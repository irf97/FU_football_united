defmodule Fu.Hobbies.SessionsTest do
  use Fu.DataCase, async: true

  alias Fu.Hobbies

  defp attrs(extra \\ %{}) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Map.merge(
      %{
        title: "Campus futsal",
        hobby: "futsal",
        mode: "committed",
        place: "Twente sports hall",
        starts_at: DateTime.add(now, 3600),
        ends_at: DateTime.add(now, 7200),
        capacity: 4,
        min_participants: 2
      },
      extra
    )
  end

  defp session(extra \\ %{}) do
    host = player_fixture()
    {:ok, session} = Hobbies.create_session(host, attrs(extra))
    {host, session}
  end

  defp ready_now(session) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    session |> Ecto.Changeset.change(starts_at: DateTime.add(now, -60)) |> Repo.update!()
  end

  test "the same session model supports sport, music and practice without football ranks" do
    for {hobby, mode} <- [
          {"futsal", "committed"},
          {"guitar", "open"},
          {"table tennis", "practice"}
        ] do
      host = player_fixture()

      {:ok, s} =
        Hobbies.create_session(
          host,
          attrs(%{
            hobby: hobby,
            mode: mode,
            host_id: -1,
            status: "completed",
            access_status: "confirmed"
          })
        )

      assert s.host_id == host.id
      assert s.status == "scheduled"
      assert s.access_status == "pending"
      assert s.hobby == hobby
      assert Enum.any?(Hobbies.list_sessions(%{hobby: hobby}), &(&1.id == s.id))
    end
  end

  test "creation validates time, capacity and minimum attendance" do
    host = player_fixture()

    for bad <- [
          %{capacity: 0},
          %{min_participants: 5},
          %{title: " "},
          %{mode: "ranked"},
          %{starts_at: DateTime.add(DateTime.utc_now(), -100)},
          %{ends_at: DateTime.utc_now()}
        ] do
      assert {:error, %Ecto.Changeset{}} = Hobbies.create_session(host, attrs(bad))
    end

    assert [] == Hobbies.list_sessions()
  end

  test "join and leave are idempotent; rejoin reuses the participant record" do
    {_host, s} = session()
    player = player_fixture()
    assert {:ok, first} = Hobbies.join(s.id, player)
    assert {:ok, duplicate} = Hobbies.join(s.id, player)
    assert duplicate.id == first.id
    assert {:ok, left} = Hobbies.leave(s.id, player)
    assert left.status == "left"
    assert {:ok, _} = Hobbies.leave(s.id, player)
    assert {:ok, rejoined} = Hobbies.join(s.id, player)
    assert rejoined.id == first.id
    assert Enum.map(Hobbies.history(s.id), & &1.action) == ["created", "joined", "left", "joined"]
  end

  test "full sessions reject extra participants and release seats after withdrawal" do
    {_host, s} = session(%{capacity: 1, min_participants: 1})
    a = player_fixture()
    b = player_fixture()
    assert {:ok, _} = Hobbies.join(s.id, a)
    assert {:error, :full} = Hobbies.join(s.id, b)
    assert {:ok, _} = Hobbies.leave(s.id, a)
    assert {:ok, _} = Hobbies.join(s.id, b)
  end

  test "commitment is explicit and withdrawing records the reason without a global penalty" do
    {_host, s} = session()
    player = player_fixture()
    assert {:error, :not_joined} = Hobbies.commit(s.id, player)
    {:ok, joined} = Hobbies.join(s.id, player)
    assert joined.status == "joined"
    assert {:ok, committed} = Hobbies.commit(s.id, player)
    assert committed.committed_at
    assert {:ok, _} = Hobbies.commit(s.id, player)
    assert {:error, :reason_required} = Hobbies.leave(s.id, player)
    assert {:ok, left} = Hobbies.leave(s.id, player, "Lecture overran")
    assert left.withdrawal_reason == "Lecture overran"
    assert Fu.Accounts.get_player(player.id).suspended_until == nil
    assert {:ok, fresh} = Hobbies.join(s.id, player)
    assert fresh.committed_at == nil
    assert fresh.withdrawal_reason == nil
  end

  test "open presence needs no commitment and allows free departure" do
    {_host, s} = session(%{hobby: "guitar", mode: "open"})
    player = player_fixture()
    {:ok, _} = Hobbies.join(s.id, player)
    assert {:error, :not_required} = Hobbies.commit(s.id, player)
    assert {:ok, left} = Hobbies.leave(s.id, player)
    assert left.status == "left"
  end

  test "only the host can confirm access, start, finish or cancel" do
    {_host, s} = session()
    outsider = player_fixture()

    assert {:error, :forbidden} =
             Hobbies.confirm_access(s.id, outsider, "Confirmed with operator")

    assert {:error, :forbidden} = Hobbies.start(s.id, outsider)
    assert {:error, :forbidden} = Hobbies.finish(s.id, outsider)
    assert {:error, :forbidden} = Hobbies.cancel(s.id, outsider, "Cancelled")
    assert Hobbies.get_session(s.id).access_status == "pending"
  end

  test "a committed session requires confirmed access and sufficient commitments before start" do
    {host, s} = session()
    s = ready_now(s)
    assert {:error, :access_unconfirmed} = Hobbies.start(s.id, host)
    assert {:error, :reason_required} = Hobbies.confirm_access(s.id, host, " ")
    assert {:ok, confirmed} = Hobbies.confirm_access(s.id, host, "Operator confirmed room access")
    assert confirmed.access_status == "host_confirmed"
    assert {:error, :not_ready} = Hobbies.start(s.id, host)

    for _ <- 1..2 do
      player = player_fixture()
      {:ok, _} = Hobbies.join(s.id, player)
      assert {:error, :not_ready} = Hobbies.start(s.id, host)
      {:ok, _} = Hobbies.commit(s.id, player)
    end

    assert {:ok, active} = Hobbies.start(s.id, host)
    assert active.status == "active"
  end

  test "start cannot occur before the stated time" do
    {host, s} = session(%{min_participants: 1})
    {:ok, _} = Hobbies.confirm_access(s.id, host, "Access checked")
    {:ok, _} = Hobbies.join(s.id, host)
    {:ok, _} = Hobbies.commit(s.id, host)
    assert {:error, :not_started} = Hobbies.start(s.id, host)
  end

  test "attendance is a participant action during the session; finish preserves the record" do
    {host, s} = session(%{mode: "practice", hobby: "table tennis", min_participants: 1})
    player = player_fixture()
    {:ok, _} = Hobbies.join(s.id, player)
    assert {:error, :not_active} = Hobbies.attend(s.id, player)
    {:ok, _} = Hobbies.confirm_access(s.id, host, "Public table available")
    ready_now(s)
    {:ok, _} = Hobbies.start(s.id, host)
    assert {:error, :not_joined} = Hobbies.attend(s.id, player_fixture())
    assert {:ok, member} = Hobbies.attend(s.id, player)
    assert member.attended_at
    assert {:ok, _} = Hobbies.attend(s.id, player)
    assert {:ok, finished} = Hobbies.finish(s.id, host)
    assert finished.status == "completed"
    assert {:error, :closed} = Hobbies.join(s.id, player_fixture())
    assert Hobbies.get_session(s.id).participants |> Enum.any?(&(&1.status == "attended"))
  end

  test "cancellation reaches every participant and prevents further actions" do
    {host, s} = session()
    a = player_fixture()
    b = player_fixture()
    {:ok, _} = Hobbies.join(s.id, a)
    {:ok, _} = Hobbies.join(s.id, b)
    {:ok, _} = Hobbies.commit(s.id, a)
    Hobbies.subscribe(s.id)
    assert {:error, :reason_required} = Hobbies.cancel(s.id, host, "")
    assert {:ok, cancelled} = Hobbies.cancel(s.id, host, "Venue unavailable")
    assert cancelled.status == "cancelled"
    assert cancelled.cancellation_reason == "Venue unavailable"
    assert_receive {:hobby_session_changed, id} when id == s.id
    assert Enum.all?(Hobbies.get_session(s.id).participants, &(&1.status == "cancelled"))
    assert {:error, :closed} = Hobbies.commit(s.id, a)
    assert {:error, :closed} = Hobbies.join(s.id, player_fixture())
    assert {:error, :closed} = Hobbies.start(s.id, host)
    assert Enum.any?(Hobbies.history(s.id), &(&1.action == "cancelled"))
  end

  test "invalid and nonexistent ids return domain errors instead of crashing" do
    player = player_fixture()

    for id <- ["invalid", "-1", "1.5", -1, 9_999_999_999] do
      assert Hobbies.get_session(id) == nil
      assert {:error, :not_found} = Hobbies.join(id, player)
    end
  end
end
