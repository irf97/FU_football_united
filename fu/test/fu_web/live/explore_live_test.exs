defmodule FuWeb.ExploreLiveTest do
  use FuWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  test "explore is authenticated", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/login"}}} = live(conn, "/explore")
  end

  test "explore filters persisted events and preserves URL state", %{conn: conn} do
    player = player_fixture()
    at = DateTime.utc_now() |> DateTime.add(3600) |> DateTime.truncate(:second)

    {:ok, session} =
      Fu.Hobbies.create_session(player, %{
        title: "Build a guitar pedal",
        hobby: "music electronics",
        category: "making",
        kind: "class",
        mode: "practice",
        place: "Campus workshop",
        starts_at: at,
        ends_at: DateTime.add(at, 3600),
        capacity: 8,
        min_participants: 1
      })

    {:ok, view, _} = live(log_in_player(conn, player), "/explore?category=making")
    assert has_element?(view, "#explore-event-#{session.id}")
    assert has_element?(view, "#explore-hobbies")
    refute has_element?(view, "#football-rank")
    view |> form("#explore-filter", filter: %{q: "missing"}) |> render_change()
    assert_patch(view)
    assert has_element?(view, "#explore-empty")
    refute has_element?(view, "#explore-event-#{session.id}")

    {:ok, reloaded, _} =
      live(log_in_player(build_conn(), player), "/explore?category=making&q=pedal")

    assert has_element?(reloaded, "#explore-event-#{session.id}")
  end

  test "new activities can be prefilled from discovery", %{conn: conn} do
    {:ok, view, _} =
      live(
        log_in_player(conn, player_fixture()),
        "/hobbies/new?hobby=birdwatching&category=outdoors&kind=event"
      )

    assert has_element?(view, "input[name='session[hobby]'][value='birdwatching']")

    assert has_element?(
             view,
             "select[name='session[category]'] option[value='outdoors'][selected]"
           )

    assert has_element?(view, "select[name='session[kind]'] option[value='event'][selected]")
  end
end
