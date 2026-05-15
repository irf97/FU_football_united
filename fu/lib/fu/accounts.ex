defmodule Fu.Accounts do
  @moduledoc "Players, phone-OTP auth, position prefs, availability (spec §2.6, §2.13 S1)."

  import Ecto.Query
  alias Fu.Repo
  alias Fu.Accounts.{Player, OtpCode, AvailabilityWindow}

  @otp_ttl_seconds 600

  ## --- Phone OTP auth (spec §2.13 Surface 1) ---

  @doc """
  Generates a 6-digit OTP for `phone`, stores it, and "sends" it via the SMS
  stub. Returns `{:ok, code}` — in v1 the code is logged, not texted.
  """
  def request_otp(phone) do
    phone = normalize_phone(phone)
    code = 100_000..999_999 |> Enum.random() |> Integer.to_string()
    expires_at = DateTime.utc_now() |> DateTime.add(@otp_ttl_seconds, :second) |> DateTime.truncate(:second)

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

  @doc "Verifies an OTP and returns the (created-if-needed) player."
  def verify_otp(phone, code) do
    phone = normalize_phone(phone)
    now = DateTime.utc_now()

    query =
      from o in OtpCode,
        where: o.phone == ^phone and o.code == ^code and is_nil(o.consumed_at) and o.expires_at > ^now,
        order_by: [desc: o.id],
        limit: 1

    case Repo.one(query) do
      nil ->
        {:error, :invalid_code}

      otp ->
        otp
        |> OtpCode.changeset(%{consumed_at: DateTime.truncate(now, :second)})
        |> Repo.update()

        {:ok, get_or_create_player(phone)}
    end
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

  def update_profile(%Player{} = player, attrs) do
    player |> Player.profile_changeset(attrs) |> Repo.update()
  end

  def change_profile(%Player{} = player, attrs \\ %{}),
    do: Player.profile_changeset(player, attrs)

  def suspended?(%Player{suspended_until: nil}), do: false

  def suspended?(%Player{suspended_until: until}),
    do: DateTime.compare(until, DateTime.utc_now()) == :gt

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
