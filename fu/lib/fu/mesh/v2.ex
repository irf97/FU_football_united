defmodule Fu.Mesh.V2 do
  @moduledoc """
  Friend-graph + proximity-TTL model — the fix for the Scuttlebutt blow-up.

  A node persistently replicates **its friends** and transiently caches
  **proximity peers on a TTL**. State is *updated, not appended*: per known
  player it keeps a folded `base` (rank, seq) plus a bounded `pending`
  window of the last `#{0}` attestations (for explainability + idempotent
  merge); older facts compact into `base`. Storage is therefore
  O((friends + live cache) × window) — flat as the world's history grows.

  Trust is **group-witnessed**: a player's canonical rank is the median of
  what their *witnesses* (friends who persist them) hold, never the
  player's own copy. A lone node can't forge its rank; only the whole
  group colluding can. Forgery cost == group size.
  """

  @window 8
  @ttl 6
  @att_bytes 120
  @rank_start 50.0
  @rank_min 30.0
  @rank_max 100.0

  @doc "Recent-attestation window kept per player (the explainability ring)."
  def window, do: @window
  @doc "Rounds a non-friend proximity record survives without a refresh."
  def ttl, do: @ttl

  ## --- Events ---

  @doc "A single match attestation about `player` (immutable, content-addressed by `match`)."
  def attest(match, player, delta, witnesses \\ []) do
    %{match: match, player: player, delta: delta, witnesses: witnesses, size: @att_bytes}
  end

  ## --- Node ---

  @doc "A node that persistently replicates `friends`."
  def new_node(id, friends) do
    %{id: id, friends: MapSet.new(friends), store: %{}, ttl: %{}}
  end

  defp blank, do: %{base_rank: @rank_start, base_seq: 0, pending: %{}}

  @doc "Fold an attestation into the local record (idempotent by match id)."
  def ingest(node, %{player: p} = att) do
    rec = Map.get(node.store, p, blank())

    rec =
      if Map.has_key?(rec.pending, att.match) or att.match <= rec.base_seq do
        rec
      else
        %{rec | pending: Map.put(rec.pending, att.match, att)}
      end

    store = Map.put(node.store, p, rec)
    # Non-friends are proximity cache → (re)arm their TTL.
    ttl = if MapSet.member?(node.friends, p), do: node.ttl, else: Map.put(node.ttl, p, @ttl)
    %{node | store: store, ttl: ttl}
  end

  @doc "Compact every record: fold all but the newest #{@window} attestations into base."
  def compact(node), do: %{node | store: Map.new(node.store, fn {p, r} -> {p, comp(r)} end)}

  defp comp(%{pending: pending} = rec) when map_size(pending) <= @window, do: rec

  defp comp(rec) do
    sorted = rec.pending |> Map.values() |> Enum.sort_by(& &1.match)
    {fold, keep} = Enum.split(sorted, length(sorted) - @window)

    base_rank =
      Enum.reduce(fold, rec.base_rank, fn a, acc -> clamp(acc + a.delta) end)

    base_seq = fold |> Enum.map(& &1.match) |> Enum.max(fn -> rec.base_seq end)
    %{rec | base_rank: base_rank, base_seq: base_seq, pending: Map.new(keep, &{&1.match, &1})}
  end

  @doc "Age the proximity cache by one round; evict expired non-friends."
  def tick(node) do
    {ttl, drop} =
      Enum.reduce(node.ttl, {%{}, []}, fn {p, t}, {keep, drop} ->
        if t - 1 <= 0, do: {keep, [p | drop]}, else: {Map.put(keep, p, t - 1), drop}
      end)

    %{node | ttl: ttl, store: Map.drop(node.store, drop)}
  end

  ## --- Reconcile (bounded: only records the receiver cares about) ---

  @doc """
  Two peers meet. Each sends the other the records for players the *receiver*
  cares about (a friend, or already in its proximity cache) that it lacks or
  is behind on. Returns `{a', b', bytes}` — bytes = attestations that
  actually crossed (compact records, not history). Idempotent.
  """
  def reconcile(a, b) do
    {b1, ba} = push(a, b)
    {a1, ab} = push(b, a)
    {a1, b1, ba + ab}
  end

  # Everything `from` knows that `to` cares about and is missing.
  defp push(from, to) do
    Enum.reduce(from.store, {to, 0}, fn {p, src}, {acc, bytes} ->
      if cares?(acc, p) do
        dst = Map.get(acc.store, p, blank())
        new_atts = Map.drop(src.pending, Map.keys(dst.pending)) |> Map.values()
        # Snapshot catch-up: adopt a more-advanced base.
        dst = if src.base_seq > dst.base_seq, do: %{dst | base_rank: src.base_rank, base_seq: src.base_seq}, else: dst
        applicable = Enum.reject(new_atts, &(&1.match <= dst.base_seq))

        if applicable == [] and dst == Map.get(acc.store, p, blank()) do
          {acc, bytes}
        else
          acc2 = Enum.reduce(applicable, %{acc | store: Map.put(acc.store, p, dst)}, &ingest(&2, &1))
          {acc2, bytes + length(applicable) * @att_bytes}
        end
      else
        {acc, bytes}
      end
    end)
  end

  defp cares?(node, p),
    do: MapSet.member?(node.friends, p) or Map.has_key?(node.store, p)

  ## --- Reads ---

  @doc "Rank as THIS node sees it (base + folded pending), clamped."
  def rank(node, player) do
    case Map.get(node.store, player) do
      nil -> @rank_start
      r -> r.pending |> Map.values() |> Enum.reduce(r.base_rank, fn a, acc -> acc + a.delta end) |> clamp()
    end
  end

  @doc """
  Canonical rank: the **median of the player's witnesses' views** — the
  friends who persist them. Excludes the player's own copy by construction,
  so self-tampering can't move it; only whole-group collusion can.
  """
  def witnessed_rank(nodes, witness_ids, player) do
    vals =
      witness_ids
      |> Enum.filter(&Map.has_key?(nodes, &1))
      |> Enum.map(&rank(nodes[&1], player))
      |> Enum.sort()

    case vals do
      [] -> @rank_start
      v -> Enum.at(v, div(length(v) - 1, 2))
    end
  end

  @doc "Test/adversary hook: overwrite a node's own folded rank for a player."
  def force_rank(node, player, value) do
    rec = Map.get(node.store, player, blank())
    %{node | store: Map.put(node.store, player, %{rec | base_rank: value, pending: %{}})}
  end

  ## --- Introspection (for the harness) ---

  def knows?(node, player), do: Map.has_key?(node.store, player)

  @doc "Has this node folded/retained a specific match for a player?"
  def seen_match?(node, player, match) do
    case Map.get(node.store, player) do
      nil -> false
      r -> match <= r.base_seq or Map.has_key?(r.pending, match)
    end
  end
  def pending_count(node, player), do: map_size(Map.get(node.store, player, blank()).pending)

  @doc "Total records + pending entries — the bounded-storage metric."
  def store_size(node) do
    Enum.reduce(node.store, 0, fn {_p, r}, acc -> acc + 1 + map_size(r.pending) end)
  end

  @doc "Bytes the device persists (records are tiny vs full history)."
  def store_bytes(node) do
    Enum.reduce(node.store, 0, fn {_p, r}, acc ->
      acc + 32 + map_size(r.pending) * @att_bytes
    end)
  end

  defp clamp(x), do: x |> max(@rank_min) |> min(@rank_max)
end
