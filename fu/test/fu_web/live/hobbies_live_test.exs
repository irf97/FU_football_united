defmodule FuWeb.HobbiesLiveTest do
  use FuWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias Fu.Hobbies

  defp create(host, extra \\ %{}) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Hobbies.create_session(
      host,
      Map.merge(
        %{
          title: "Campus guitar",
          hobby: "guitar",
          mode: "open",
          place: "Campus music room",
          starts_at: DateTime.add(now, 3600),
          ends_at: DateTime.add(now, 7200),
          capacity: 4,
          min_participants: 1
        },
        extra
      )
    )
  end

  test "hobby discovery requires authentication", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/login"}}} = live(conn, "/hobbies")
  end

  test "a host creates a session and sees honest pending access", %{conn: conn} do
    host = player_fixture()
    {:ok, view, _} = live(log_in_player(conn, host), "/hobbies/new")
    at = DateTime.utc_now() |> DateTime.add(3600) |> DateTime.truncate(:second)

    view
    |> form("#hobby-session-form",
      session: %{
        title: "Table tennis",
        hobby: "table tennis",
        mode: "practice",
        place: "Campus tables",
        starts_at: DateTime.to_iso8601(at),
        ends_at: DateTime.to_iso8601(DateTime.add(at, 3600)),
        capacity: "4",
        min_participants: "2"
      }
    )
    |> render_submit()

    [session] = Hobbies.list_sessions()
    assert session.host_id == host.id
    assert_redirect(view, "/hobbies/#{session.id}")
    {:ok, detail, _} = live(log_in_player(build_conn(), host), "/hobbies/#{session.id}")
    assert has_element?(detail, "#access-pending")
    assert has_element?(detail, "#host-controls")
  end

  test "invalid create input keeps the form usable and stores nothing", %{conn: conn} do
    host = player_fixture()
    {:ok, view, _} = live(log_in_player(conn, host), "/hobbies/new")
    view |> form("#hobby-session-form", session: %{title: "", capacity: "0"}) |> render_submit()
    assert has_element?(view, "#hobby-session-form")
    assert Hobbies.list_sessions() == []
  end

  test "a participant discovers, joins, leaves and reloads persisted state", %{conn: conn} do
    host = player_fixture()
    player = player_fixture()
    {:ok, session} = create(host)
    {:ok, browse, _} = live(log_in_player(conn, player), "/hobbies")
    assert has_element?(browse, "#hobby-session-#{session.id}")
    {:ok, view, _} = live(log_in_player(build_conn(), player), "/hobbies/#{session.id}")
    refute has_element?(view, "#host-controls")
    view |> element("#join-session") |> render_click()
    assert has_element?(view, "#leave-session-form")
    refute has_element?(view, "#commit-session")
    view |> form("#leave-session-form", leave: %{reason: ""}) |> render_submit()
    assert has_element?(view, "#join-session")
    {:ok, reloaded, _} = live(log_in_player(build_conn(), player), "/hobbies/#{session.id}")
    assert has_element?(reloaded, "#join-session")
    assert [%{status: "left"}] = Hobbies.get_session(session.id).participants
  end

  test "a committed participant can explicitly commit through the interface", %{conn: conn} do
    host = player_fixture()
    player = player_fixture()
    {:ok, session} = create(host, %{hobby: "futsal", mode: "committed"})
    {:ok, view, _} = live(log_in_player(conn, player), "/hobbies/#{session.id}")
    view |> element("#join-session") |> render_click()
    view |> element("#commit-session") |> render_click()
    assert [%{status: "committed"}] = Hobbies.get_session(session.id).participants
    view |> form("#leave-session-form", leave: %{reason: ""}) |> render_submit()
    assert [%{status: "committed"}] = Hobbies.get_session(session.id).participants
    view |> form("#leave-session-form", leave: %{reason: "Exam moved"}) |> render_submit()

    assert [%{status: "left", withdrawal_reason: "Exam moved"}] =
             Hobbies.get_session(session.id).participants
  end

  test "host cancellation reaches another connected participant", %{conn: conn} do
    host = player_fixture()
    player = player_fixture()
    {:ok, session} = create(host)
    {:ok, _} = Hobbies.join(session.id, player)
    {:ok, guest, _} = live(log_in_player(conn, player), "/hobbies/#{session.id}")
    {:ok, owner, _} = live(log_in_player(build_conn(), host), "/hobbies/#{session.id}")

    owner
    |> form("#cancel-session-form", cancel: %{reason: "Room unavailable"})
    |> render_submit()

    assert has_element?(owner, "#session-cancelled")
    assert has_element?(guest, "#session-cancelled")
    refute has_element?(guest, "#join-session")
  end

  test "host and participant complete the full committed session through LiveView", %{conn: conn} do
    host = player_fixture()
    player = player_fixture()
    {:ok, session} = create(host, %{hobby: "futsal", mode: "committed", min_participants: 1})
    {:ok, guest, _} = live(log_in_player(conn, player), "/hobbies/#{session.id}")
    {:ok, owner, _} = live(log_in_player(build_conn(), host), "/hobbies/#{session.id}")
    guest |> element("#join-session") |> render_click()
    guest |> element("#commit-session") |> render_click()
    owner |> form("#confirm-access-form", access: %{note: "Operator confirmed the slot"}) |> render_submit()
    assert has_element?(guest, "#access-confirmed")
    session |> Ecto.Changeset.change(starts_at: DateTime.utc_now() |> DateTime.add(-60) |> DateTime.truncate(:second)) |> Fu.Repo.update!()
    owner |> element("#start-session") |> render_click()
    guest |> element("#attend-session") |> render_click()
    assert has_element?(guest, "#attendance-recorded")
    owner |> element("#finish-session") |> render_click()
    assert has_element?(owner, "#session-completed")
    assert has_element?(guest, "#session-completed")
    {:ok, reloaded, _} = live(log_in_player(build_conn(), player), "/hobbies/#{session.id}")
    assert has_element?(reloaded, "#session-completed")
    assert [%{status: "attended"}] = Hobbies.get_session(session.id).participants
  end

  test "missing or malformed sessions show a recoverable page", %{conn: conn} do
    player = player_fixture()

    for id <- ["bad-id", "999999999"] do
      {:ok, view, _} = live(log_in_player(conn, player), "/hobbies/#{id}")
      assert has_element?(view, "#session-not-found")
      assert has_element?(view, "a[href='/hobbies']")
    end
  end
end
