defmodule Fu.Queues do
  @moduledoc """
  Queue creation, the position-aware browser, and fill mechanics
  (spec §2.1, §2.2, §2.4, §2.11). Join/leave land in Phase 2.
  """

  import Ecto.Query
  alias Fu.Repo
  alias Fu.Queues.{Queue, QueueSlot}
  alias Fu.{Positions, Geo}

  @lock_seconds 3 * 3600

  ## --- Creation (spec §2.11 operator queue creation, S19) ---

  @doc """
  Creates a queue and its per-position slots derived from the formation.
  `rated` is forced true iff format is 8v8 (spec §2.11 load-bearing rule).
  """
  def create_queue(attrs) do
    attrs = normalize(attrs)
    formation = attrs["formation"] || Positions.default_formation(attrs["format"])
    attrs = Map.merge(attrs, %{"formation" => formation, "rated" => Positions.rated?(attrs["format"])})

    Repo.transaction(fn ->
      queue =
        %Queue{} |> Queue.changeset(attrs) |> Repo.insert!()

      for {pos, cap} <- Positions.quotas(formation) do
        %QueueSlot{}
        |> QueueSlot.changeset(%{queue_id: queue.id, position: pos, capacity: cap})
        |> Repo.insert!()
      end

      queue
    end)
  end

  defp normalize(attrs) do
    Map.new(attrs, fn {k, v} -> {to_string(k), v} end)
  end

  def get_queue!(id) do
    Queue
    |> Repo.get!(id)
    |> Repo.preload([:field, :slots, memberships: :player])
  end

  ## --- Lifecycle (spec §2.4) ---

  @doc "Seconds until kickoff (negative once started)."
  def seconds_to_kickoff(%Queue{scheduled_at: at}),
    do: DateTime.diff(at, DateTime.utc_now())

  @doc "In the 3-hour commitment lock window (spec §2.4)?"
  def locked?(%Queue{} = q), do: seconds_to_kickoff(q) <= @lock_seconds

  ## --- Fill status (spec §2.2 position-by-position) ---

  @doc """
  Per-position fill: `%{"GK" => %{filled: 1, capacity: 2}, ...}`.
  Counts only `queued` memberships by declared position.
  """
  def fill_status(%Queue{} = q) do
    q = Repo.preload(q, [:slots, :memberships])
    counts = Enum.frequencies_by(active(q.memberships), & &1.declared_position)

    Map.new(q.slots, fn s ->
      {s.position, %{filled: Map.get(counts, s.position, 0), capacity: s.capacity}}
    end)
  end

  @doc "Total queued / total capacity."
  def fill_ratio(%Queue{} = q) do
    fs = fill_status(q)
    filled = fs |> Map.values() |> Enum.map(& &1.filled) |> Enum.sum()
    cap = fs |> Map.values() |> Enum.map(& &1.capacity) |> Enum.sum()
    if cap == 0, do: 0.0, else: filled / cap
  end

  @doc "Does the queue still have an open slot for `position`?"
  def needs_position?(%Queue{} = q, position) do
    case fill_status(q)[position] do
      %{filled: f, capacity: c} -> f < c
      _ -> false
    end
  end

  defp active(memberships), do: Enum.filter(memberships, &(&1.status == "queued"))

  ## --- The browser (spec §2.1, §2.13 Surface 3, S21) ---

  @doc """
  Returns browsable queue *cards* for a player. `filters` keys (all optional):

    * `:time` — `"today" | "tomorrow" | "week" | "weekend"`
    * `:max_km` — distance radius (defaults to player's `queue_region_km`)
    * `:needs_my_position` — only queues that still need the player's primary
    * `:rank_window` — only queues whose avg rank is within ±N of the player
    * `:format` — exact format string
    * `:rated_only` — only 8v8 rated queues

  Sort: queues needing the player's position first, then time-ascending
  (spec §2.1).
  """
  def browse(player, filters \\ %{}) do
    now = DateTime.utc_now()

    queues =
      from(q in Queue,
        where: q.state in ["open", "locked"] and q.scheduled_at > ^now,
        order_by: [asc: q.scheduled_at]
      )
      |> Repo.all()
      |> Repo.preload([:field, :slots, memberships: :player])

    queues
    |> Enum.map(&card(&1, player))
    |> Enum.filter(&passes?(&1, player, filters))
    |> Enum.sort_by(fn c -> {if(c.needs_my_position, do: 0, else: 1), DateTime.to_unix(c.scheduled_at)} end)
  end

  defp card(%Queue{} = q, player) do
    fs = fill_status(q)
    ranks = q.memberships |> active() |> Enum.map(& &1.player.rank)
    avg_rank = if ranks == [], do: nil, else: Enum.sum(ranks) / length(ranks)

    %{
      queue: q,
      field: q.field,
      scheduled_at: q.scheduled_at,
      format: q.format,
      formation: q.formation,
      rated: q.rated,
      fill: fs,
      fill_ratio: fill_ratio(q),
      avg_rank: avg_rank,
      seconds_to_lock: seconds_to_kickoff(q) - @lock_seconds,
      locked: locked?(q),
      distance_km:
        Geo.distance_km(player.home_lat, player.home_lng, q.field.lat, q.field.lng),
      needs_my_position: needs_position?(q, player.primary_position)
    }
  end

  defp passes?(card, player, filters) do
    time_ok?(card, filters[:time]) and
      distance_ok?(card, player, filters[:max_km]) and
      position_ok?(card, filters[:needs_my_position]) and
      rank_ok?(card, player, filters[:rank_window]) and
      format_ok?(card, filters[:format]) and
      rated_ok?(card, filters[:rated_only])
  end

  defp time_ok?(_card, nil), do: true

  defp time_ok?(card, window) do
    d = DateTime.to_date(card.scheduled_at)
    today = Date.utc_today()

    case window do
      "today" -> d == today
      "tomorrow" -> d == Date.add(today, 1)
      "week" -> Date.diff(d, today) in 0..7
      "weekend" -> Date.day_of_week(d) in [6, 7]
      _ -> true
    end
  end

  defp distance_ok?(card, player, max_km) do
    limit = max_km || player.queue_region_km
    is_nil(card.distance_km) or card.distance_km <= limit
  end

  defp position_ok?(_card, val) when val in [nil, false], do: true
  defp position_ok?(card, _), do: card.needs_my_position

  defp rank_ok?(_card, _player, nil), do: true
  defp rank_ok?(%{avg_rank: nil}, _player, _), do: true

  defp rank_ok?(card, player, window),
    do: abs(card.avg_rank - player.rank) <= window

  defp format_ok?(_card, nil), do: true
  defp format_ok?(card, fmt), do: card.format == fmt

  defp rated_ok?(_card, val) when val in [nil, false], do: true
  defp rated_ok?(card, _), do: card.rated
end
