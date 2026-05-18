defmodule FuWeb.GroupQueueTest do
  @moduledoc "AUDIT #6 — a formed friend group can actually queue from the UI (spec §2.12)."
  use FuWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias Fu.{Groups, Queues}

  setup %{conn: conn} do
    leader = player_fixture(primary_position: "MID")
    {:ok, group} = Groups.create_group(leader)
    queue = queue_fixture(format: "8v8")
    %{conn: log_in_player(conn, leader), leader: leader, group: group, queue: queue}
  end

  test "leader sees a Queue-group button for a fitting queue and clicking it queues the group",
       %{conn: conn, leader: leader, group: group, queue: queue} do
    {:ok, lv, html} = live(conn, ~p"/")
    assert html =~ "queue-group"

    lv
    |> element("#queue-group-#{queue.id}")
    |> render_click()

    assert Queues.get_queue!(queue.id).memberships
           |> Enum.any?(&(&1.player_id == leader.id and &1.status == "queued"))

    assert Fu.Repo.reload!(group).queue_id == queue.id
  end

  test "a queue the group cannot fit shows no Queue-group button", %{conn: conn, group: group} do
    # Fill every slot so the leader cannot be placed → group does not fit.
    full = queue_fixture(format: "8v8", fill: :all)
    {:ok, lv, _html} = live(conn, ~p"/")
    refute has_element?(lv, "#queue-group-#{full.id}")
    assert Fu.Repo.reload!(group).queue_id == nil
  end
end
