defmodule Fu.MatchesClockTest do
  @moduledoc "AUDIT #12 — the in-play match clock: kickoff, captain pause/resume."
  use Fu.DataCase, async: true

  alias Fu.Matches

  defp confirmed_queue do
    queue_fixture(format: "8v8", fill: :all, state: "confirmed")
  end

  describe "kickoff/1" do
    test "starts the clock and is idempotent" do
      q = confirmed_queue()
      assert {:ok, r1} = Matches.kickoff(q.id)
      assert r1.started_at != nil

      assert {:ok, r2} = Matches.kickoff(q.id)
      assert r2.started_at == r1.started_at
    end

    test "refuses a queue that is not confirmed" do
      q = queue_fixture(format: "8v8", fill: :all)
      assert {:error, :not_confirmed} = Matches.kickoff(q.id)
    end
  end

  describe "elapsed_seconds/2 with pause/resume" do
    test "the paused span is excluded from played time, before and after resume" do
      q = confirmed_queue()
      {:ok, _} = Matches.kickoff(q.id)

      now = DateTime.utc_now() |> DateTime.truncate(:second)
      started = DateTime.add(now, -200, :second)
      paused = DateTime.add(now, -60, :second)

      # Simulate: kicked off 200s ago, currently paused for the last 60s.
      {:ok, _} =
        Matches.result(q.id)
        |> Fu.Matches.MatchResult.changeset(%{started_at: started, paused_at: paused})
        |> Fu.Repo.update()

      paused_r = Matches.result(q.id)
      assert Matches.paused?(paused_r)
      # 200s wall - 60s in-progress pause = 140s played, frozen while paused.
      assert_in_delta Matches.elapsed_seconds(paused_r, now), 140, 1

      {:ok, _} = Matches.resume(q.id)
      running = Matches.result(q.id)
      refute Matches.paused?(running)
      # Resume banks the ~60s paused span; played time still excludes it.
      e = Matches.elapsed_seconds(running, now)
      assert_in_delta e, 140, 1
      assert e < 200 and e > 0
    end

    test "elapsed is zero before kickoff" do
      q = confirmed_queue()
      r = Matches.get_or_create_result(q.id)
      assert Matches.elapsed_seconds(r, DateTime.utc_now()) == 0
    end
  end
end
