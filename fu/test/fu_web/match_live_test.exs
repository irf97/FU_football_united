defmodule FuWeb.MatchLiveTest do
  @moduledoc "AUDIT #12 — live in-play match surface: kickoff, captain pause, final whistle."
  use FuWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias Fu.{Balance, Lobby, Matches, Queues}

  setup %{conn: conn} do
    q = queue_fixture(format: "8v8", fill: :all, state: "confirmed")
    {:ok, q} = Balance.assign_teams(q.id)
    captain_m = Enum.find(q.memberships, &(&1.team == "A"))
    {:ok, _} = Lobby.claim_captain(q, captain_m.player)
    other = Enum.find(q.memberships, &(&1.team == "B" and not &1.is_captain)).player

    %{conn: conn, queue: q, captain: captain_m.player, other: other}
  end

  test "captain kicks off, pauses and resumes the live clock",
       %{conn: conn, queue: q, captain: captain} do
    conn = log_in_player(conn, captain)
    {:ok, lv, _html} = live(conn, ~p"/match/#{q.id}")

    assert has_element?(lv, "#kickoff")
    lv |> element("#kickoff") |> render_click()
    assert Matches.result(q.id).started_at != nil

    assert has_element?(lv, "#pause")
    lv |> element("#pause") |> render_click()
    assert Matches.paused?(Matches.result(q.id))
    assert has_element?(lv, "#paused-banner")

    assert has_element?(lv, "#resume")
    lv |> element("#resume") |> render_click()
    refute Matches.paused?(Matches.result(q.id))
  end

  test "a non-captain sees the live match but no captain controls",
       %{conn: conn, queue: q, other: other} do
    {:ok, _} = Matches.kickoff(q.id)
    conn = log_in_player(conn, other)
    {:ok, lv, _html} = live(conn, ~p"/match/#{q.id}")

    refute has_element?(lv, "#kickoff")
    refute has_element?(lv, "#pause")
    refute has_element?(lv, "#match-finish")
  end

  test "captain blows the final whistle → match completes and redirects to post-match",
       %{conn: conn, queue: q, captain: captain} do
    {:ok, _} = Matches.kickoff(q.id)
    conn = log_in_player(conn, captain)
    {:ok, lv, _html} = live(conn, ~p"/match/#{q.id}")

    lv
    |> form("#match-finish", %{"score_a" => "2", "score_b" => "1"})
    |> render_submit()

    assert_redirect(lv, ~p"/postmatch/#{q.id}")
    result = Matches.result(q.id)
    assert result.score_a == 2 and result.score_b == 1
    assert result.completed_at != nil
    assert Queues.get_queue!(q.id).state == "completed"
  end

  test "the team captain can edit tactics and they persist",
       %{conn: conn, queue: q, captain: captain} do
    conn = log_in_player(conn, captain)
    {:ok, lv, _html} = live(conn, ~p"/match/#{q.id}")

    assert has_element?(lv, "#tactics-form")

    lv
    |> form("#tactics-form", %{
      "formation" => "3-5-2",
      "style" => "Counter",
      "notes" => "Sit deep, break fast."
    })
    |> render_submit()

    t = Fu.Tactics.get(q.id, "A")
    assert t.formation == "3-5-2"
    assert t.style == "Counter"
  end

  test "a non-captain only previews tactics — no edit form",
       %{conn: conn, queue: q, other: other} do
    conn = log_in_player(conn, other)
    {:ok, lv, _html} = live(conn, ~p"/match/#{q.id}")

    refute has_element?(lv, "#tactics-form")
    assert has_element?(lv, "#tactics-preview")
  end
end
