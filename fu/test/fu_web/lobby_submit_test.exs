defmodule FuWeb.LobbySubmitTest do
  @moduledoc "AUDIT #1 — the captain submits the final score from the lobby."
  use FuWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias Fu.{Queues, Balance, Lobby, Matches, Voting}

  setup %{conn: conn} do
    q = queue_fixture(format: "8v8", fill: :all, state: "confirmed")
    {:ok, q} = Balance.assign_teams(q.id)
    captain_m = Enum.find(q.memberships, &(&1.team == "A"))
    {:ok, _} = Lobby.claim_captain(q, captain_m.player)

    %{conn: log_in_player(conn, captain_m.player), queue: q}
  end

  test "captain submitting the score completes the match and finalizes ranks",
       %{conn: conn, queue: q} do
    {:ok, lv, _html} = live(conn, ~p"/lobby/#{q.id}")

    lv
    |> form("#submit-result", %{"score_a" => "3", "score_b" => "2"})
    |> render_submit()

    assert_redirect(lv, ~p"/postmatch/#{q.id}")

    result = Matches.result(q.id)
    assert result.score_a == 3 and result.score_b == 2
    assert result.completed_at != nil
    assert Voting.voting_open?(q.id)
    assert Queues.get_queue!(q.id).state == "completed"
  end

  test "a non-captain does not see the submit-score form", %{queue: q} do
    other = Enum.find(q.memberships, &(&1.team == "B" and not &1.is_captain)).player
    conn = log_in_player(Phoenix.ConnTest.build_conn(), other)
    {:ok, _lv, html} = live(conn, ~p"/lobby/#{q.id}")
    refute html =~ "submit-result"
  end
end
