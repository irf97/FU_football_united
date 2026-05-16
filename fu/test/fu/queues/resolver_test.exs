defmodule Fu.Queues.ResolverTest do
  @moduledoc "P0 — T-3h partial-fill resolution (race-prone, runs unattended)."
  use Fu.DataCase, async: false

  alias Fu.Queues

  describe "resolve_partial_fill/1 (spec §2.4)" do
    test "confirms when every position quota is filled" do
      q = queue_fixture(format: "8v8", fill: :all)
      assert {:confirmed, updated} = Queues.resolve_partial_fill(q)
      assert updated.state == "confirmed"
    end

    test "cancels when the keeper slot is empty" do
      # 8v8 quotas: GK2 DEF6 MID6 FWD2. Fill outfield, no keeper.
      q = queue_fixture(format: "8v8")
      fill_positions(q, %{"DEF" => 6, "MID" => 6, "FWD" => 2, "GK" => 0})
      assert {:cancelled, updated} = Queues.resolve_partial_fill(Queues.get_queue!(q.id))
      assert updated.state == "cancelled"
    end

    test "cancels when more than 2 non-keeper slots are empty" do
      q = queue_fixture(format: "8v8")
      fill_positions(q, %{"GK" => 2, "DEF" => 6, "MID" => 3, "FWD" => 2})
      assert {:cancelled, _} = Queues.resolve_partial_fill(Queues.get_queue!(q.id))
    end

    test "extends once when keeper present and <2 non-keeper slots empty" do
      q = queue_fixture(format: "8v8")
      fill_positions(q, %{"GK" => 2, "DEF" => 6, "MID" => 5, "FWD" => 2})
      assert {:extended, updated} = Queues.resolve_partial_fill(Queues.get_queue!(q.id))
      assert updated.extended_once == true
      assert updated.state == "open"
    end

    test "does not extend a second time (cancels instead)" do
      q = queue_fixture(format: "8v8", state: "open")
      q |> Fu.Queues.Queue.changeset(%{extended_once: true}) |> Repo.update!()
      fill_positions(q, %{"GK" => 2, "DEF" => 6, "MID" => 5, "FWD" => 2})
      assert {:cancelled, _} = Queues.resolve_partial_fill(Queues.get_queue!(q.id))
    end

    test "broadcasts {:queue_changed, id} on confirm" do
      q = queue_fixture(format: "8v8", fill: :all)
      Phoenix.PubSub.subscribe(Fu.PubSub, Queues.topic(q.id))
      Queues.resolve_partial_fill(q)
      assert_receive {:queue_changed, qid} when qid == q.id, 1000
    end
  end

  describe "due_for_resolution/0 — idempotency guard" do
    test "excludes already-confirmed queues (worker can fire twice safely)" do
      q = queue_fixture(format: "8v8", fill: :all)
      {:confirmed, _} = Queues.resolve_partial_fill(q)
      ids = Queues.due_for_resolution() |> Enum.map(& &1.id)
      refute q.id in ids
    end

    test "includes an open queue inside the 3h lock window" do
      q = queue_fixture(format: "8v8", scheduled_in: 3600, fill: :all)
      ids = Queues.due_for_resolution() |> Enum.map(& &1.id)
      assert q.id in ids
    end

    test "excludes an open queue still outside the 3h window" do
      q = queue_fixture(format: "8v8", scheduled_in: 6 * 3600, fill: :all)
      ids = Queues.due_for_resolution() |> Enum.map(& &1.id)
      refute q.id in ids
    end
  end

  defp fill_positions(queue, counts) do
    for {pos, n} <- counts, n > 0, _ <- 1..n do
      member(queue, player_fixture(primary_position: pos), pos)
    end
  end
end
