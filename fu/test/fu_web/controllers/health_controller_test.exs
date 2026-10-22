defmodule FuWeb.HealthControllerTest do
  use FuWeb.ConnCase, async: true

  test "readiness checks the database without requiring a login", %{conn: conn} do
    conn = get(conn, "/healthz")
    assert json_response(conn, 200) == %{"status" => "ok"}
    assert get_resp_header(conn, "cache-control") == ["no-store"]
  end
end
