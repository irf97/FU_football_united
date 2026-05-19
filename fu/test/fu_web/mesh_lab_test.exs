defmodule FuWeb.MeshLabTest do
  @moduledoc "The Mesh Lab renders, runs the live conformance harness, and simulates."
  use FuWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  setup %{conn: conn}, do: %{conn: log_in_player(conn, player_fixture())}

  test "mounts and the live conformance harness reports PASS, no FAIL", %{conn: conn} do
    {:ok, _lv, html} = live(conn, ~p"/lab")
    assert html =~ "MESH LAB"
    assert html =~ "PASS"
    refute html =~ "FAIL"
  end

  test "an honest round drives the witnessed rank to 51.5", %{conn: conn} do
    {:ok, lv, _} = live(conn, ~p"/lab")
    html = lv |> element("button[phx-click=honest]") |> render_click()
    assert html =~ "51.5"
  end

  test "byzantine relay is reported as not delivered (integrity)", %{conn: conn} do
    {:ok, lv, _} = live(conn, ~p"/lab")
    html = lv |> element("button[phx-click=byzantine]") |> render_click()
    assert html =~ "verified?=false"
  end
end
