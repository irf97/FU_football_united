defmodule FuWeb.LockUITest do
  @moduledoc "Soft-join → hard-lock wiring: Browse lock button + Lobby lock-in."
  use FuWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias Fu.Queues
  alias Fu.Queues.QueueMembership

  defp locked?(qid, pid) do
    m = Fu.Repo.get_by(QueueMembership, queue_id: qid, player_id: pid)
    m && m.locked_at != nil
  end

  test "Browse: a joined player can lock in from the queue card", %{conn: conn} do
    p = player_fixture(primary_position: "MID")
    q = queue_fixture(format: "8v8", scheduled_in: 5 * 3600)
    {:ok, _} = Queues.join(q, p)

    {:ok, lv, _} = live(log_in_player(conn, p), ~p"/browse")

    lv
    |> element("button[phx-click=lock][phx-value-id='#{q.id}']")
    |> render_click()

    assert locked?(q.id, p.id)
    assert render(lv) =~ "Locked in"
  end

  test "Lobby: the player can lock in, and it can't be undone by leaving",
       %{conn: conn} do
    q = queue_fixture(format: "8v8", fill: :all, state: "confirmed", scheduled_in: 5 * 3600)
    {:ok, q} = Fu.Balance.assign_teams(q.id)
    m = Enum.find(q.memberships, &(&1.team == "A"))

    {:ok, lv, _} = live(log_in_player(conn, m.player), ~p"/lobby/#{q.id}")

    lv |> element("button[phx-click=lock-in]") |> render_click()

    assert locked?(q.id, m.player_id)
    # Locked → leaving is allowed but penalised (ban), not blocked.
    assert {:penalised, _tier, _until} = Queues.leave(Queues.get_queue!(q.id), m.player)
  end
end
