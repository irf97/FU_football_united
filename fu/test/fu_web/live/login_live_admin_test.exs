defmodule FuWeb.LoginLiveAdminTest do
  @moduledoc """
  The admin gate must be config-driven and FAIL-CLOSED:
  no secret configured ⇒ admin login is disabled (never a hardcoded
  fallback). Pre-launch blocker — credential out of source.
  """
  # async: false — these tests mutate Application env (global).
  use FuWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  alias Fu.Fixtures

  setup do
    prev = Application.fetch_env(:fu, :admin_password)

    on_exit(fn ->
      case prev do
        {:ok, v} -> Application.put_env(:fu, :admin_password, v)
        :error -> Application.delete_env(:fu, :admin_password)
      end
    end)

    :ok
  end

  defp open_admin(conn) do
    {:ok, lv, _} = live(conn, ~p"/login")
    lv |> element("button[phx-click=show-admin]") |> render_click()
    lv
  end

  defp submit(lv, pw),
    do: lv |> form("form[phx-submit=admin-login]", %{password: pw}) |> render_submit()

  test "succeeds with the configured secret and redirects to /admin", %{conn: conn} do
    Application.put_env(:fu, :admin_password, "s3cret-under-test")
    Fixtures.player_fixture()
    lv = open_admin(conn)

    assert {:error, {:redirect, %{to: path}}} = submit(lv, "s3cret-under-test")
    assert path =~ "/session/"
    assert path =~ "to=%2Fadmin"
  end

  test "is DISABLED (fail-closed) when no secret is configured", %{conn: conn} do
    Application.delete_env(:fu, :admin_password)
    Fixtures.player_fixture()
    lv = open_admin(conn)

    # Even the old hardcoded value must NOT be accepted.
    html = submit(lv, "boobs")
    assert html =~ "Admin login is disabled"
    refute html =~ "session/"
  end

  test "is DISABLED when the secret is configured empty", %{conn: conn} do
    Application.put_env(:fu, :admin_password, "")
    lv = open_admin(conn)

    assert submit(lv, "") =~ "Admin login is disabled"
  end

  test "rejects a wrong password when a secret is configured", %{conn: conn} do
    Application.put_env(:fu, :admin_password, "s3cret-under-test")
    lv = open_admin(conn)

    assert submit(lv, "not-it") =~ "Wrong password"
  end
end
