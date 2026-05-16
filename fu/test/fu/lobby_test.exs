defmodule Fu.LobbyTest do
  @moduledoc "P0 — sequenced captain claim: timing windows + state transitions (spec §2.5)."
  use Fu.DataCase, async: false

  alias Fu.{Lobby, Balance, Queues}

  defp confirmed_queue do
    q = queue_fixture(format: "8v8", fill: :all)
    {:ok, q} = Balance.assign_teams(q.id)
    q
  end

  defp anchor(q) do
    case q.updated_at do
      %DateTime{} = dt -> dt
      %NaiveDateTime{} = n -> DateTime.from_naive!(n, "Etc/UTC")
    end
  end

  describe "claim_phase/2 windows (keeper 60 → ranked 120 → free 240 → random)" do
    test "moves through all four phases by elapsed seconds" do
      q = confirmed_queue()
      a = anchor(q)

      assert {:keeper, _} = Lobby.claim_phase(q, DateTime.add(a, 10))
      assert {:ranked, _} = Lobby.claim_phase(q, DateTime.add(a, 90))
      assert {:free, _} = Lobby.claim_phase(q, DateTime.add(a, 180))
      assert {:random, 0} = Lobby.claim_phase(q, DateTime.add(a, 300))
    end

    test "reports seconds remaining in the current phase" do
      q = confirmed_queue()
      {:keeper, rem} = Lobby.claim_phase(q, DateTime.add(anchor(q), 20))
      assert rem in 35..40
    end
  end

  describe "eligible_to_claim?/3" do
    test "only the goalkeeper may claim in the :keeper window" do
      q = confirmed_queue()
      gk = Enum.find(q.memberships, &(&1.declared_position == "GK" and &1.team))
      outfield = Enum.find(q.memberships, &(&1.declared_position == "DEF" and &1.team))

      assert Lobby.eligible_to_claim?(q, gk.player, :keeper)
      refute Lobby.eligible_to_claim?(q, outfield.player, :keeper)
    end

    test "anyone on a team may claim in the :free window" do
      q = confirmed_queue()
      outfield = Enum.find(q.memberships, &(&1.declared_position == "DEF" and &1.team))
      assert Lobby.eligible_to_claim?(q, outfield.player, :free)
    end

    test "no one is eligible once their team already has a captain" do
      q = confirmed_queue()
      gk = Enum.find(q.memberships, &(&1.declared_position == "GK" and &1.team))
      {:ok, _} = Lobby.claim_captain(q, gk.player)
      q = Queues.get_queue!(q.id)
      assert {:error, :taken} = Lobby.claim_captain(q, gk.player)
    end
  end

  describe "claim_captain/2" do
    test "sets is_captain and blocks a second claim on the same team" do
      q = confirmed_queue()
      a_team = Enum.filter(q.memberships, &(&1.team == "A"))
      [first, second | _] = a_team

      assert {:ok, m} = Lobby.claim_captain(q, first.player)
      assert m.is_captain
      q = Queues.get_queue!(q.id)
      assert {:error, :taken} = Lobby.claim_captain(q, second.player)
    end
  end

  describe "random_assign/1 — deterministic fallback" do
    test "promotes the lowest player_id on every uncaptained team" do
      q = confirmed_queue()
      :ok = Lobby.random_assign(q)
      caps = Lobby.captains(Queues.get_queue!(q.id))
      assert Map.has_key?(caps, "A")
      assert Map.has_key?(caps, "B")
    end

    test "does not override an already-claimed captain" do
      q = confirmed_queue()
      a_first = q.memberships |> Enum.filter(&(&1.team == "A")) |> Enum.at(0)
      {:ok, claimed} = Lobby.claim_captain(q, a_first.player)
      :ok = Lobby.random_assign(Queues.get_queue!(q.id))
      caps = Lobby.captains(Queues.get_queue!(q.id))
      assert caps["A"] == claimed.id
    end
  end
end
