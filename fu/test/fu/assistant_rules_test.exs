defmodule Fu.AssistantRulesTest do
  use ExUnit.Case, async: true
  alias Fu.Assistant.Rules
  @now ~U[2026-10-22 12:00:00Z]

  test "organizer explains commitments, venue access, timing and declared equipment condition" do
    session = %{
      status: "scheduled",
      mode: "committed",
      starts_at: @now,
      ends_at: DateTime.add(@now, 3600),
      access_status: "pending",
      min_participants: 2
    }

    members = [%{status: "joined"}, %{status: "committed"}]

    gear = [
      %{
        name: "Ball",
        condition: "maintenance",
        location: %{freshness: "fresh", source: "receiver_report"}
      }
    ]

    result = Rules.readiness(session, members, gear, @now)
    refute result.can_start?
    assert result.eligible == 1
    assert result.missing == 1
    assert Enum.find(result.checks, &(&1.key == "gear")).status == "needs_action"
    ready = %{session | mode: "open", access_status: "host_confirmed"}
    assert Rules.readiness(ready, members, [], @now).can_start?

    refute Rules.readiness(%{ready | starts_at: DateTime.add(@now, 1)}, members, [], @now).can_start?
  end

  test "a persistent deadline produces elapsed status without claiming a final result" do
    board = %{status: "running", remaining_seconds: 600, deadline_at: DateTime.add(@now, 20)}
    assert Rules.clock(board, @now) == %{status: "running", remaining_seconds: 20}

    assert Rules.clock(board, DateTime.add(@now, 30)) == %{
             status: "elapsed",
             remaining_seconds: 0
           }

    assert Rules.clock(
             %{board | status: "paused", deadline_at: nil, remaining_seconds: 17},
             DateTime.add(@now, 300)
           ) == %{status: "paused", remaining_seconds: 17}
  end
end
