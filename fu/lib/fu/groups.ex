defmodule Fu.Groups do
  @moduledoc """
  Friend groups & group queuing (spec §2.12): players band together (up to 8),
  the leader picks a queue, and all N members join atomically — a group fits a
  queue only if every member's position can be satisfied as a single unit.
  """

  import Ecto.Query
  alias Fu.Repo
  alias Fu.Groups.{Group, GroupMembership}
  alias Fu.{Positions, Queues}

  @max_members 8

  ## --- Creation (spec §2.12) ---

  @doc """
  Creates a group with `leader` as its first member. Generates an 8-char
  url-safe `invite_code`. Group + leader membership are inserted together in a
  transaction (all-or-nothing). Returns `{:ok, group}`.
  """
  def create_group(leader) do
    Repo.transaction(fn ->
      group =
        %Group{}
        |> Group.changeset(%{leader_id: leader.id, invite_code: gen_invite_code()})
        |> Repo.insert!()

      %GroupMembership{}
      |> GroupMembership.changeset(%{group_id: group.id, player_id: leader.id})
      |> Repo.insert!()

      group
    end)
  end

  defp gen_invite_code do
    :crypto.strong_rand_bytes(6) |> Base.url_encode64(padding: false)
  end

  ## --- Membership (spec §2.12) ---

  @doc """
  Adds `player` to `group`. Rejected with `{:error, :group_full}` once the
  group has #{@max_members} members, or `{:error, :already_member}` on a
  duplicate.
  """
  def add_member(group, player) do
    cond do
      member_count(group) >= @max_members ->
        {:error, :group_full}

      Repo.exists?(
        from m in GroupMembership,
          where: m.group_id == ^group.id and m.player_id == ^player.id
      ) ->
        {:error, :already_member}

      true ->
        %GroupMembership{}
        |> GroupMembership.changeset(%{group_id: group.id, player_id: player.id})
        |> Repo.insert()
    end
  end

  @doc "Players in the group, ordered by join time (spec §2.12)."
  def members(group) do
    from(m in GroupMembership,
      where: m.group_id == ^group.id,
      order_by: [asc: m.inserted_at, asc: m.id],
      preload: [:player]
    )
    |> Repo.all()
    |> Enum.map(& &1.player)
  end

  @doc "Number of members in the group."
  def member_count(group) do
    Repo.aggregate(
      from(m in GroupMembership, where: m.group_id == ^group.id),
      :count,
      :id
    )
  end

  @doc "Fetches a group by `invite_code` (memberships → player preloaded), or nil."
  def get_by_invite(code) do
    Group
    |> Repo.get_by(invite_code: code)
    |> case do
      nil -> nil
      group -> Repo.preload(group, memberships: :player)
    end
  end

  @doc "The player's most recent group (as leader or member), or nil."
  def current_group(player) do
    from(g in Group,
      join: m in GroupMembership,
      on: m.group_id == g.id,
      where: m.player_id == ^player.id,
      order_by: [desc: g.id],
      limit: 1
    )
    |> Repo.one()
    |> case do
      nil -> nil
      group -> Repo.preload(group, memberships: :player)
    end
  end

  ## --- Group fit & queuing (spec §2.12) ---

  @doc """
  True only if EVERY member of the group can be slotted into `queue` as a unit.

  This is the load-bearing rule of spec §2.12: members compete for the same
  scarce slots, so a group fits only when the *whole* group can be placed.
  """
  def fits_queue?(group, queue) do
    case simulate(group, queue) do
      {:ok, _placements} -> true
      :error -> false
    end
  end

  @doc """
  Queues the whole group into `queue` atomically (spec §2.12). If the group
  fits, builds the `[%{player: p, position: pos}]` list from the *same*
  simulation that decided the fit and delegates the all-or-nothing insert to
  `Fu.Queues.join_group/2`, then records `group.queue_id`.

  Returns `{:ok, memberships}` | `{:error, :group_does_not_fit}` | passthrough.
  """
  def queue_as_group(group, queue) do
    case simulate(group, queue) do
      :error ->
        {:error, :group_does_not_fit}

      {:ok, placements} ->
        members = Enum.map(placements, fn {player, pos} -> %{player: player, position: pos} end)

        with {:ok, memberships} <- Queues.join_group(queue, members) do
          {:ok, _group} =
            group
            |> Group.changeset(%{queue_id: queue.id})
            |> Repo.update()

          {:ok, memberships}
        end
    end
  end

  # Folds over the group's members (in join order) and tries to place each one,
  # tracking the remaining capacity of every position as we go.
  #
  # Starting capacity per position = queue.slots capacity minus the players
  # already `queued` there (counted by `declared_position`). Each member takes
  # the first of [primary, secondary, (fill_mode) any] that still has remaining
  # capacity; we then decrement that position so later members in the *same*
  # group can't double-book a slot we already promised. If any member cannot be
  # placed, the whole simulation fails (all-or-nothing — spec §2.12).
  #
  # Returns `{:ok, [{player, position}, ...]}` (join order) or `:error`.
  defp simulate(group, queue) do
    queue = Queues.get_queue!(queue.id)

    queued_counts =
      queue.memberships
      |> Enum.filter(&(&1.status == "queued"))
      |> Enum.frequencies_by(& &1.declared_position)

    remaining =
      Map.new(queue.slots, fn s ->
        {s.position, max(s.capacity - Map.get(queued_counts, s.position, 0), 0)}
      end)

    members(group)
    |> Enum.reduce_while({remaining, []}, fn player, {remaining, placed} ->
      case place(player, remaining) do
        {:ok, pos} ->
          {:cont, {Map.update!(remaining, pos, &(&1 - 1)), [{player, pos} | placed]}}

        :error ->
          {:halt, :error}
      end
    end)
    |> case do
      :error -> :error
      {_remaining, placed} -> {:ok, Enum.reverse(placed)}
    end
  end

  # The position this player would take given the remaining capacity map:
  # primary → secondary → (fill mode) any open, mirroring
  # `Fu.Queues.pick_position/2` semantics but against the live simulation.
  defp place(player, remaining) do
    prefs =
      [player.primary_position, player.secondary_position]
      |> Enum.reject(&(&1 in [nil, ""]))

    prefs = if player.fill_mode, do: prefs ++ Positions.positions(), else: prefs

    case Enum.find(Enum.uniq(prefs), fn pos -> Map.get(remaining, pos, 0) > 0 end) do
      nil -> :error
      pos -> {:ok, pos}
    end
  end

  ## --- UI expectation table (spec §2.12) ---

  @doc """
  The size-based expectation copy shown before queuing (spec §2.12 UI table).
  """
  def expected_split(n) when n in 2..3, do: "You'll probably play together"
  def expected_split(n) when n in 4..5, do: "Auto-balance may split your group"
  def expected_split(n) when n in 6..8, do: "Group will likely play across both teams"
  def expected_split(_n), do: "Queue solo or invite friends"
end
