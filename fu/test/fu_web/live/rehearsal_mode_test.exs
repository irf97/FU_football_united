defmodule FuWeb.RehearsalModeTest do
  use FuWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  setup do
    old = Application.fetch_env(:fu, :environment)

    on_exit(fn ->
      case old do
        {:ok, env} -> Application.put_env(:fu, :environment, env)
        :error -> Application.delete_env(:fu, :environment)
      end
    end)
  end

  test "rehearsal pages visibly identify synthetic conditions", %{conn: conn} do
    Application.put_env(:fu, :environment, :rehearsal)
    conn = get(conn, "/login")
    assert get_resp_header(conn, "x-fu-environment") == ["rehearsal"]
    {:ok, view, _} = live(conn)
    assert has_element?(view, "#simulation-banner")
  end

  test "production pages never present the rehearsal banner", %{conn: conn} do
    Application.put_env(:fu, :environment, :production)
    conn = get(conn, "/login")
    assert get_resp_header(conn, "x-fu-environment") == ["production"]
    {:ok, view, _} = live(conn)
    refute has_element?(view, "#simulation-banner")
  end
end
