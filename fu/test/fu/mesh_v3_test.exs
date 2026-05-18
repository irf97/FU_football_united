defmodule Fu.MeshV3Test do
  @moduledoc """
  v3 adds the routing the bound starved in v2:

    * subject-directed relay — a carrier pushes S's record toward S's
      witnesses even though the carrier doesn't 'care' about S;
    * proximity-over-time → acquaintance: repeated co-presence promotes a
      peer to a long-retention tier; absence decays it back;
    * closeness filter — you do NOT blind-flood a stranger's data to an
      unrelated peer; you relay toward witnesses or share about people
      you're actually close to.

  Bounded-store + idempotent invariants from v2 must still hold.
  """
  use ExUnit.Case, async: true

  alias Fu.Mesh.V3

  defp att(m, p, d, w \\ []), do: V3.attest(m, p, d, w)

  test "subject-directed relay: a carrier delivers S's fact to S's witness, though it doesn't care about S" do
    # 'a' played with S, carries the fact. 'a' is NOT friends with S.
    # 'w' IS S's friend (a witness) but wasn't at the match.
    a = V3.new_node("a", []) |> V3.ingest(att(1, "S", 1.5, ["w"]))
    w = V3.new_node("w", ["S"])

    refute V3.knows?(w, "S")
    {_a, w1, bytes} = V3.reconcile(a, w)

    assert bytes > 0
    assert V3.seen_match?(w1, "S", 1), "the witness must receive S's attestation via relay"
  end

  test "closeness filter: a carrier does NOT flood an unrelated peer with a stranger's data" do
    # 'a' carries S's fact. 'x' is unrelated to S (not a witness, doesn't
    # know S) and 'a' is not close to S either → no transfer.
    a = V3.new_node("a", []) |> V3.ingest(att(1, "S", 1.5, ["w"]))
    x = V3.new_node("x", [])

    {_a, x1, _b} = V3.reconcile(a, x)
    refute V3.knows?(x1, "S"), "stranger data must not blind-flood unrelated peers"
  end

  test "proximity over time promotes an acquaintance; absence decays it back" do
    a = V3.new_node("a", [])
    th = V3.acq_threshold()

    a = Enum.reduce(1..th, a, fn _, acc -> V3.met(acc, "b") end)
    assert V3.acquaintance?(a, "b")

    # Stop meeting 'b' → decays out after enough idle ticks.
    a = Enum.reduce(1..(th + V3.acq_decay() + 2), a, fn _, acc -> V3.tick(acc) end)
    refute V3.acquaintance?(a, "b")
  end

  test "retention tiers: friend kept forever, acquaintance long, stranger evicted fast" do
    n = V3.new_node("a", ["fr"])

    n =
      n
      |> V3.ingest(att(1, "fr", 1.0, []))
      |> V3.ingest(att(1, "acq", 1.0, []))
      |> V3.ingest(att(1, "str", 1.0, []))

    n = Enum.reduce(1..V3.acq_threshold(), n, fn _, acc -> V3.met(acc, "acq") end)

    n = Enum.reduce(1..(V3.stranger_ttl() + 1), n, fn _, acc -> V3.tick(acc) end)

    assert V3.knows?(n, "fr"), "friends are permanent"
    assert V3.knows?(n, "acq"), "acquaintances survive the stranger TTL"
    refute V3.knows?(n, "str"), "strangers are evicted fast"
  end

  test "still bounded + idempotent: re-ingest never double counts, pending capped at K" do
    k = V3.window()
    n = V3.new_node("a", ["p"])
    e = att(1, "p", 1.5, [])

    n = n |> V3.ingest(e) |> V3.ingest(e)
    assert_in_delta V3.rank(n, "p"), 51.5, 1.0e-9

    n = Enum.reduce(1..(k * 4), n, fn i, acc -> acc |> V3.ingest(att(i, "p", 1.0, [])) |> V3.compact() end)
    assert V3.pending_count(n, "p") <= k
  end

  describe "friendless bootstrap — provisional witnesses" do
    # A node that has met `subject` enough to be a sustained acquaintance
    # AND holds its record.
    defp acq_holder(id, subject, att) do
      n = V3.new_node(id, [])
      n = Enum.reduce(1..V3.acq_threshold(), n, fn _, acc -> V3.met(acc, subject) end)
      V3.ingest(n, att)
    end

    test "an orphan is recoverable once sustained acquaintances hold its record" do
      a = att(1, "orphan", 1.5, [])
      w1 = acq_holder("w1", "orphan", a)
      w2 = acq_holder("w2", "orphan", a)
      # self may hold (and even tamper) its own copy — must not count.
      self = V3.new_node("orphan", []) |> V3.ingest(a)
      nodes = %{"w1" => w1, "w2" => w2, "orphan" => self}

      pw = V3.provisional_witnesses(nodes, "orphan")
      assert Enum.sort(pw) == ["w1", "w2"]
      refute "orphan" in pw

      # No friends → falls back to provisional witnesses, which agree on 51.5.
      assert_in_delta V3.recoverable_rank(nodes, [], "orphan"), 51.5, 1.0e-9
    end

    test "self-tamper still cannot move the recoverable rank" do
      a = att(1, "orphan", 0.3, [])
      w1 = acq_holder("w1", "orphan", a)
      w2 = acq_holder("w2", "orphan", a)
      tampered = V3.new_node("orphan", []) |> V3.ingest(att(1, "orphan", 99.0, []))
      nodes = %{"w1" => w1, "w2" => w2, "orphan" => tampered}

      assert_in_delta V3.recoverable_rank(nodes, [], "orphan"), 50.3, 1.0e-9
    end

    test "with no acquaintances there is nothing to recover (honest gap)" do
      a = att(1, "orphan", 1.5, [])
      lone = V3.new_node("orphan", []) |> V3.ingest(a)
      nodes = %{"orphan" => lone}

      assert V3.provisional_witnesses(nodes, "orphan") == []
      assert V3.recoverable_rank(nodes, [], "orphan") == 50.0
    end

    test "friend-witnesses still take precedence when present" do
      a = att(1, "p", 1.5, [])
      f = V3.new_node("f", ["p"]) |> V3.ingest(a)
      acq = acq_holder("acq", "p", att(1, "p", -0.8, []))
      nodes = %{"f" => f, "acq" => acq, "p" => V3.new_node("p", [])}

      # Friend "f" holds it → friend path wins, ignores the acquaintance's view.
      assert_in_delta V3.recoverable_rank(nodes, ["f"], "p"), 51.5, 1.0e-9
    end
  end
end
