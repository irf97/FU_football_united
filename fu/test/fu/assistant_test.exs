defmodule Fu.AssistantTest do
  use Fu.DataCase, async: true
  alias Fu.{Assistant, Hobbies, Repo}
  import Ecto.Query

  defp event(host) do
    at = DateTime.utc_now() |> DateTime.add(3600) |> DateTime.truncate(:second)

    {:ok, session} =
      Hobbies.create_session(host, %{
        title: "Assisted game",
        hobby: "table tennis",
        place: "Room",
        starts_at: at,
        ends_at: DateTime.add(at, 3600),
        capacity: 4,
        min_participants: 1
      })

    session
  end

  defp active(session) do
    Repo.update!(
      Ecto.Changeset.change(session,
        starts_at: DateTime.utc_now() |> DateTime.add(-10) |> DateTime.truncate(:second)
      )
    )
  end

  defp command(session, actor, board, action, attrs \\ %{}) do
    Assistant.command(
      session.id,
      actor,
      action,
      Map.merge(%{"revision" => board.revision, "request_id" => Ecto.UUID.generate()}, attrs)
    )
  end

  test "only host configures; a referee must be a current member" do
    host = player_fixture()
    guest = player_fixture()
    session = event(host)
    attrs = %{team_a: "Blue", team_b: "Gold", duration_seconds: 600, referee_id: guest.id}
    assert {:error, :forbidden} = Assistant.configure(session.id, guest, attrs)
    assert {:error, :invalid_referee} = Assistant.configure(session.id, host, attrs)
    {:ok, _} = Hobbies.join(session.id, guest)
    assert {:ok, board} = Assistant.configure(session.id, host, attrs)
    assert board.referee_id == guest.id
    assert board.score_a == 0 and board.score_b == 0
    assert board.status == "idle"
    assert {:error, :already_configured} = Assistant.configure(session.id, host, attrs)
  end

  test "authorized commands are versioned, idempotent and recoverable; corrections require reasons" do
    host = player_fixture()
    guest = player_fixture()
    stranger = player_fixture()
    session = event(host)
    {:ok, _} = Hobbies.join(session.id, guest)

    {:ok, board} =
      Assistant.configure(session.id, host, %{
        team_a: "Blue",
        team_b: "Gold",
        duration_seconds: 600,
        referee_id: guest.id
      })

    assert {:error, :not_active} = command(session, guest, board, "start")
    session = active(session)
    {:ok, _} = Hobbies.confirm_access(session.id, host, "Room confirmed")
    {:ok, _} = Hobbies.start(session.id, host)
    assert {:error, :forbidden} = command(session, stranger, board, "start")
    assert {:ok, running} = command(session, guest, board, "start")
    assert running.deadline_at != nil

    attrs = %{
      "revision" => running.revision,
      "request_id" => "point-1",
      "side" => "a",
      "delta" => 1
    }

    assert {:ok, scored} = Assistant.command(session.id, guest, "score", attrs)
    assert scored.score_a == 1 and scored.score_b == 0
    assert {:ok, retry} = Assistant.command(session.id, guest, "score", attrs)
    assert retry.revision == scored.revision

    assert {:error, :idempotency_conflict} =
             Assistant.command(session.id, guest, "score", Map.put(attrs, "side", "b"))

    assert {:error, :stale_revision} = command(session, guest, running, "pause")

    assert {:error, :reason_required} =
             command(session, guest, scored, "correct", %{"score_a" => 0, "score_b" => 0})

    assert {:ok, corrected} =
             command(session, guest, scored, "correct", %{
               "score_a" => 0,
               "score_b" => 0,
               "reason" => "Point was recorded for the wrong rally"
             })

    assert {:ok, paused} = command(session, guest, corrected, "pause")
    assert paused.deadline_at == nil
    assert {:ok, resumed} = command(session, guest, paused, "start")

    assert {:ok, final} =
             command(session, guest, resumed, "finalize", %{
               "reason" => "Both sides reviewed the recorded score"
             })

    assert final.status == "finalized"

    assert {:error, :finished} =
             command(session, guest, final, "score", %{"side" => "b", "delta" => 1})

    assert {:ok, late} =
             command(session, host, final, "correct", %{
               "score_a" => 2,
               "score_b" => 1,
               "reason" => "Both sides confirmed the omitted rally"
             })

    assert late.status == "finalized" and late.score_a == 2
    history = Assistant.history(session.id, guest)
    assert Enum.count(history, &(&1.action == "score")) == 1

    assert Enum.any?(
             history,
             &(&1.action == "correct" &&
                 &1.payload["reason"] == "Point was recorded for the wrong rally")
           )

    assert Assistant.history(session.id, stranger) == []

    assert Repo.aggregate(
             from(e in Fu.Assistant.Event, where: e.session_id == ^session.id),
             :count
           ) == length(history)
  end

  test "host can replace a referee and departed participants lose authority immediately" do
    host = player_fixture()
    guest = player_fixture()
    stranger = player_fixture()
    session = event(host)
    {:ok, _} = Hobbies.join(session.id, guest)

    {:ok, board} =
      Assistant.configure(session.id, host, %{
        team_a: "A",
        team_b: "B",
        duration_seconds: 60,
        referee_id: guest.id
      })

    assert {:error, :forbidden} =
             command(session, guest, board, "assign_referee", %{"referee_id" => host.id})

    assert {:error, :invalid_referee} =
             command(session, host, board, "assign_referee", %{"referee_id" => stranger.id})

    {:ok, _} = Hobbies.leave(session.id, guest)
    assert {:error, :forbidden} = command(session, guest, board, "start")

    assert {:ok, reassigned} =
             command(session, host, board, "assign_referee", %{"referee_id" => host.id})

    assert reassigned.referee_id == host.id
  end
end
