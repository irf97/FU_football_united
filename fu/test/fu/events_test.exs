defmodule Fu.EventsTest do
  @moduledoc "Semantic event log — IrfTek paper §6 alignment slice."
  use Fu.DataCase, async: true

  alias Fu.{Events, Queues}

  test "record/recent/to_jsonl round-trips in the paper's §6.3 shape" do
    :ok = Events.record("player.join_queue", %{player_id: 102, queue_id: 49, position: "GK"})

    [ev] = Events.recent()
    assert ev.type == "player.join_queue"
    assert ev.domain == "football"
    assert ev.payload["player_id"] == 102

    line = Events.to_jsonl([ev])
    decoded = Jason.decode!(line)
    assert decoded["type"] == "player.join_queue"
    assert decoded["domain"] == "football"
    assert decoded["position"] == "GK"
    assert is_binary(decoded["t"])
  end

  test "joining a queue emits a player.join_queue semantic event" do
    q = queue_fixture(format: "8v8", scheduled_in: 6 * 3600)
    p = player_fixture(primary_position: "MID")

    {:ok, _} = Queues.join(q, p)

    types = Events.recent() |> Enum.map(& &1.type)
    assert "player.join_queue" in types

    ev = Enum.find(Events.recent(), &(&1.type == "player.join_queue"))
    assert ev.payload["player_id"] == p.id
    assert ev.payload["queue_id"] == q.id
  end

  test "leave + state change emit their semantic events" do
    q = queue_fixture(format: "8v8", scheduled_in: 6 * 3600)
    p = player_fixture(primary_position: "MID")
    {:ok, _} = Queues.join(q, p)
    :ok = Queues.leave(Queues.get_queue!(q.id), p)

    q2 = queue_fixture(format: "8v8", fill: :all)
    {:confirmed, _} = Queues.resolve_partial_fill(q2)

    types = Events.recent(200) |> Enum.map(& &1.type) |> Enum.uniq()
    assert "player.leave_queue" in types
    assert "queue.confirmed" in types
  end

  test "a logging failure never breaks the domain action (side-effect only)" do
    # bad payload value still returns :ok (jsonb can hold it; record never raises)
    assert :ok = Events.record("x.test", %{"k" => {:not, :jsonable}})
  end
end
