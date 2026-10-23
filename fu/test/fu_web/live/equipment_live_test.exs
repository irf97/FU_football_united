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

  test "receiver API fixes its zone, deduplicates retries and rejects altered retries", %{
    conn: conn
  } do
    owner = player_fixture()
    {:ok, _} = Fu.Equipment.create_asset(owner, %{name: "Ball", beacon_id: "api-ball"})
    {:ok, _, token} = Fu.Equipment.create_receiver(owner, %{name: "Collector", zone: "Court"})

    payload = %{
      "beacon_id" => "api-ball",
      "message_id" => "observation-1",
      "observed_at" => DateTime.to_iso8601(DateTime.utc_now() |> DateTime.truncate(:second)),
      "zone" => "Forged",
      "rssi" => -50
    }

    post_report = fn payload ->
      conn
      |> recycle()
      |> put_req_header("authorization", "Bearer " <> token)
      |> put_req_header("accept", "application/json")
      |> post("/api/equipment/observations", payload)
    end

    first = post_report.(payload)

    assert %{"source" => "receiver_report", "zone" => "Court", "id" => id} =
             json_response(first, 200)

    assert get_resp_header(first, "cache-control") == ["no-store"]
    assert %{"id" => ^id} = json_response(post_report.(payload), 200)

    assert json_response(post_report.(Map.put(payload, "rssi", -60)), 409) == %{
             "error" => "idempotency_conflict"
           }

    assert json_response(post_report.(Map.put(payload, "observed_at", "invalid")), 422) == %{
             "error" => "invalid_observation"
           }
  end
end
