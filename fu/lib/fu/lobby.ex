defmodule Fu.Lobby do
  @moduledoc """
  Game lobby mechanics (spec §2.5): the captain-claim state machine and
  position-swap persistence for a confirmed queue.

  ## Captain claim sequence (spec §2.5, §4 Q5)

  Once a queue confirms, a lobby opens and captaincy is claimed through a
  cascading set of time windows, measured from the lobby-open instant:

    * `:keeper`  0–60s   — only the team's goalkeeper may claim
    * `:ranked`  60–120s — only the team's highest-ranked player may claim
    * `:free`    120–240s — anyone on the team may claim
    * `:random`  ≥240s   — deterministic fallback assignment

  We do not persist the lobby-open instant, so `queue.updated_at` is used as
  the lobby-open anchor (a confirmed queue's last state write). This is an
  intentional, documented approximation for the MVP.
  """

  import Ecto.Query
  alias Fu.Repo
  alias Fu.Queues.QueueMembership

  @keeper_until 60
  @ranked_until 120
  @free_until 240

  @doc """
  Returns `{phase, seconds_remaining_in_phase}` where phase is one of
  `:keeper | :ranked | :free | :random`, based on seconds elapsed since the
  lobby opened (anchored on `queue.updated_at`).
  """
  def claim_phase(queue, now \\ DateTime.utc_now()) do
    elapsed = DateTime.diff(now, anchor(queue))

    cond do
      elapsed < @keeper_until -> {:keeper, @keeper_until - elapsed}
      elapsed < @ranked_until -> {:ranked, @ranked_until - elapsed}
      elapsed < @free_until -> {:free, @free_until - elapsed}
      true -> {:random, 0}
    end
  end

  defp anchor(%{updated_at: %DateTime{} = at}), do: at
  defp anchor(%{updated_at: %NaiveDateTime{} = at}), do: DateTime.from_naive!(at, "Etc/UTC")
  defp anchor(_), do: DateTime.utc_now()

  @doc """
  Whether `player` may claim captain for their team in the current `phase`.

  Eligibility is cumulative: a player eligible in an earlier window stays
  eligible in every later window while the team is still uncaptained.

    * `:keeper` — player is the GK on their team (declared_position "GK")
    * `:ranked` — player is the highest-ranked member of their team
    * `:free`/`:random` — anyone on the team
  """
  def eligible_to_claim?(queue, player, phase) do
    case team_membership(queue, player.id) do
      nil ->
        false

      m ->
        cond do
          captain_for_team?(queue, m.team) -> false
          phase == :keeper -> keeper?(m)
          phase == :ranked -> keeper?(m) or highest_ranked?(queue, m)
          true -> true
        end
    end
  end

  @doc """
  Sets `is_captain` on the player's membership iff their team is still
  uncaptained. Returns `{:ok, membership}` or `{:error, :taken}`.
  """
  def claim_captain(queue, player) do
    case team_membership(queue, player.id) do
      nil ->
        {:error, :taken}

      m ->
        if captain_for_team?(queue, m.team) do
          {:error, :taken}
        else
          m |> QueueMembership.changeset(%{is_captain: true}) |> Repo.update()
        end
    end
  end

  @doc """
  Random fallback (spec §2.5): for every team with no captain, deterministically
  promote the member with the lowest player id. Returns `:ok`.
  """
  def random_assign(queue) do
    queue.memberships
    |> queued()
    |> Enum.group_by(& &1.team)
    |> Enum.each(fn {team, members} ->
      unless team == nil or Enum.any?(members, & &1.is_captain) do
        members
        |> Enum.min_by(& &1.player_id)
        |> QueueMembership.changeset(%{is_captain: true})
        |> Repo.update()
      end
    end)

    :ok
  end

  @doc """
  Swaps the `declared_position` of two memberships in a transaction. Both must
  belong to the same team. Returns `{:ok, {a, b}}` or `{:error, reason}`.
  """
  def swap_positions(membership_a_id, membership_b_id) do
    Repo.transaction(fn ->
      a = Repo.get!(QueueMembership, membership_a_id)
      b = Repo.get!(QueueMembership, membership_b_id)

      if a.team != b.team or is_nil(a.team) do
        Repo.rollback(:different_team)
      end

      {:ok, a2} = a |> QueueMembership.changeset(%{declared_position: b.declared_position}) |> Repo.update()
      {:ok, b2} = b |> QueueMembership.changeset(%{declared_position: a.declared_position}) |> Repo.update()
      {a2, b2}
    end)
  end

  ## --- internals ---

  defp team_membership(queue, player_id) do
    queue.memberships
    |> queued()
    |> Enum.find(&(&1.player_id == player_id and not is_nil(&1.team)))
  end

  defp captain_for_team?(queue, team) do
    queue.memberships
    |> queued()
    |> Enum.any?(&(&1.team == team and &1.is_captain))
  end

  defp keeper?(%{declared_position: "GK"}), do: true
  defp keeper?(_), do: false

  defp highest_ranked?(queue, m) do
    top =
      queue.memberships
      |> queued()
      |> Enum.filter(&(&1.team == m.team))
      |> Enum.max_by(& &1.player.rank, fn -> nil end)

    top && top.id == m.id
  end

  defp queued(memberships), do: Enum.filter(memberships, &(&1.status == "queued"))

  @doc "Memberships ids that are captains, keyed by team (for quick UI lookup)."
  def captains(queue) do
    from(m in QueueMembership,
      where: m.queue_id == ^queue.id and m.is_captain == true,
      select: {m.team, m.id}
    )
    |> Repo.all()
    |> Map.new()
  end
end
