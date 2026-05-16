defmodule Fu.MatchesSubmitTest do
  @moduledoc """
  AUDIT integration break #1 — the missing in-app trigger that records a
  final score, completes the match, and finalizes ranks as one operation.
  """
  use Fu.DataCase, async: true

  alias Fu.{Matches, Ranking, Queues, Balance, Voting}

  defp confirmed_8v8 do
    q = queue_fixture(format: "8v8", fill: :all, state: "confirmed")
    {:ok, _} = Balance.assign_teams(q.id)
    q
  end

  test "submit_result records score, completes the match, and finalizes ranks" do
    q = confirmed_8v8()

    assert {:ok, result} = Matches.submit_result(q.id, 3, 2)
    assert result.score_a == 3
    assert result.score_b == 2
    assert result.completed_at != nil
    assert Voting.voting_open?(q.id)
    assert Queues.get_queue!(q.id).state == "completed"

    {:ok, events} = Ranking.finalize_match(q.id)
    assert length(events) == 16
  end

  test "submit_result is idempotent — a second call does not move ranks again" do
    q = confirmed_8v8()
    {:ok, _} = Matches.submit_result(q.id, 1, 0)
    {:ok, evs1} = Ranking.finalize_match(q.id)
    ranks = Map.new(evs1, &{&1.player_id, Ranking.current_rank(&1.player_id)})

    assert {:ok, _} = Matches.submit_result(q.id, 9, 9)
    {:ok, evs2} = Ranking.finalize_match(q.id)
    assert length(evs2) == length(evs1)

    for {pid, r} <- ranks do
      assert Ranking.current_rank(pid) == r
    end
  end

  test "submit_result refuses a queue that is not confirmed" do
    q = queue_fixture(format: "8v8", fill: :all)
    assert {:error, :not_confirmed} = Matches.submit_result(q.id, 1, 1)
    refute Voting.voting_open?(q.id)
  end
end
