defmodule Fu.Hobbies.RulesTest do
  use ExUnit.Case, async: true
  alias Fu.Hobbies.Rules

  @now ~U[2026-10-22 16:00:00Z]
  defp session(extra \\ %{}) do
    Map.merge(
      %{
        mode: "committed",
        status: "scheduled",
        access_status: "host_confirmed",
        starts_at: DateTime.add(@now, -60),
        ends_at: DateTime.add(@now, 3600),
        capacity: 4,
        min_participants: 2
      },
      extra
    )
  end

  test "committed sessions need commitments; open and practice sessions accept presence" do
    joined = [%{status: "joined"}, %{status: "joined"}]
    assert Rules.start_error(session(), joined, @now) == :not_ready
    assert Rules.start_error(session(%{mode: "open"}), joined, @now) == nil
    assert Rules.start_error(session(%{mode: "practice"}), joined, @now) == nil

    assert Rules.start_error(session(), [%{status: "committed"}, %{status: "committed"}], @now) ==
             nil
  end

  test "host confirmation, time window and actual attendance constrain readiness" do
    committed = [%{status: "committed"}, %{status: "committed"}]

    assert Rules.start_error(session(%{access_status: "pending"}), committed, @now) ==
             :access_unconfirmed

    assert Rules.start_error(session(%{starts_at: DateTime.add(@now, 60)}), committed, @now) ==
             :not_started

    assert Rules.start_error(session(%{ends_at: @now}), committed, @now) == :expired

    assert Rules.start_error(session(), [%{status: "left"}, %{status: "cancelled"}], @now) ==
             :not_ready
  end

  test "capacity and closing time bound new joins" do
    assert Rules.join_error(session(), 4, @now) == :full
    assert Rules.join_error(session(), 3, @now) == nil
    assert Rules.join_error(session(%{ends_at: @now}), 0, @now) == :expired
    assert Rules.join_error(session(%{status: "cancelled"}), 0, @now) == :closed
    assert Rules.join_error(session(%{status: "completed"}), 0, @now) == :closed
  end

  test "committed departures need an explanation; ordinary presence can leave freely" do
    assert Rules.withdrawal_error(%{committed_at: @now}, " ") == :reason_required
    assert Rules.withdrawal_error(%{committed_at: @now}, "Exam rescheduled") == nil
    assert Rules.withdrawal_error(%{committed_at: nil}, "") == nil

    assert Rules.withdrawal_error(%{committed_at: nil}, String.duplicate("x", 501)) ==
             :reason_too_long
  end
end
