defmodule Fu.Accounts do
  @moduledoc "Players, phone-OTP auth, position prefs, availability (spec §2.6, §2.13 S1)."

  import Ecto.Query
  alias Fu.Repo
  alias Fu.Accounts.{Player, OtpCode, AvailabilityWindow}

  @otp_ttl_seconds 600

  # OTP abuse resistance (AUDIT #1). A real attacker shouldn't be able to
  # SMS-bomb a number, fill the table, or brute-force a 6-digit code.
  @max_requests_per_window 5
  @request_window_seconds 900
  @max_verify_attempts 5

  ## --- Phone OTP auth (spec §2.13 Surface 1) ---

  @doc """
  Generates a 6-digit OTP for `phone`, stores it, and "sends" it via the SMS
  adapter. Rate-limited to #{@max_requests_per_window} requests per phone per
  #{div(@request_window_seconds, 60)} minutes — returns `{:error, :rate_limited}`
  past the cap. Returns `{:ok, code}` (in v1 the code is logged, not texted).
  """
  def request_otp(phone) do
    phone = normalize_phone(phone)

    if rate_limited?(phone) do
      {:error, :rate_limited}
    else
      code = 100_000..999_999 |> Enum.random() |> Integer.to_string()

      expires_at =
        DateTime.utc_now() |> DateTime.add(@otp_ttl_seconds, :second) |> DateTime.truncate(:second)

      %OtpCode{}
      |> OtpCode.changeset(%{phone: phone, code: code, expires_at: expires_at})
      |> Repo.insert()
      |> case do
        {:ok, _} ->
          Fu.SMS.deliver(phone, "Your Football United code is #{code}")
          {:ok, code}

        err ->
          err
      end
    end
  end

  defp rate_limited?(phone) do
    since =
      DateTime.utc_now()
      |> DateTime.add(-@request_window_seconds, :second)
      |> DateTime.truncate(:second)

    recent =
      from(o in OtpCode, where: o.phone == ^phone and o.inserted_at >= ^since)
      |> Repo.aggregate(:count, :id)

    recent >= @max_requests_per_window
  end

  @doc """
  Verifies an OTP and returns the (created-if-needed) player. Each wrong guess
  against the live code increments its attempt counter; after
  #{@max_verify_attempts} the code is burned (`{:error, :locked}`) so a 6-digit
  secret can't be brute-forced. Replay is still blocked via `consumed_at`.
  """
  def verify_otp(phone, code) do
    phone = normalize_phone(phone)
    now = DateTime.utc_now()

    active =
      from(o in OtpCode,
        where: o.phone == ^phone and is_nil(o.consumed_at) and o.expires_at > ^now,
        order_by: [desc: o.id],
        limit: 1
      )

    case Repo.one(active) do
      nil ->
        {:error, :invalid_code}

      %OtpCode{attempts: a} = otp when a >= @max_verify_attempts ->
        burn(otp, now)
        {:error, :locked}

      %OtpCode{code: ^code} = otp ->
        burn(otp, now)
        {:ok, get_or_create_player(phone)}

      otp ->
        attempts = otp.attempts + 1
        changes = %{attempts: attempts}

        changes =
          if attempts >= @max_verify_attempts,
            do: Map.put(changes, :consumed_at, DateTime.truncate(now, :second)),
            else: changes

        otp |> OtpCode.changeset(changes) |> Repo.update()
        if attempts >= @max_verify_attempts, do: {:error, :locked}, else: {:error, :invalid_code}
    end
  end

  defp burn(%OtpCode{} = otp, now) do
    otp
    |> OtpCode.changeset(%{consumed_at: DateTime.truncate(now, :second)})
    |> Repo.update()
  end

  defp get_or_create_player(phone) do
    case Repo.get_by(Player, phone: phone) do
      nil ->
        {:ok, player} =
          %Player{} |> Player.registration_changeset(%{phone: phone}) |> Repo.insert()

        player

      player ->
        player
    end
  end

  defp normalize_phone(phone), do: phone |> to_string() |> String.replace(~r/[^\d+]/, "")

  ## --- Players (spec §2.6) ---

  def get_player!(id), do: Repo.get!(Player, id)
  def get_player(id), do: Repo.get(Player, id)

  @doc """
  The display label for a main position: the player's chosen default
  sub-position for it, falling back to the main label. GK has no variant.
  Display/preference only — matchmaking still uses the main position.
  """
  def sub_label(%Player{} = p, "DEF"), do: blankish(p.def_sub) || "DEF"
  def sub_label(%Player{} = p, "MID"), do: blankish(p.mid_sub) || "MID"
  def sub_label(%Player{} = p, "FWD"), do: blankish(p.fwd_sub) || "FWD"
  def sub_label(%Player{}, "GK"), do: "GK"
  def sub_label(%Player{}, other), do: other

  defp blankish(v) when v in [nil, ""], do: nil
  defp blankish(v), do: v

  @doc "Player age in full years from `birthdate`, or `nil` if unset."
  def age(%Player{birthdate: nil}), do: nil

  def age(%Player{birthdate: %Date{} = dob}) do
    today = Date.utc_today()
    before_birthday? = {today.month, today.day} < {dob.month, dob.day}
    today.year - dob.year - if(before_birthday?, do: 1, else: 0)
  end

  def age(_), do: nil

  def update_profile(%Player{} = player, attrs) do
    player |> Player.profile_changeset(attrs) |> Repo.update()
  end

  def change_profile(%Player{} = player, attrs \\ %{}),
    do: Player.profile_changeset(player, attrs)

  def suspended?(%Player{suspended_until: nil}), do: false

  def suspended?(%Player{suspended_until: until}),
    do: DateTime.compare(until, DateTime.utc_now()) == :gt

  @doc """
  Suspends a player for `days`, stacking onto any existing future
  suspension (never shortens it). Returns the new `suspended_until`.
  """
  def suspend_for(%Player{} = player, days) when is_integer(days) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    base = if player.suspended_until && DateTime.compare(player.suspended_until, now) == :gt,
             do: player.suspended_until,
             else: now

    until = DateTime.add(base, days * 86_400, :second)

    {:ok, _} =
      Repo.get!(Player, player.id)
      |> Ecto.Changeset.change(suspended_until: until)
      |> Repo.update()

    until
  end

  ## --- Availability windows (spec §2.6) ---

  def list_availability(%Player{id: pid}) do
    from(w in AvailabilityWindow, where: w.player_id == ^pid, order_by: [asc: w.weekday, asc: w.date])
    |> Repo.all()
  end

  def add_availability(%Player{id: pid}, attrs) do
    %AvailabilityWindow{}
    |> AvailabilityWindow.changeset(Map.put(attrs, "player_id", pid))
    |> Repo.insert()
  end

  def delete_availability(%Player{id: pid}, id) do
    case Repo.get_by(AvailabilityWindow, id: id, player_id: pid) do
      nil -> {:error, :not_found}
      w -> Repo.delete(w)
    end
  end

  @doc "Does the player have an availability window covering `dt` (spec §2.6)?"
  def available_at?(%Player{} = player, %DateTime{} = dt) do
    windows = list_availability(player)
    wday = Date.day_of_week(DateTime.to_date(dt)) |> rem(7)
    t = DateTime.to_time(dt)
    d = DateTime.to_date(dt)

    Enum.any?(windows, fn w ->
      time_ok = Time.compare(t, w.start_time) != :lt and Time.compare(t, w.end_time) != :gt

      cond do
        w.kind == "recurring" -> w.weekday == wday and time_ok
        w.kind == "oneoff" -> w.date == d and time_ok
        true -> false
      end
    end)
  end
end
