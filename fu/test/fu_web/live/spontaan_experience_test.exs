defmodule FuWeb.SpontaanExperienceTest do
  use FuWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  test "Spontaan owns the shared identity and install metadata", %{conn: conn} do
    {:ok, view, html} = live(conn, "/login")
    assert has_element?(view, "#spontaan-brand", "spontaan")
    assert html =~ "Spontaan"
    refute has_element?(view, "#experience-identity", "Football United")

    manifest = get(build_conn(), "/manifest.webmanifest") |> response(200) |> Jason.decode!()
    assert manifest["name"] == "Spontaan"
    assert manifest["short_name"] == "Spontaan"
    assert manifest["start_url"] == "/explore"
  end

  test "a main hobby and experience persist across reconnect and navigation", %{conn: conn} do
    player = player_fixture()
    {:ok, view, _} = live(log_in_player(conn, player), "/profile")
    assert has_element?(view, "#experience-form")

    view
    |> form("#experience-form", experience: %{main_hobby: "guitar", experience_theme: "auto"})
    |> render_submit()

    assert has_element?(view, "#spontaan-shell[data-experience='music']")
    assert has_element?(view, "#experience-identity", "After Hours")

    {:ok, reconnected, _} = live(log_in_player(build_conn(), player), "/explore")
    assert has_element?(reconnected, "#spontaan-shell[data-experience='music']")
    assert has_element?(reconnected, "#main-hobby-link[href='/explore?hobby=guitar']")
    refute has_element?(reconnected, "#football-rank")
  end

  test "Football United remains a selectable experience without changing hobby access", %{
    conn: conn
  } do
    player = player_fixture()
    {:ok, view, _} = live(log_in_player(conn, player), "/profile")

    view
    |> form("#experience-form", experience: %{main_hobby: "futsal", experience_theme: "football"})
    |> render_submit()

    assert has_element?(view, "#spontaan-brand", "spontaan")
    assert has_element?(view, "#experience-identity", "Football United")
    assert has_element?(view, "#spontaan-shell[data-experience='football']")

    {:ok, explore, _} = live(log_in_player(build_conn(), player), "/explore")
    assert has_element?(explore, "#explore-all")
    assert has_element?(explore, "#explore-filter")
    refute has_element?(explore, "#football-rank")
  end
end
