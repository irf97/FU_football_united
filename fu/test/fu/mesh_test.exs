defmodule Fu.MeshTest do
  @moduledoc """
  Invariants of the P2P proximity-gossip model. The scale harness's numbers
  are only trustworthy if these hold: no loss/dup, idempotent merge,
  eventual consistency under full connectivity, log-derived rank == oracle,
  and partition→heal.
  """
  use ExUnit.Case, async: true

  alias Fu.Mesh

  defp match(id, deltas), do: Mesh.match_event(id, deltas)

  test "append is idempotent — the same event never duplicates or grows the log" do
    n = Mesh.new_node("a")
    e = match("m1", %{"p1" => 1.5})

    n1 = n |> Mesh.append(e) |> Mesh.append(e) |> Mesh.append(e)
    assert Mesh.log_count(n1) == 1
  end

  test "reconcile transfers only what's missing, converges both ways, then is a no-op" do
    a = Mesh.new_node("a") |> Mesh.append(match("m1", %{"p1" => 1.5}))
    b = Mesh.new_node("b") |> Mesh.append(match("m2", %{"p1" => -0.8}))

    {a1, b1, bytes} = Mesh.reconcile(a, b)

    assert Mesh.log_count(a1) == 2
    assert Mesh.log_count(b1) == 2
    assert Mesh.log_ids(a1) == Mesh.log_ids(b1)
    assert bytes > 0

    # Anti-entropy is convergent: a second pass moves nothing.
    {_a2, _b2, bytes2} = Mesh.reconcile(a1, b1)
    assert bytes2 == 0
  end

  test "rank is a pure function of the local log: 50 + summed deltas, clamped [30,100]" do
    n =
      Mesh.new_node("a")
      |> Mesh.append(match("m1", %{"p1" => 1.5, "p2" => -0.8}))
      |> Mesh.append(match("m2", %{"p1" => -0.8}))

    assert_in_delta Mesh.rank(n, "p1"), 50.7, 1.0e-9
    assert_in_delta Mesh.rank(n, "p2"), 49.2, 1.0e-9
    assert Mesh.rank(n, "unknown") == 50.0
    # Clamp holds at the extremes.
    big = Mesh.new_node("z") |> Mesh.append(match("m3", %{"p1" => 999.0}))
    assert Mesh.rank(big, "p1") == 100.0
  end

  test "a fully-connected swarm converges to identical logs" do
    nodes =
      for i <- 1..6 do
        Mesh.new_node("n#{i}") |> Mesh.append(match("m#{i}", %{"p1" => 0.1 * i}))
      end

    converged = gossip(nodes, 4)
    ids = converged |> Enum.map(&Mesh.log_ids/1) |> Enum.uniq()

    assert length(ids) == 1, "all nodes must hold the same log"
    assert MapSet.size(hd(ids)) == 6
  end

  test "partition: clusters diverge from the oracle, then heal when one peer bridges them" do
    # Player P plays once in each cluster; the true rank needs both events.
    e1 = match("east", %{"P" => 1.5})
    e2 = match("west", %{"P" => 1.5})
    oracle = Mesh.new_node("oracle") |> Mesh.append(e1) |> Mesh.append(e2)

    a = Mesh.new_node("a") |> Mesh.append(e1)
    b = Mesh.new_node("b") |> Mesh.append(e1)
    c = Mesh.new_node("c") |> Mesh.append(e2)
    d = Mesh.new_node("d") |> Mesh.append(e2)

    # Partitioned: east {a,b} never meets west {c,d}.
    {a, b, _} = Mesh.reconcile(a, b)
    {c, d, _} = Mesh.reconcile(c, d)
    refute Mesh.rank(a, "P") == Mesh.rank(oracle, "P")

    # b bumps into c (one bridging encounter), then each cluster gossips internally.
    {b, c, _} = Mesh.reconcile(b, c)
    {a, b, _} = Mesh.reconcile(a, b)
    {c, d, _} = Mesh.reconcile(c, d)

    for n <- [a, b, c, d] do
      assert Mesh.rank(n, "P") == Mesh.rank(oracle, "P")
    end
  end

  # All-pairs gossip for `rounds` rounds (test helper, not the model).
  defp gossip(nodes, rounds) do
    Enum.reduce(1..rounds, nodes, fn _r, ns ->
      last = length(ns) - 1
      pairs = for a <- 0..last, b <- (a + 1)..last//1, do: {a, b}

      Enum.reduce(pairs, ns, fn {i, j}, acc ->
        {ni, nj, _} = Mesh.reconcile(Enum.at(acc, i), Enum.at(acc, j))
        acc |> List.replace_at(i, ni) |> List.replace_at(j, nj)
      end)
    end)
  end
end
