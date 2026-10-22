defmodule Fu.Assistant.Rules do
  @moduledoc "Explainable organizer checks and a clock derived from a durable deadline."

  def readiness(session, participants, assets, now) do
    eligible_states =
      if session.mode == "committed",
        do: ["committed", "attended"],
        else: ["joined", "committed", "attended"]

    eligible = Enum.count(participants, &(&1.status in eligible_states))
    missing = max(session.min_participants - eligible, 0)

    time_ready =
      DateTime.compare(now, session.starts_at) != :lt and
        DateTime.compare(now, session.ends_at) == :lt

    gear_ready = Enum.all?(assets, &(&1.condition == "ready"))

    checks = [
      %{
        key: "access",
        label: "Venue access",
        status: if(session.access_status == "host_confirmed", do: "ready", else: "needs_action"),
        detail:
          if(session.access_status == "host_confirmed",
            do: "Confirmed by the host. Check any operator restrictions.",
            else: "Ask the host to confirm access with the venue operator."
          )
      },
      %{
        key: "people",
        label: "People",
        status: if(missing == 0, do: "ready", else: "needs_action"),
        detail:
          "#{eligible} eligible · minimum #{session.min_participants}. #{if session.mode == "committed", do: "Explicit commitments count.", else: "Joined participants count."}"
      },
      %{
        key: "time",
        label: "Event window",
        status: if(time_ready, do: "ready", else: "needs_action"),
        detail:
          if(time_ready,
            do: "Inside the scheduled time window.",
            else: "Wait for the start time or arrange another event if the window has ended."
          )
      },
      %{
        key: "gear",
        label: "Equipment",
        status:
          cond do
            assets == [] -> "optional"
            gear_ready -> "ready"
            true -> "needs_action"
          end,
        detail:
          cond do
            assets == [] ->
              "No gear reserved. Add items if this activity needs them."

            gear_ready ->
              "#{length(assets)} reserved items declared ready by their owners. Check the physical items before use."

            true ->
              "A reserved item needs maintenance or has been retired. Replace it or release its reservation."
          end
      }
    ]

    %{
      eligible: eligible,
      missing: missing,
      checks: checks,
      can_start?:
        session.status == "scheduled" and Enum.all?(checks, &(&1.status != "needs_action"))
    }
  end

  def clock(%{status: "running", deadline_at: deadline}, now) do
    seconds = max(DateTime.diff(deadline, now, :second), 0)
    %{status: if(seconds == 0, do: "elapsed", else: "running"), remaining_seconds: seconds}
  end

  def clock(board, _), do: %{status: board.status, remaining_seconds: board.remaining_seconds}
end
