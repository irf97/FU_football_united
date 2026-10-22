defmodule FuWeb.AssistantLiveTest do
  use FuWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

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
