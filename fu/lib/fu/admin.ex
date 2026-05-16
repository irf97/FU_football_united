defmodule Fu.Admin do
  @moduledoc """
  App-management read model: every player with their derived live status
  (idle · in queue · in match), specs, and avatar, plus roll-up stats.
  Admin-gated (see `Fu.Accounts.Player.is_admin`).
  """

  import Ecto.Query
  alias Fu.Repo
  alias Fu.Accounts.Player
  alias Fu.Queues.{Queue, QueueMembership}

  @doc """
  `%{players: [%{player: %Player{}, status: :idle | :in_queue | :in_match,
  where: queue_id | nil}], stats: %{...}}` — one query for memberships,
  reduced in memory (player set is small in v1).
  """
  def overview do
    players = Repo.all(from p in Player, order_by: [desc: p.rank])

    # player_id => list of {queue_state, queue_id} for active memberships
    member_states =
      from(m in QueueMembership,
        join: q in Queue,
        on: q.id == m.queue_id,
        where: m.status == "queued",
        select: {m.player_id, q.state, q.id}
      )
      |> Repo.all()
      |> Enum.group_by(fn {pid, _, _} -> pid end, fn {_, st, qid} -> {st, qid} end)

    rows =
      Enum.map(players, fn p ->
        {status, where} = derive_status(Map.get(member_states, p.id, []))
        %{player: p, status: status, where: where}
      end)

    %{players: rows, stats: tally(rows)}
  end

  # in_match wins over in_queue wins over idle (spec: confirmed = match/lobby).
  defp derive_status([]), do: {:idle, nil}

  defp derive_status(states) do
    cond do
      match = Enum.find(states, fn {st, _} -> st == "confirmed" end) ->
        {:in_match, elem(match, 1)}

      q = Enum.find(states, fn {st, _} -> st in ["open", "locked"] end) ->
        {:in_queue, elem(q, 1)}

      true ->
        {:idle, nil}
    end
  end

  defp tally(rows) do
    by = Enum.frequencies_by(rows, & &1.status)

    %{
      total: length(rows),
      idle: Map.get(by, :idle, 0),
      in_queue: Map.get(by, :in_queue, 0),
      in_match: Map.get(by, :in_match, 0),
      suspended: Enum.count(rows, &Fu.Accounts.suspended?(&1.player))
    }
  end

  @doc "Admin action: 14-day queue suspension toggle (spec §2.9)."
  def toggle_suspend(%Player{} = p) do
    until =
      if Fu.Accounts.suspended?(p) do
        nil
      else
        DateTime.utc_now() |> DateTime.add(14 * 86_400, :second) |> DateTime.truncate(:second)
      end

    p
    |> Ecto.Changeset.change(suspended_until: until)
    |> Repo.update()
  end

  def get_player!(id), do: Repo.get!(Player, id)
end
