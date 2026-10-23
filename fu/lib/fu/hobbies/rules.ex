defmodule Fu.Hobbies.Rules do
  @moduledoc "Activity rules shared by the persisted hobby session lifecycle."

  def join_error(session, occupied, now) do
    cond do
      session.status in ["cancelled", "completed"] -> :closed
      DateTime.compare(now, session.ends_at) != :lt -> :expired
      occupied >= session.capacity -> :full
      true -> nil
    end
  end

  def start_error(session, participants, now) do
    eligible =
      if session.mode == "committed",
        do: ["committed", "attended"],
        else: ["joined", "committed", "attended"]

    cond do
      session.status in ["cancelled", "completed"] -> :closed
      session.access_status != "host_confirmed" -> :access_unconfirmed
      Enum.count(participants, &(&1.status in eligible)) < session.min_participants -> :not_ready
      DateTime.compare(now, session.starts_at) == :lt -> :not_started
      DateTime.compare(now, session.ends_at) != :lt -> :expired
      true -> nil
    end
  end

  def withdrawal_error(participant, reason) do
    cond do
      !is_binary(reason) -> :reason_required
      String.length(reason) > 500 -> :reason_too_long
      participant.committed_at != nil and String.trim(reason) == "" -> :reason_required
      true -> nil
    end
  end
end
