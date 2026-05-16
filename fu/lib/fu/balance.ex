defmodule Fu.Balance do
  @moduledoc """
  Auto-balance & team assignment (spec §2.7, S45/S46).

  When a queue confirms, queued players are split into two teams (`"A"`/`"B"`)
  with roughly equal aggregate rank while satisfying per-team position quotas.

  The algorithm is intentionally simple and **deterministic** so that the
  question "why is X on the other team?" always has a derivable answer
  (spec §2.7):

    1. Sort all queued players by rank descending (tie-break: player id asc).
    2. Snake-draft alternately into Team A / Team B.
    3. Position-feasibility check: each team meets its per-team counts
       (`Fu.Positions.per_team/1` of the queue's formation).
    4. If infeasible, swap players across teams to satisfy the quotas while
       minimizing the aggregate-rank delta; repeat until feasible or no
       improving swap remains.

  Determinism is preserved throughout via stable sorts and player-id
  tie-breaks, so identical queue contents always yield identical teams.
  """

  alias Fu.Repo
  alias Fu.Queues
  alias Fu.Queues.{Queue, QueueMembership}
  alias Fu.Positions

  ## --- Public API (spec §2.7) ---

  @doc """
  Runs the spec §2.7 algorithm and PERSISTS `team` (`"A"`/`"B"`) on every
  queued membership (one `Repo.update/1` per membership inside a
  transaction). Idempotent: re-running on the same queue contents yields an
  identical assignment. Returns `{:ok, queue}` with the queue reloaded.
  """
  def assign_teams(queue_or_id) do
    queue = resolve(queue_or_id)
    {team_a, team_b} = split(queue)

    Repo.transaction(fn ->
      Enum.each(team_a, &persist_team(&1, "A"))
      Enum.each(team_b, &persist_team(&1, "B"))
    end)

    {:ok, Queues.get_queue!(queue.id)}
  end

  @doc """
  Current rosters for the queue: `%{"A" => [memberships], "B" => [...]}` for
  queued members only, each list sorted by player rank descending (spec §2.7).
  Memberships carry their preloaded `:player`.
  """
  def rosters(queue_or_id) do
    queue = resolve(queue_or_id)

    queue
    |> queued()
    |> Enum.group_by(& &1.team)
    |> Map.take(["A", "B"])
    |> Map.new(fn {team, ms} -> {team, Enum.sort_by(ms, &sort_key/1)} end)
    |> then(&Map.merge(%{"A" => [], "B" => []}, &1))
  end

  @doc "Sum of player ranks for a list of memberships (float, spec §2.7)."
  def team_rank(memberships) do
    memberships |> Enum.map(&(&1.player.rank * 1.0)) |> Enum.sum()
  end

  @doc """
  Absolute difference of the two teams' aggregate rank — the "derivable
  answer" used for dispute resolution (spec §2.7). Computed from the snake
  draft + swap pass (does not require a prior `assign_teams/1`).
  """
  def balance_delta(queue_or_id) do
    {team_a, team_b} = queue_or_id |> resolve() |> split()
    abs(team_rank(team_a) - team_rank(team_b))
  end

  ## --- Algorithm (spec §2.7 steps 1-4) ---

  # Produces the {team_a, team_b} membership lists for a queue's queued
  # players by running steps 1-4. Pure: no persistence.
  defp split(%Queue{} = queue) do
    members = queued(queue)
    per_team = Positions.per_team(queue.formation)

    # Step 1 — sort by rank desc, tie-break by player id asc (deterministic).
    sorted = Enum.sort_by(members, &sort_key/1)

    # Step 2 — snake draft: A, B, B, A, A, B, ... (alternating pair order
    # by round) so the rank gradient is shared evenly between the teams.
    {team_a, team_b} = snake_draft(sorted)

    # Steps 3 & 4 — feasibility check + minimal-delta swap pass.
    feasibility_swaps(team_a, team_b, per_team)
  end

  defp snake_draft(sorted) do
    sorted
    |> Enum.with_index()
    |> Enum.reduce({[], []}, fn {m, i}, {a, b} ->
      # Round = pair index; even rounds pick A then B, odd rounds B then A.
      if rem(div(i, 2) + rem(i, 2), 2) == 0 do
        case rem(i, 2) do
          0 -> {[m | a], b}
          1 -> {a, [m | b]}
        end
      else
        case rem(i, 2) do
          0 -> {a, [m | b]}
          1 -> {[m | a], b}
        end
      end
    end)
    |> then(fn {a, b} -> {Enum.reverse(a), Enum.reverse(b)} end)
  end

  # Step 3 + Step 4. Repeatedly: find a position where one team is short and
  # the other has a surplus, then apply the minimal aggregate-rank-delta
  # cross-team swap that fixes it. Stop when feasible or no improving swap.
  defp feasibility_swaps(team_a, team_b, per_team) do
    case deficit_position(team_a, team_b, per_team) do
      nil ->
        {team_a, team_b}

      {short_team, surplus_team, pos} ->
        {a, b} =
          if short_team == :a,
            do: best_swap(team_a, team_b, pos, :a),
            else: best_swap(team_a, team_b, pos, :b) |> flip()

        # Guard against non-progress (no improving swap) to stay terminating
        # and deterministic.
        if {a, b} == {team_a, team_b} or surplus_team == nil do
          {team_a, team_b}
        else
          feasibility_swaps(a, b, per_team)
        end
    end
  end

  # Returns {short_team, surplus_team, position} for the first position (in
  # canonical GK,DEF,MID,FWD order) where one team is below its per-team
  # quota and the other is at/above it, else nil.
  defp deficit_position(team_a, team_b, per_team) do
    ca = counts(team_a)
    cb = counts(team_b)

    Enum.find_value(Positions.positions(), fn pos ->
      need = Map.get(per_team, pos, 0)
      a = Map.get(ca, pos, 0)
      b = Map.get(cb, pos, 0)

      cond do
        a < need and b > need -> {:a, :b, pos}
        b < need and a > need -> {:b, :a, pos}
        true -> nil
      end
    end)
  end

  # Finds the cross-team swap that brings one `pos` player onto the short
  # team in exchange for a non-`pos` player, choosing the pairing that
  # minimizes the resulting aggregate-rank delta (tie-break: player ids asc
  # for determinism). `short` indicates which team needs the `pos` player.
  defp best_swap(team_a, team_b, pos, short) do
    {short_list, surplus_list} =
      if short == :a, do: {team_a, team_b}, else: {team_b, team_a}

    givers = Enum.filter(surplus_list, &(&1.declared_position == pos))
    takers = Enum.reject(short_list, &(&1.declared_position == pos))

    candidates =
      for g <- givers, t <- takers do
        new_short = [g | List.delete(short_list, t)]
        new_surplus = [t | List.delete(surplus_list, g)]
        delta = abs(team_rank(new_short) - team_rank(new_surplus))
        {delta, g.player.id, t.player.id, new_short, new_surplus}
      end

    case Enum.sort_by(candidates, fn {d, gi, ti, _, _} -> {d, gi, ti} end) do
      [{_d, _gi, _ti, new_short, new_surplus} | _] ->
        if short == :a,
          do: {new_short, new_surplus},
          else: {new_surplus, new_short}

      [] ->
        {team_a, team_b}
    end
  end

  defp flip({a, b}), do: {a, b}

  ## --- Helpers ---

  defp queued(%Queue{memberships: ms}),
    do: Enum.filter(ms, &(&1.status == "queued"))

  # Rank desc, player id asc (deterministic tie-break, spec §2.7 step 1).
  defp sort_key(m), do: {-m.player.rank, m.player.id}

  defp counts(memberships),
    do: Enum.frequencies_by(memberships, & &1.declared_position)

  defp persist_team(%QueueMembership{} = m, team) do
    m |> QueueMembership.changeset(%{team: team}) |> Repo.update!()
  end

  defp resolve(%Queue{} = q), do: q
  defp resolve(id), do: Queues.get_queue!(id)
end
