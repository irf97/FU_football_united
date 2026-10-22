defmodule FuWeb.AssistantLiveTest do
  use FuWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  test "unrelated structured timer fields cannot poison the rendered audit history", %{conn: conn} do
    host = player_fixture()
    at = DateTime.utc_now() |> DateTime.add(3600) |> DateTime.truncate(:second)

    {:ok, session} =
      Fu.Hobbies.create_session(host, %{
        title: "Bounded history",
        hobby: "game",
        place: "Room",
        starts_at: at,
        ends_at: DateTime.add(at, 3600),
        capacity: 3,
        min_participants: 1
      })

    {:ok, _} = Fu.Hobbies.join(session.id, host)
    {:ok, _} = Fu.Hobbies.confirm_access(session.id, host, "Room confirmed")
    Fu.Repo.update!(Ecto.Changeset.change(session, starts_at: DateTime.add(at, -3610)))
    {:ok, _} = Fu.Hobbies.start(session.id, host)

    {:ok, board} =
      Fu.Assistant.configure(session.id, host, %{team_a: "A", team_b: "B", duration_seconds: 60})

    {:ok, _} =
      Fu.Assistant.command(session.id, host, "start", %{
        "revision" => board.revision,
        "request_id" => "bounded-history",
        "reason" => %{"nested" => ["unsafe"]}
      })

    {:ok, view, _} = live(log_in_player(conn, host), "/hobbies/#{session.id}/assistant")
    assert has_element?(view, "#scoreboard")
    assert has_element?(view, "#assistant-history")
    assert render(view) =~ "Recorded score"
  end

  test "organizer requires membership and shows readiness without configuring a scorekeeper", %{
    conn: conn
  } do
    host = player_fixture()
    at = DateTime.utc_now() |> DateTime.add(3600) |> DateTime.truncate(:second)

    {:ok, session} =
      Fu.Hobbies.create_session(host, %{
        title: "Guitar practice",
        hobby: "guitar",
        place: "Room",
        starts_at: at,
        ends_at: DateTime.add(at, 3600),
        capacity: 3,
        min_participants: 1
      })

    {:ok, view, _} = live(log_in_player(conn, host), "/hobbies/#{session.id}/assistant")
    assert has_element?(view, "#organizer-checks")
    assert has_element?(view, "#configure-scorekeeper")
    refute has_element?(view, "#scoreboard")

    {:ok, stranger, _} =
      live(log_in_player(build_conn(), player_fixture()), "/hobbies/#{session.id}/assistant")

    assert has_element?(stranger, "#assistant-unavailable")
    refute has_element?(stranger, "#organizer-checks")

    assert {:error, {:redirect, %{to: "/login"}}} =
             live(build_conn(), "/hobbies/#{session.id}/assistant")
  end
end
