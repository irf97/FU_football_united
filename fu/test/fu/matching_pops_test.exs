defmodule Fu.MatchingPopsTest do
  @moduledoc "Auto-queue search: pops/1 = joinable, position-fitting queues, best-first."
  use Fu.DataCase, async: true

  alias Fu.{Matching, Queues}

  test "surfaces an open queue that has a slot for the player's position" do
    player = player_fixture(primary_position: "MID")
    q = queue_fixture(format: "8v8")

    ids = Matching.pops(player) |> Enum.map(& &1.queue.id)
    assert q.id in ids
  end

  test "excludes a queue with no slot for the player (and fill_mode off)" do
    player = player_fixture(primary_position: "MID", secondary_position: "FWD")
    full = queue_fixture(format: "8v8", fill: :all)

    refute full.id in (Matching.pops(player) |> Enum.map(& &1.queue.id))
  end

  test "excludes queues the player has already joined" do
    player = player_fixture(primary_position: "MID")
    q = queue_fixture(format: "8v8")
    {:ok, _} = Queues.join(q, player)

    refute q.id in (Matching.pops(player) |> Enum.map(& &1.queue.id))
  end

  test "a queue that needs the player's primary position ranks first" do
    player = player_fixture(primary_position: "GK", secondary_position: "MID", rank: 50.0)

    # q_no_gk: GK already full → player can only take a secondary (MID) slot.
    q_no_gk = queue_fixture(format: "8v8")
    for _ <- 1..2, do: member(q_no_gk, player_fixture(primary_position: "GK"), "GK")

    # q_needs_gk: empty → needs the player's *primary* (the strongest signal).
    q_needs_gk = queue_fixture(format: "8v8")

    [first | _] = Matching.pops(player)
    assert first.queue.id == q_needs_gk.id
  end
end
