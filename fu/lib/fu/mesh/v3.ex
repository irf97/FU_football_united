defmodule Fu.Mesh.V3 do
  @moduledoc """
  v2 (bounded friend-graph + proximity store) plus the routing that makes
  witness delivery actually work:

    * **Subject-directed relay** — every record carries the subject's
      declared witness set; a carrier forwards it toward those witnesses on
      contact even though the carrier itself doesn't 'care' about the
      subject. Facts flow *to the people who vouch for you*.
    * **Proximity-over-time → acquaintance** — repeated co-presence raises a
      closeness score; crossing a threshold promotes a peer to a
      long-retention tier; absence decays it back to stranger.
    * **Closeness filter** — you never blind-flood a stranger's data to an
      unrelated peer. You relay toward witnesses, or share about subjects
      you're close to. That keeps gossip (and storage) bounded.

  Trust tiers for retention: friend (permanent) > acquaintance (long) >
  stranger (short TTL). Canonical rank is still the witnessed median —
  self-tamper-proof, group-collusion-only.
  """

  @window 8
  @stranger_ttl 4
  @acq_threshold 3
  @acq_decay 6
  @att_bytes 120
  @rank_start 50.0
  @rank_min 30.0
  @rank_max 100.0

  def window, do: @window
  def stranger_ttl, do: @stranger_ttl
  def acq_threshold, do: @acq_threshold
  def acq_decay, do: @acq_decay

  ## --- Events ---

  @doc "Attestation about `player`; `witnesses` = the subject's declared witness set."
  def attest(match, player, delta, witnesses \\ []) do
    %{match: match, player: player, delta: delta, witnesses: witnesses, size: @att_bytes}
  end

  ## --- Node ---

  def new_node(id, friends) do
    %{
      id: id,
      friends: MapSet.new(friends),
      store: %{},
      age: %{},
      prox: %{}
    }
  end

  defp blank, do: %{base_rank: @rank_start, base_seq: 0, pending: %{}, witnesses: MapSet.new()}

  @doc "Fold an attestation in (idempotent by match id); refresh the subject's age clock."
  def ingest(node, %{player: p} = att) do
    rec = Map.get(node.store, p, blank())

    rec =
      if Map.has_key?(rec.pending, att.match) or att.match <= rec.base_seq do
        rec
      else
        %{rec | pending: Map.put(rec.pending, att.match, att)}
      end

    rec = %{rec | witnesses: MapSet.union(rec.witnesses, MapSet.new(att.witnesses))}
    %{node | store: Map.put(node.store, p, rec), age: Map.put(node.age, p, 0)}
  end

  @doc "Record a proximity encounter with `peer` (raises closeness)."
  def met(node, peer) do
    {s, _idle} = Map.get(node.prox, peer, {0, 0})
    %{node | prox: Map.put(node.prox, peer, {s + 1, 0})}
  end

  @doc """
  Is `peer` a sustained acquaintance? Enough encounters to cross the
  threshold AND seen recently enough that the bond hasn't lapsed (absence,
  not per-tick erosion, is what decays it — that's "proximity over time").
  """
  def acquaintance?(node, peer) do
    case Map.get(node.prox, peer) do
      {s, idle} -> s >= @acq_threshold and idle <= @acq_decay
      _ -> false
    end
  end

  @doc "One round of decay: age every record, lapse stale bonds, evict cold strangers."
  def tick(node) do
    prox =
      node.prox
      |> Enum.map(fn {peer, {s, idle}} -> {peer, {s, idle + 1}} end)
      |> Enum.reject(fn {_p, {_s, idle}} -> idle > @acq_decay end)
      |> Map.new()

    node = %{node | prox: prox}

    {age, drop} =
      Enum.reduce(node.age, {%{}, []}, fn {p, a}, {keep, drop} ->
        cond do
          MapSet.member?(node.friends, p) -> {Map.put(keep, p, a + 1), drop}
          acquaintance?(node, p) -> {Map.put(keep, p, a + 1), drop}
          a + 1 > @stranger_ttl -> {keep, [p | drop]}
          true -> {Map.put(keep, p, a + 1), drop}
        end
      end)

    %{node | age: age, store: Map.drop(node.store, drop)}
  end

  @doc "Fold all but the newest #{@window} attestations of every record into base."
  def compact(node), do: %{node | store: Map.new(node.store, fn {p, r} -> {p, comp(r)} end)}

  defp comp(%{pending: pending} = rec) when map_size(pending) <= @window, do: rec

  defp comp(rec) do
    sorted = rec.pending |> Map.values() |> Enum.sort_by(& &1.match)
    {fold, keep} = Enum.split(sorted, length(sorted) - @window)
    base_rank = Enum.reduce(fold, rec.base_rank, fn a, acc -> clamp(acc + a.delta) end)
    base_seq = fold |> Enum.map(& &1.match) |> Enum.max(fn -> rec.base_seq end)
    %{rec | base_rank: base_rank, base_seq: base_seq, pending: Map.new(keep, &{&1.match, &1})}
  end

  ## --- Reconcile: subject-directed relay + closeness filter ---

  def reconcile(a, b) do
    {b1, ba} = push(a, b)
    {a1, ab} = push(b, a)
    {a1, b1, ba + ab}
  end

  # `from` sends `to` every record `to` should get:
  #   • cares?(to, S)                       — to is S's friend / already knows S
  #   • to ∈ S.witnesses                    — subject-directed relay
  #   • from is close to S (friend/acq)     — willing to vouch/share (filter)
  # Anything else (a stranger's data to an unrelated peer) is NOT forwarded.
  defp push(from, to) do
    Enum.reduce(from.store, {to, 0}, fn {s, src}, {acc, bytes} ->
      relay? =
        cares?(acc, s) or
          MapSet.member?(src.witnesses, acc.id) or
          MapSet.member?(from.friends, s) or
          acquaintance?(from, s)

      if relay? do
        dst = Map.get(acc.store, s, blank())
        dst = if src.base_seq > dst.base_seq, do: %{dst | base_rank: src.base_rank, base_seq: src.base_seq}, else: dst

        new =
          src.pending
          |> Map.drop(Map.keys(dst.pending))
          |> Map.values()
          |> Enum.reject(&(&1.match <= dst.base_seq))

        if new == [] and dst == Map.get(acc.store, s, blank()) do
          {acc, bytes}
        else
          acc2 =
            Enum.reduce(new, %{acc | store: Map.put(acc.store, s, dst)}, &ingest(&2, &1))

          {acc2, bytes + length(new) * @att_bytes}
        end
      else
        {acc, bytes}
      end
    end)
  end

  defp cares?(node, s),
    do: MapSet.member?(node.friends, s) or Map.has_key?(node.store, s)

  ## --- Reads ---

  def rank(node, player) do
    case Map.get(node.store, player) do
      nil -> @rank_start
      r -> r.pending |> Map.values() |> Enum.reduce(r.base_rank, fn a, acc -> acc + a.delta end) |> clamp()
    end
  end

  @doc "Canonical rank = median of the player's witnesses' views (never self)."
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

  ## --- Signed events (protocol-grade identity, Fu.Mesh.Identity) ---

  @doc """
  Verify-then-fold. An attestation that is not validly signed by its
  declared author is dropped — never ingested, never relayed. This is the
  faithful-reference path: the Rust runtime must do exactly this.
  """
  def ingest_signed(node, att) do
    if Fu.Mesh.Identity.verified?(att), do: ingest(node, att), else: node
  end

  ## --- Friendless bootstrap: provisional witnesses ---

  @doc """
  Nodes that can *provisionally* vouch for `subject`: any node (≠ subject)
  that regards `subject` as a sustained acquaintance and actually holds
  their record. This is the bootstrap path for the friendless — repeated
  co-presence earns recoverable witnesses without needing declared friends.
  """
  def provisional_witnesses(nodes, subject) do
    for {id, node} <- nodes,
        id != subject,
        acquaintance?(node, subject),
        knows?(node, subject),
        do: id
  end

  @doc """
  Canonical rank with bootstrap fallback: use friend-witnesses when any
  hold the record; otherwise fall back to the median over provisional
  (acquaintance) witnesses. Still self-excluded, still group-collusion-only.
  """
  def recoverable_rank(nodes, friend_ids, subject) do
    holding_friends = Enum.filter(friend_ids, &(Map.has_key?(nodes, &1) and knows?(nodes[&1], subject)))

    if holding_friends != [] do
      witnessed_rank(nodes, holding_friends, subject)
    else
      witnessed_rank(nodes, provisional_witnesses(nodes, subject), subject)
    end
  end

  ## --- Introspection (harness) ---

  def knows?(node, player), do: Map.has_key?(node.store, player)

  @doc "The signed attestations this node currently holds for a player (for relay)."
  def held_attestations(node, player) do
    case Map.get(node.store, player) do
      nil -> []
      r -> Map.values(r.pending)
    end
  end

  def seen_match?(node, player, match) do
    case Map.get(node.store, player) do
      nil -> false
      r -> match <= r.base_seq or Map.has_key?(r.pending, match)
    end
  end

  def pending_count(node, player), do: map_size(Map.get(node.store, player, blank()).pending)

  def store_size(node),
    do: Enum.reduce(node.store, 0, fn {_p, r}, acc -> acc + 1 + map_size(r.pending) end)

  def store_bytes(node),
    do: Enum.reduce(node.store, 0, fn {_p, r}, acc -> acc + 40 + map_size(r.pending) * @att_bytes end)

  defp clamp(x), do: x |> max(@rank_min) |> min(@rank_max)
end
