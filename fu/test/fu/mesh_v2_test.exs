defmodule Fu.MeshV2Test do
  @moduledoc """
  Invariants of the friend-graph + proximity-TTL model that solves the
  Scuttlebutt blow-up. The harness numbers are only trustworthy if these
  hold: bounded store under compaction, idempotent ingest, TTL eviction of
  non-friends, friends persisted forever, and — the load-bearing one —
  canonical rank is read from a player's *witnesses*, never self-held, so a
  lone node can't forge it but a colluding whole group can.
  """
  use ExUnit.Case, async: true

  alias Fu.Mesh.V2

  defp att(match, player, delta, witnesses \\ []),
    do: V2.attest(match, player, delta, witnesses)

  test "ingest is idempotent — the same match attestation never double-counts" do
    n = V2.new_node("a", [])
    a = att(1, "p", 1.5)

    n1 = n |> V2.ingest(a) |> V2.ingest(a) |> V2.ingest(a)
    assert_in_delta V2.rank(n1, "p"), 51.5, 1.0e-9
  end

  test "store stays bounded: K recent attestations max per player; older compact into base" do
    k = V2.window()
    n = V2.new_node("a", ["p"])

    n =
      Enum.reduce(1..(k * 5), n, fn i, acc ->
        acc |> V2.ingest(att(i, "p", 1.0)) |> V2.compact()
      end)

    # Pending is capped at K regardless of how many matches happened …
    assert V2.pending_count(n, "p") <= k
    # … but the rank is still correct (base folded the rest): 50 + 40×1.0.
    assert_in_delta V2.rank(n, "p"), 90.0, 1.0e-9

    # And the band still clamps under a big swing.
    big = V2.new_node("z", ["p"]) |> V2.ingest(att(99, "p", 999.0)) |> V2.compact()
    assert V2.rank(big, "p") == 100.0
  end

  test "tick evicts non-friend proximity records after TTL; friends persist forever" do
    n = V2.new_node("a", ["friend"])
    n = n |> V2.ingest(att(1, "friend", 1.0)) |> V2.ingest(att(1, "stranger", 1.0))

    assert V2.knows?(n, "stranger")
    n = Enum.reduce(1..(V2.ttl() + 1), n, fn _, acc -> V2.tick(acc) end)

    refute V2.knows?(n, "stranger")
    assert V2.knows?(n, "friend")
  end

  test "reconcile only moves records the receiver cares about, idempotent, and delivers" do
    # b is p's friend (a witness); a just played with p and carries the fact.
    a = V2.new_node("a", []) |> V2.ingest(att(7, "p", 1.5))
    b = V2.new_node("b", ["p"])

    {a1, b1, bytes} = V2.reconcile(a, b)
    assert bytes > 0
    assert_in_delta V2.rank(b1, "p"), 51.5, 1.0e-9

    {_a2, _b2, bytes2} = V2.reconcile(a1, b1)
    assert bytes2 == 0
  end

  test "CANONICAL: rank is witnessed by friends, not self — lone forge fails, group collusion succeeds" do
    friends_of_p = ["w1", "w2", "w3"]
    real = att(1, "p", 0.3)

    # p's three witnesses each independently hold the real attestation.
    witnesses =
      Map.new(friends_of_p, fn w -> {w, V2.new_node(w, ["p"]) |> V2.ingest(real)} end)

    # p tampers its OWN copy to a fake 99.
    p = V2.new_node("p", []) |> V2.ingest(att(1, "p", 0.3))
    p = V2.force_rank(p, "p", 99.0)

    nodes = Map.put(witnesses, "p", p)

    # Witnessed read ignores p's self-copy → unaffected by the forge.
    assert_in_delta V2.witnessed_rank(nodes, friends_of_p, "p"), 50.3, 1.0e-9

    # Only if the WHOLE group colludes (all witnesses ingest the fake) does it move.
    fake = att(2, "p", 40.0)
    colluded = Map.new(friends_of_p, fn w -> {w, V2.ingest(nodes[w], fake)} end)
    colluded = Map.put(colluded, "p", p)
    assert V2.witnessed_rank(colluded, friends_of_p, "p") > 80.0
  end
end
