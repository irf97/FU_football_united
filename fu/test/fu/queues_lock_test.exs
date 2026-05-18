defmodule Fu.QueuesLockTest do
  @moduledoc """
  Soft-join → hard-lock lifecycle. Joining = interested; locking = a
  commitment. The match is "good to go" the instant every quota slot is
  filled by LOCKED members (fast path, no Resolver needed). The lock
  deadline force-locks everyone still merely queued, then resolves.
  """
  use Fu.DataCase, async: true

  alias Fu.Queues
  alias Fu.Queues.QueueMembership

  defp locked?(qid, player_id) do
    m = Fu.Repo.get_by(QueueMembership, queue_id: qid, player_id: player_id)
    m && m.locked_at != nil
  end

  test "lock_in commits a queued member and is idempotent" do
    q = queue_fixture(format: "8v8")
    p = player_fixture(primary_position: "MID")
    {:ok, _} = Queues.join(q, p)

    assert {:ok, m1} = Queues.lock_in(q, p)
    assert m1.locked_at != nil
    assert {:ok, m2} = Queues.lock_in(q, p)
    assert m2.locked_at == m1.locked_at
    assert locked?(q.id, p.id)
  end

  test "lock_in by a non-member is rejected" do
    q = queue_fixture(format: "8v8")
    assert {:error, :not_member} = Queues.lock_in(q, player_fixture())
  end

  test "you can leave while only queued, but not once locked in" do
    # Scheduled beyond the 3h hard-lock window so only the membership lock
    # (not the queue-level window) is what blocks leaving.
    q = queue_fixture(format: "8v8", scheduled_in: 5 * 3600)
    p = player_fixture(primary_position: "MID")
    {:ok, _} = Queues.join(q, p)

    # Soft (un-locked): leaving is free, no penalty.
    assert :ok = Queues.leave(q, p)
    refute Fu.Accounts.suspended?(Fu.Accounts.get_player!(p.id))

    {:ok, _} = Queues.join(q, p)
    {:ok, _} = Queues.lock_in(q, p)

    # Locked: you CAN still bail, but it bans you.
    assert {:penalised, tier, until} = Queues.leave(q, p)
    assert tier in [:day, :week]
    assert %DateTime{} = until
    assert Fu.Accounts.suspended?(Fu.Accounts.get_player!(p.id))
  end

  test "bailing after lock-in: 1-day ban when >24h out, 1-week ban within 24h" do
    far = queue_fixture(format: "8v8", scheduled_in: 5 * 24 * 3600)
    soon = queue_fixture(format: "8v8", scheduled_in: 3 * 3600)

    p1 = player_fixture(primary_position: "MID")
    {:ok, _} = Queues.join(far, p1)
    {:ok, _} = Queues.lock_in(far, p1)
    assert {:penalised, :day, d1} = Queues.leave(far, p1)
    assert_in_delta DateTime.diff(d1, DateTime.utc_now()), 86_400, 120

    p2 = player_fixture(primary_position: "MID")
    {:ok, _} = Queues.join(soon, p2)
    {:ok, _} = Queues.lock_in(soon, p2)
    assert {:penalised, :week, d2} = Queues.leave(soon, p2)
    assert_in_delta DateTime.diff(d2, DateTime.utc_now()), 7 * 86_400, 120
  end

  test "FAST PATH: when every quota slot is filled by locked members, the queue confirms itself" do
    q = queue_fixture(format: "8v8", fill: :all)
    refute Queues.get_queue!(q.id).state == "confirmed"

    for m <- Queues.get_queue!(q.id).memberships, m.status == "queued" do
      {:ok, _} = Queues.lock_in(q, %{id: m.player_id})
    end

    assert Queues.get_queue!(q.id).state == "confirmed"
  end

  test "a partially-locked full queue does NOT confirm yet" do
    q = queue_fixture(format: "8v8", fill: :all)
    [first | _] = Enum.filter(Queues.get_queue!(q.id).memberships, &(&1.status == "queued"))
    {:ok, _} = Queues.lock_in(q, %{id: first.player_id})

    assert Queues.get_queue!(q.id).state == "open"
  end

  test "the lock deadline force-locks everyone still queued, then resolves" do
    q = queue_fixture(format: "8v8", fill: :all)
    {outcome, _} = Queues.resolve_partial_fill(Queues.get_queue!(q.id))

    assert outcome == :confirmed

    assert Enum.all?(
             Queues.get_queue!(q.id).memberships,
             &(&1.status != "queued" or &1.locked_at != nil)
           )
  end
end
