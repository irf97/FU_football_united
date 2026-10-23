defmodule FuWeb.LoginReturnTest do
  use FuWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  alias Fu.{Accounts, Hobbies, Repo}
  alias Fu.Accounts.OtpCode
  alias FuWeb.PlayerAuth

  test "an invitation remembers the exact destination before redirecting to login", %{conn: conn} do
    event = event_fixture()
    destination = "/hobbies/#{event.id}?from=invitation"
    redirected = get(conn, destination)

    assert redirected_to(redirected) == "/login"
    assert get_session(redirected, :player_return_to) == destination
  end

  test "a new participant completes OTP and joins the invited event without football setup", %{
    conn: conn
  } do
    event = event_fixture()
    destination = "/hobbies/#{event.id}?from=invitation"
    redirected = get(conn, destination)
    {:ok, login, _} = live(recycle(redirected), "/login")
    handoff = complete_otp(login, "+31687000001")
    signed_in = get(recycle(redirected), handoff)

    assert redirected_to(signed_in) == destination
    assert get_session(signed_in, :player_return_to) == nil
    {:ok, event_view, _} = live(recycle(signed_in), destination)
    assert has_element?(event_view, "#join-session")
    refute has_element?(event_view, "#football-rank")
    event_view |> element("#join-session") |> render_click()

    player = Accounts.get_player(get_session(signed_in, :player_id))
    assert Hobbies.membership(Hobbies.get_session(event.id), player).status == "joined"
  end

  test "login defaults to Explore and presents the shared hobby entry", %{conn: conn} do
    {:ok, login, _} = live(conn, "/login")
    assert has_element?(login, "#login-introduction", "Find your next thing")
    handoff = complete_otp(login, "+31687000002")
    signed_in = get(conn, handoff)
    assert redirected_to(signed_in) == "/explore"
    {:ok, explore, _} = live(recycle(signed_in), "/explore")
    assert has_element?(explore, "#explore-filter")
    refute has_element?(explore, "#football-rank")
  end

  test "the captured tab destination survives another tab and handoff query tampering", %{
    conn: conn
  } do
    event = event_fixture()
    destination = "/hobbies/#{event.id}"
    redirected = get(conn, destination)
    {:ok, login, _} = live(recycle(redirected), "/login")
    handoff = complete_otp(login, "+31687000003")

    other_tab = get(recycle(redirected), "/equipment")
    assert get_session(other_tab, :player_return_to) == "/equipment"
    signed_in = get(recycle(other_tab), handoff <> "?to=%2Fadmin")
    assert redirected_to(signed_in) == destination
    refute Accounts.get_player(get_session(signed_in, :player_id)).is_admin
  end

  test "filtered discovery and prefilled creation links survive legacy handoff", %{conn: conn} do
    player = player_fixture()

    for destination <- [
          "/explore?category=music&q=guitar%20night",
          "/hobbies/new?hobby=birdwatching&category=outdoors"
        ] do
      redirected = get(conn, destination)
      token = PlayerAuth.login_token(player.id)
      signed_in = get(recycle(redirected), "/session/#{token}")
      assert redirected_to(signed_in) == destination
    end
  end

  test "legacy handoff rejects external and auth-loop destinations", %{conn: conn} do
    player = player_fixture()
    token = PlayerAuth.login_token(player.id)

    for destination <- [
          "https://outside.example",
          "//outside.example",
          "/session/token",
          "/login"
        ] do
      signed_in = get(conn, "/session/#{token}?" <> URI.encode_query(%{"to" => destination}))
      assert redirected_to(signed_in) == "/explore"
    end
  end

  test "returning to the assistant does not grant event membership", %{conn: conn} do
    event = event_fixture()
    destination = "/hobbies/#{event.id}/assistant"
    redirected = get(conn, destination)
    {:ok, login, _} = live(recycle(redirected), "/login")
    handoff = complete_otp(login, "+31687000004")
    signed_in = get(recycle(redirected), handoff)

    assert redirected_to(signed_in) == destination
    {:ok, view, _} = live(recycle(signed_in), destination)
    assert has_element?(view, "#assistant-unavailable")
    refute has_element?(view, "#configure-scorekeeper")
    player = Accounts.get_player(get_session(signed_in, :player_id))
    assert Hobbies.membership(Hobbies.get_session(event.id), player) == nil
  end

  test "an invalid handoff never signs in or consumes the pending destination", %{conn: conn} do
    redirected = get(conn, "/equipment")
    rejected = get(recycle(redirected), "/session/not-a-valid-token")
    assert redirected_to(rejected) == "/login"
    assert get_session(rejected, :player_id) == nil
    assert get_session(rejected, :player_return_to) == "/equipment"
  end

  test "authenticated users opening login land on Explore", %{conn: conn} do
    signed_in = conn |> log_in_player(player_fixture()) |> get("/login")
    assert redirected_to(signed_in) == "/explore"
  end

  defp complete_otp(view, phone) do
    view |> form("form[phx-submit=send]", phone: phone) |> render_submit()
    code = Repo.get_by!(OtpCode, phone: phone).code

    assert {:error, {:redirect, %{to: path}}} =
             view |> form("form[phx-submit=verify]", code: code) |> render_submit()

    path
  end

  defp event_fixture do
    at = DateTime.utc_now() |> DateTime.add(3600) |> DateTime.truncate(:second)

    {:ok, event} =
      Hobbies.create_session(player_fixture(), %{
        title: "Invited guitar practice",
        hobby: "guitar",
        place: "Campus room",
        mode: "open",
        starts_at: at,
        ends_at: DateTime.add(at, 3600),
        capacity: 4,
        min_participants: 1
      })

    event
  end
end
