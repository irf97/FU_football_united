defmodule Fu.Mesh do
  @moduledoc """
  In-memory model of the P2P proximity-gossip substrate (no server, no DB).

  Mirrors the real app's shape: every node keeps an **append-only log** of
  immutable, content-addressed events; peers reconcile by **anti-entropy**
  (exchange only what the other lacks) on physical encounter. Rank is a pure
  fold over the local log — there is no global authority, only "rank
  according to the events this device has witnessed", which converges.

  This module is the trustworthy core the scale harness measures. It is
  deliberately pure and deterministic (no processes, no time, no DB) so
  10k-node runs are fast and reproducible.

  ## Event sizing (for the bandwidth question)

  A signed event on the wire ≈ a 96-byte envelope (id + author key + sig)
  plus 24 bytes per participant rank-delta. An 8v8 match (16 players) is
  therefore ~480 B — the unit that has to cross an NFC tap or BLE window.
  """

  @envelope_bytes 96
  @bytes_per_delta 24
  @rank_start 50.0
  @rank_min 30.0
  @rank_max 100.0

  ## --- Events (immutable, content-addressed) ---

  @doc """
  A match event: `id` is content-addressed (`{:match, match_id}`), so every
  participant that records the same match holds the *same* event — merge
  dedups it for free. `deltas` is `%{player_id => rank_delta}`.
  """
  def match_event(match_id, %{} = deltas) do
    %{
      id: {:match, match_id},
      kind: :match,
      deltas: deltas,
      size: @envelope_bytes + @bytes_per_delta * map_size(deltas)
    }
  end

  @doc "Wire size of an event in bytes."
  def event_size(%{size: s}), do: s

  ## --- Node = identity + append-only log ---

  @doc "A fresh node (its log is a `%{event_id => event}` store)."
  def new_node(id), do: %{id: id, store: %{}}

  @doc "Append an event. Idempotent — re-appending an id is a no-op."
  def append(%{store: store} = node, %{id: id} = event),
    do: %{node | store: Map.put_new(store, id, event)}

  @doc "Append many events."
  def merge(node, events), do: Enum.reduce(events, node, &append(&2, &1))

  @doc "Number of events in the local log."
  def log_count(%{store: store}), do: map_size(store)

  @doc "The set of event ids the node holds."
  def log_ids(%{store: store}), do: store |> Map.keys() |> MapSet.new()

  @doc "Total bytes the local log occupies on this device."
  def log_bytes(%{store: store}),
    do: store |> Map.values() |> Enum.reduce(0, &(&1.size + &2))

  ## --- Anti-entropy reconcile (the proximity exchange) ---

  @doc """
  Two peers meet and reconcile: each receives exactly the events the other
  has and it lacks. Returns `{a', b', bytes}` where `bytes` is the total
  payload that crossed the link (what an NFC/BLE window must carry).

  Convergent and idempotent: a second reconcile of the same pair moves 0
  bytes. (The id-digest exchange that decides the delta is ~8 B/event and
  is folded into the byte total as negligible vs payload here.)
  """
  def reconcile(%{store: sa} = a, %{store: sb} = b) do
    only_b = Map.drop(sb, Map.keys(sa))
    only_a = Map.drop(sa, Map.keys(sb))

    bytes =
      (only_b |> Map.values() |> Enum.reduce(0, &(&1.size + &2))) +
        (only_a |> Map.values() |> Enum.reduce(0, &(&1.size + &2)))

    {%{a | store: Map.merge(sa, only_b)}, %{b | store: Map.merge(sb, only_a)}, bytes}
  end

  ## --- Rank: a pure fold over the local log (no authority) ---

  @doc """
  The player's rank *as this node sees it* — `#{@rank_start}` plus the sum
  of every delta in this node's log that names them, clamped to
  `[#{@rank_min}, #{@rank_max}]`. Deterministic in the log; addition
  commutes, so order of receipt doesn't matter (CRDT-ish).
  """
  def rank(%{store: store}, player_id) do
    sum =
      store
      |> Map.values()
      |> Enum.reduce(0.0, fn %{deltas: d}, acc -> acc + Map.get(d, player_id, 0.0) end)

    (@rank_start + sum) |> max(@rank_min) |> min(@rank_max)
  end

  @doc "An omniscient node holding every event — the centralized oracle."
  def oracle(events), do: merge(new_node(:oracle), events)
end
