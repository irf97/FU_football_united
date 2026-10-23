defmodule FuWeb.LoginLiveOtpTest do
  use FuWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  setup do
    previous = Application.fetch_env(:fu, :show_otp_codes)
    sms = Application.fetch_env(:fu, Fu.SMS)
    Application.delete_env(:fu, :show_otp_codes)

    on_exit(fn ->
      for {key, value} <- [{:show_otp_codes, previous}, {Fu.SMS, sms}] do
        case value do
          {:ok, config} -> Application.put_env(:fu, key, config)
          :error -> Application.delete_env(:fu, key)
        end
      end
    end)
  end

  test "the login page never shows the OTP by default", %{conn: conn} do
    {:ok, view, _} = live(conn, "/login")
    view |> form("form[phx-submit=send]", phone: "+31680000002") |> render_submit()
    assert has_element?(view, "input[name=code]")
    refute has_element?(view, "div", "demo code:")
  end

  test "development can explicitly enable a visible demo code", %{conn: conn} do
    Application.put_env(:fu, :show_otp_codes, true)
    {:ok, view, _} = live(conn, "/login")
    view |> form("form[phx-submit=send]", phone: "+31680000003") |> render_submit()
    assert has_element?(view, "div", "demo code:")
  end

  test "unconfigured delivery keeps the phone form and reports the failure", %{conn: conn} do
    Application.put_env(:fu, Fu.SMS, adapter: Fu.SMS.HTTPAdapter)
    {:ok, view, _} = live(conn, "/login")
    view |> form("form[phx-submit=send]", phone: "+31680000004") |> render_submit()
    assert has_element?(view, "input[name=phone]")
    refute has_element?(view, "input[name=code]")
    assert has_element?(view, "p", "We couldn't send your code. Try again later.")
  end
end
