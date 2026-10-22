defmodule FuWeb.EquipmentLiveTest do
  use FuWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  test "gear requires authentication", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/login"}}} = live(conn, "/equipment")
  end

  test "owner creates inventory and reports a source-labeled location", %{conn: conn} do
    owner = player_fixture()
    {:ok, view, _} = live(log_in_player(conn, owner), "/equipment")

    view
    |> form("#equipment-form",
      asset: %{name: "Practice ball", beacon_id: "practice-ball", home_zone: "Shelf A"}
    )
    |> render_submit()

    [asset] = Fu.Equipment.list_assets(owner)
    assert has_element?(view, "#equipment-#{asset.id}")
    view |> form("#locate-#{asset.id}", location: %{zone: "Court A"}) |> render_submit()
    assert has_element?(view, "#equipment-#{asset.id} [data-source='manual']")
    refute has_element?(view, "[data-source='verified']")
    {:ok, stranger, _} = live(log_in_player(build_conn(), player_fixture()), "/equipment")
    refute has_element?(stranger, "#equipment-#{asset.id}")
  end

  test "ingest API refuses unauthenticated receivers", %{conn: conn} do
    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> post("/api/equipment/observations", %{})

    assert json_response(conn, 401) == %{"error" => "unauthorized"}
  end
end
