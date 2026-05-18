defmodule Fu.TacticsTest do
  @moduledoc """
  Team tactics: only the captain of THAT team in THAT queue may edit; the
  rest of the squad reads. Captain-guard is the load-bearing invariant.
  """
  use Fu.DataCase, async: true

  alias Fu.{Tactics, Balance, Lobby, Queues}

  setup do
    q = queue_fixture(format: "8v8", fill: :all, state: "confirmed")
    {:ok, q} = Balance.assign_teams(q.id)
    cap_a = Enum.find(q.memberships, &(&1.team == "A"))
    {:ok, _} = Lobby.claim_captain(q, cap_a.player)
    q = Queues.get_queue!(q.id)

    a_member = Enum.find(q.memberships, &(&1.team == "A" and not &1.is_captain))
    b_member = Enum.find(q.memberships, &(&1.team == "B"))

    %{q: q, captain_a: cap_a.player, member_a: a_member.player, member_b: b_member.player}
  end

  test "get/2 returns sensible defaults when nothing is set", %{q: q} do
    t = Tactics.get(q.id, "A")
    assert t.formation in Tactics.formations()
    assert t.style in Tactics.styles()
  end

  test "the team captain can set tactics, and they persist", %{q: q, captain_a: cap} do
    assert {:ok, t} =
             Tactics.set(q.id, "A", %{"formation" => "3-5-2", "style" => "Counter", "notes" => "Sit deep, break fast."}, cap)

    assert t.formation == "3-5-2"
    reloaded = Tactics.get(q.id, "A")
    assert reloaded.style == "Counter"
    assert reloaded.notes == "Sit deep, break fast."
  end

  test "a non-captain team member cannot edit", %{q: q, member_a: m} do
    assert {:error, :not_captain} =
             Tactics.set(q.id, "A", %{"formation" => "4-4-2", "style" => "Direct"}, m)
  end

  test "a captain cannot edit the other team's tactics", %{q: q, captain_a: cap} do
    assert {:error, :not_captain} =
             Tactics.set(q.id, "B", %{"formation" => "4-4-2", "style" => "Direct"}, cap)
  end

  test "invalid formation/style is rejected", %{q: q, captain_a: cap} do
    assert {:error, cs} =
             Tactics.set(q.id, "A", %{"formation" => "9-9-9", "style" => "Tiki"}, cap)

    refute cs.valid?
  end

  test "setting again updates the same row (no duplicate)", %{q: q, captain_a: cap} do
    {:ok, _} = Tactics.set(q.id, "A", %{"formation" => "4-3-3", "style" => "Balanced"}, cap)
    {:ok, _} = Tactics.set(q.id, "A", %{"formation" => "5-3-2", "style" => "Defensive"}, cap)

    assert Tactics.get(q.id, "A").formation == "5-3-2"
    assert Tactics.count(q.id, "A") == 1
  end
end
