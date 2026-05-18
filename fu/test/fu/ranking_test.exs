defmodule Fu.RankingTest do
  @moduledoc "P0 — rank calculation: the reproducibility/trust contract (spec §2.9)."
  use Fu.DataCase, async: false
  use ExUnitProperties

  alias Fu.{Ranking, Matches, Balance}

  defp played_rated_queue do
    q = queue_fixture(format: "8v8", fill: :all)
    {:ok, _} = Balance.assign_teams(q.id)
    Matches.record_score(q.id, 2, 1)
    Matches.complete_match(q.id)
    Fu.Queues.get_queue!(q.id)
  end

  describe "finalize_match/1" do
    test "writes one rank event per queued participant" do
      q = played_rated_queue()
      {:ok, events} = Ranking.finalize_match(q.id)
      participants = Enum.count(q.memberships, &(&1.status == "queued"))
      assert length(events) == participants
      assert participants == 16
    end

    test "delta equals the sum of its breakdown components (inspectable, spec §2.9)" do
      q = played_rated_queue()
      {:ok, events} = Ranking.finalize_match(q.id)

      for e <- events do
        sum = e.breakdown |> Map.values() |> Enum.sum()
        assert_in_delta e.delta, sum, 1.0e-9
        assert_in_delta e.rank_after, Ranking.clamp(e.rank_before + e.delta), 1.0e-9
      end
    end

    test "is idempotent — second call returns the same events, ranks unchanged" do
      q = played_rated_queue()
      {:ok, first} = Ranking.finalize_match(q.id)
      ranks_after = for e <- first, into: %{}, do: {e.player_id, e.rank_after}

      {:ok, second} = Ranking.finalize_match(q.id)
      assert length(second) == length(first)

      for e <- second do
        assert Ranking.current_rank(e.player_id) == ranks_after[e.player_id]
      end
    end

    test "unrated format earns zero rated points (5v5 — not in rated set)" do
      q = queue_fixture(format: "5v5", fill: :all)
      {:ok, _} = Balance.assign_teams(q.id)
      Matches.record_score(q.id, 3, 0)
      Matches.complete_match(q.id)
      {:ok, events} = Ranking.finalize_match(q.id)

      for e <- events do
        assert e.breakdown["outcome"] == 0.0
        assert e.breakdown["goals"] == 0.0
        assert e.delta == 0.0
      end
    end

    test "7v7 IS rated — earns non-zero outcome points (user decision 2026-05-17)" do
      q = queue_fixture(format: "7v7", fill: :all)
      {:ok, _} = Balance.assign_teams(q.id)
      Matches.record_score(q.id, 3, 0)
      Matches.complete_match(q.id)
      {:ok, events} = Ranking.finalize_match(q.id)

      assert Enum.any?(events, &(&1.breakdown["outcome"] != 0.0)),
             "a rated 7v7 must move ranks via the outcome component"
    end
  end

  describe "clamp/1 — rank bounds are well-defined and stable" do
    property "always idempotent and within the fixed range" do
      lo = Ranking.clamp(-1.0e9)
      hi = Ranking.clamp(1.0e9)

      check all x <- one_of([float(), integer()]) do
        c = Ranking.clamp(x)
        assert c >= lo and c <= hi
        assert Ranking.clamp(c) == c
      end
    end

    property "monotonic — clamping never inverts order" do
      check all a <- float(), b <- float() do
        if a <= b, do: assert(Ranking.clamp(a) <= Ranking.clamp(b))
      end
    end
  end
end
