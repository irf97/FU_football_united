defmodule Fu.Matching do
  @moduledoc """
  Auto-match: proposes the queues a player should join, derived from their
  availability windows and position preferences (spec §2.6, §2.13 item 8).

  Builds on the position-aware browser (`Fu.Queues.browse/1`, already
  distance/region-filtered), keeps only queues that fall inside one of the
  player's availability windows (spec §2.6), then scores what's left so the
  best three rise to the top — answering "can I play soon?" (spec §2.1) with
  the 8v8 rated match as the aspirational anchor (spec §2.11).
  """

  alias Fu.Accounts

  # --- Scoring weights (spec §2.6) ---
  # The queue needs the player's primary position — the strongest signal.
  @w_needs_primary 100
  # A primary/secondary slot is still open (player would get a real role).
  @w_open_pref 50
  # Rated 8v8 — the aspirational anchor (spec §2.11).
  @w_rated 20
  # Up to this many points for rank closeness (closer avg_rank = higher).
  @w_rank_close 30
  # Neutral rank score when the queue has no members yet (avg_rank nil).
  @w_rank_neutral 15
  # Up to this many points for a sooner kickoff — "can I play soon?" (spec §2.1).
  @w_soon 25
  # Penalty: the queue is in its commitment lock, harder to commit late.
  @w_locked -40

  # Rank delta beyond which the closeness bonus bottoms out at zero.
  @rank_span 20
  # Time horizon (seconds) over which the "sooner" bonus decays to zero (7d).
  @soon_horizon 7 * 24 * 3600

  @doc """
  Suggests up to 3 queues the player should join, ranked best-first
  (spec §2.6). `opts`:

    * `:limit` — how many cards to return (default 3)

  Returns a list of `Fu.Queues.browse/1` card maps.
  """
  def suggest(player, opts \\ []) do
    limit = Keyword.get(opts, :limit, 3)

    player
    |> Fu.Queues.browse()
    |> Enum.filter(&Accounts.available_at?(player, &1.scheduled_at))
    |> Enum.sort_by(&score(&1, player), :desc)
    |> Enum.take(limit)
  end

  @doc """
  Auto-queue "pops" — every queue the player can *accept right now*: open or
  in-lock, not already joined, with a slot their position prefs (or fill
  mode) can take, region-filtered. Best-first by the same scorer as
  `suggest/2`. Unlike `suggest/2` this ignores availability windows: the
  player explicitly pressed QUEUE, so we actively hunt anything that fits.
  """
  def pops(player) do
    joined = Fu.Queues.joined_queue_ids(player)

    player
    |> Fu.Queues.browse()
    |> Enum.reject(&MapSet.member?(joined, &1.queue.id))
    |> Enum.filter(&Fu.Queues.pick_position(&1.queue, player))
    |> Enum.sort_by(&score(&1, player), :desc)
  end

  # Total card score for `player` (spec §2.6). Higher is a better suggestion.
  defp score(card, player) do
    needs_primary(card) +
      open_pref(card, player) +
      rated(card) +
      rank_close(card, player) +
      soon(card) +
      locked(card)
  end

  defp needs_primary(%{needs_my_position: true}), do: @w_needs_primary
  defp needs_primary(_), do: 0

  # An open slot for the player's primary OR secondary position?
  defp open_pref(card, player) do
    prefs =
      [player.primary_position, player.secondary_position]
      |> Enum.reject(&(&1 in [nil, ""]))

    if Enum.any?(prefs, &open?(card.fill, &1)), do: @w_open_pref, else: 0
  end

  defp open?(fill, position) do
    case Map.get(fill, position) do
      %{filled: f, capacity: c} -> f < c
      _ -> false
    end
  end

  defp rated(%{rated: true}), do: @w_rated
  defp rated(_), do: 0

  # Closer avg_rank to the player's rank => higher (nil => neutral).
  defp rank_close(%{avg_rank: nil}, _player), do: @w_rank_neutral

  defp rank_close(%{avg_rank: avg}, player) do
    delta = abs(avg - player.rank)
    closeness = max(0.0, 1.0 - delta / @rank_span)
    round(@w_rank_close * closeness)
  end

  # Sooner kickoff => higher; decays linearly to 0 over @soon_horizon.
  defp soon(%{scheduled_at: at}) do
    secs = max(DateTime.diff(at, DateTime.utc_now()), 0)
    nearness = max(0.0, 1.0 - secs / @soon_horizon)
    round(@w_soon * nearness)
  end

  defp locked(%{locked: true}), do: @w_locked
  defp locked(_), do: 0
end
