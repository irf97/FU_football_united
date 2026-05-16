defmodule Fu.QueuesJoinTest do
  @moduledoc """
  Regression — `Queues.join/3` must never return a raw changeset (it
  crashed `BrowseLive.join_error/1` via `String.Chars` on Ecto.Changeset
  when a prior "left" row kept the (queue_id, player_id) unique key).
  """
  use Fu.DataCase, async: true

  alias Fu.Queues

  # Open, NOT in the 3h lock window, so leave/2 is allowed.
  defp open_queue, do: queue_fixture(format: "8v8", scheduled_in: 6 * 3600)

  test "re-joining a queue you left reactivates the membership (no crash)" do
    q = open_queue()
    p = player_fixture(primary_position: "MID")

    assert {:ok, _} = Queues.join(q, p)
    assert :ok = Queues.leave(Queues.get_queue!(q.id), p)
    # Previously: unique-constraint violation → {:error, %Ecto.Changeset{}}.
    assert {:ok, m} = Queues.join(Queues.get_queue!(q.id), p)
    assert m.status == "queued"

    # Exactly one row for (queue, player) — reactivated, not duplicated.
    count =
      Repo.aggregate(
        from(x in Fu.Queues.QueueMembership,
          where: x.queue_id == ^q.id and x.player_id == ^p.id
        ),
        :count,
        :id
      )

    assert count == 1
  end

  test "joining while already queued returns an atom, never a changeset" do
    q = open_queue()
    p = player_fixture(primary_position: "MID")

    assert {:ok, _} = Queues.join(q, p)
    assert {:error, reason} = Queues.join(Queues.get_queue!(q.id), p)
    assert is_atom(reason)
    assert reason == :already_joined
  end

  test "every join error reason is an atom (join_error/1 contract)" do
    q = open_queue()
    suspended = player_fixture()

    {:ok, p} =
      suspended
      |> Ecto.Changeset.change(
        suspended_until: DateTime.utc_now() |> DateTime.add(3600) |> DateTime.truncate(:second)
      )
      |> Repo.update()

    assert {:error, r} = Queues.join(q, p)
    assert is_atom(r)
  end
end
