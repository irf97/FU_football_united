defmodule Fu.Ranking do
  @moduledoc """
  The ranking engine (spec §2.9), rank decay, no-show tracking + suspension,
  and disputes (spec §2.10).

  Spec §2.9 demands the engine be **deterministic and inspectable**: every
  rank change is written as an append-only `Fu.Ranking.RankEvent` whose
  `breakdown` map enumerates each weighted component, so the answer to "why
  did my rank move?" is always derivable from the ledger alone. Events are
  never mutated — corrections are amendments via `Fu.Ranking.Dispute`
  (spec §2.10). Ranks are clamped to `[30.0, 100.0]`; new players start 50.

  ## Weight table (spec §2.9)

    * Outcome: win `+1.5`, draw `+0.3`, loss `-0.8`
    * Goal `+0.6` each; assist `+0.4` each
    * Opponent MVP vote won `+2.0`; opponent best-defender `+1.6`
    * Opponent keeper score: `(median - 5) * 0.3` clamped to `[-1.5, +1.5]`
      (the team's GK only)
    * Own-team MVP or defender vote won: `+0.6` (weighted lower than the
      opponent equivalents — spec §2.9)
    * Inactivity: `-0.2` per missed weekly window (computed `0` in v1 — no
      availability-vs-played reconciliation data yet; documented gap)
    * Skip-vote penalty: `-10` one-time when the player fully skipped voting
      twice in a row (spec §4 Q3)
    * No-show: first `-15`; second within 60 days `-15` plus a 14-day
      suspension (spec §2.9, §4 Q1)
  """

  import Ecto.Query
  alias Fu.Repo
  alias Fu.Ranking.{RankEvent, NoShow, Dispute}
  alias Fu.Accounts.Player
  alias Fu.{Queues, Matches, Voting}

  # --- Weight table (spec §2.9) — module attributes, one source of truth ---

  @w_win 1.5
  @w_draw 0.3
  @w_loss -0.8
  @w_goal 0.6
  @w_assist 0.4
  @w_opp_mvp 2.0
  @w_opp_defender 1.6
  @w_own_vote 0.6
  @keeper_scale 0.3
  @keeper_clamp 1.5
  @skip_penalty -10.0
  @no_show_penalty -15.0

  @no_show_window_days 60
  @suspend_days 14
  @decay_idle_days 90
  @decay_per_week 0.3
  @decay_target 50.0

  @rank_min 30.0
  @rank_max 100.0

  ## --- Match finalization (spec §2.9 — the centerpiece) ---

  @doc """
  Finalizes ranking for `queue_id`: for every queued participant computes the
  delta from the spec §2.9 weight table, writes ONE append-only `RankEvent`
  (kind `"match"`) carrying the full component `breakdown`, `rank_before` and
  `rank_after`, and updates the player's clamped rank.

  Deterministic and **idempotent**: the `(player_id, queue_id, "match")`
  unique index means re-running returns the already-written events without
  double-applying. The whole pass runs in one `Repo.transaction/1`.

  Returns `{:ok, [%RankEvent{}]}`.
  """
  def finalize_match(queue_id) do
    queue = Queues.get_queue!(queue_id)

    existing =
      from(e in RankEvent, where: e.queue_id == ^queue_id and e.kind == "match")
      |> Repo.all()

    if existing != [] do
      {:ok, existing}
    else
      winner = Matches.winner(queue_id)
      tally = Voting.tally(queue_id)

      participants =
        queue.memberships
        |> Enum.filter(&(&1.status == "queued"))

      Repo.transaction(fn ->
        Enum.map(participants, fn m ->
          write_match_event(queue, m, winner, tally)
        end)
      end)
    end
  end

  # Computes the breakdown for one participant, persists the RankEvent and the
  # clamped player rank. Returns the inserted %RankEvent{}.
  defp write_match_event(queue, membership, winner, tally) do
    player = membership.player
    team = membership.team
    breakdown = breakdown_for(queue, membership, winner, tally)

    delta = breakdown |> Map.values() |> Enum.sum()
    rank_before = player.rank * 1.0
    rank_after = clamp(rank_before + delta)

    {:ok, event} =
      %RankEvent{}
      |> RankEvent.changeset(%{
        player_id: player.id,
        queue_id: queue.id,
        kind: "match",
        delta: delta,
        rank_before: rank_before,
        rank_after: rank_after,
        breakdown: breakdown
      })
      |> Repo.insert()

    set_rank!(player, rank_after)
    apply_skip_streak(player, queue.id)
    _ = team
    event
  end

  # The deterministic, inspectable component map (spec §2.9). Only non-trivial
  # rated queues earn outcome/vote points; unrated queues still log a zeroed
  # breakdown so the ledger is complete.
  defp breakdown_for(queue, membership, winner, tally) do
    player = membership.player
    team = membership.team

    if queue.rated do
      %{
        "outcome" => outcome_points(team, winner),
        "goals" => Matches.goal_count(queue.id, player.id) * @w_goal,
        "assists" => Matches.assist_count(queue.id, player.id) * @w_assist,
        "opponent_mvp" => opponent_vote(tally, :mvp, player.id, @w_opp_mvp),
        "opponent_defender" => opponent_vote(tally, :defender, player.id, @w_opp_defender),
        "own_vote" => own_vote(tally, player.id),
        "keeper_score" => keeper_points(tally, membership),
        "inactivity" => 0.0,
        "skip_penalty" => skip_points(player, queue.id)
      }
    else
      %{
        "outcome" => 0.0,
        "goals" => 0.0,
        "assists" => 0.0,
        "opponent_mvp" => 0.0,
        "opponent_defender" => 0.0,
        "own_vote" => 0.0,
        "keeper_score" => 0.0,
        "inactivity" => 0.0,
        "skip_penalty" => skip_points(player, queue.id)
      }
    end
  end

  # Win/draw/loss for the player's team given Matches.winner/1 (spec §2.9).
  defp outcome_points(_team, :draw), do: @w_draw
  defp outcome_points(team, team), do: @w_win
  defp outcome_points(team, winner) when team in ["A", "B"] and winner in ["A", "B"], do: @w_loss
  defp outcome_points(_team, _winner), do: 0.0

  # Opponent-cast MVP / best-defender vote win (spec §2.9 — full weight).
  defp opponent_vote(tally, kind, player_id, weight) do
    if tally[kind][:winner_id] == player_id, do: weight, else: 0.0
  end

  # Own-team MVP or defender win is weighted lower than the opponent value
  # (spec §2.9): a flat `+0.6`, not stacked per category.
  defp own_vote(tally, player_id) do
    own_mvp = own_count(tally, :mvp, player_id)
    own_def = own_count(tally, :defender, player_id)
    if own_mvp > 0 or own_def > 0, do: @w_own_vote, else: 0.0
  end

  defp own_count(tally, kind, player_id) do
    tally
    |> get_in([kind, :own_counts])
    |> case do
      nil -> 0
      counts -> Map.get(counts, player_id, 0)
    end
  end

  # Opponent keeper score: only the team's GK earns it. The keeper's median
  # vote is mapped `(median - 5) * 0.3` and clamped to `[-1.5, +1.5]`.
  defp keeper_points(tally, %{declared_position: "GK", player: player}) do
    median = get_in(tally, [:keeper, :keeper_player, player.id])

    case median do
      nil -> 0.0
      m -> ((m - 5) * @keeper_scale) |> max(-@keeper_clamp) |> min(@keeper_clamp)
    end
  end

  defp keeper_points(_tally, _membership), do: 0.0

  # Skip-vote penalty (spec §4 Q3): -10 one-time only when this is the player's
  # SECOND consecutive fully-skipped match (skip_streak reaches 2).
  defp skip_points(player, queue_id) do
    if fully_skipped?(queue_id, player.id) and player.skip_streak >= 1,
      do: @skip_penalty,
      else: 0.0
  end

  # Maintain player.skip_streak: increment when this match was fully skipped,
  # reset to 0 otherwise (spec §4 Q3). Re-reads the player to avoid stale rank.
  defp apply_skip_streak(player, queue_id) do
    streak =
      if fully_skipped?(queue_id, player.id), do: player.skip_streak + 1, else: 0

    Repo.get!(Player, player.id)
    |> Ecto.Changeset.change(skip_streak: streak)
    |> Repo.update!()
  end

  # Voting.fully_skipped?/2 is the consecutive-skip detector; fall back to
  # skip_streak_delta/2 if the name differs (per spec note).
  defp fully_skipped?(queue_id, player_id) do
    cond do
      function_exported?(Voting, :fully_skipped?, 2) ->
        Voting.fully_skipped?(queue_id, player_id)

      function_exported?(Voting, :skip_streak_delta, 2) ->
        Voting.skip_streak_delta(queue_id, player_id)

      true ->
        false
    end
  end

  ## --- No-shows + suspension (spec §2.9, §4 Q1) ---

  @doc """
  Records a no-show: inserts a `NoShow`, then writes a `RankEvent`
  (kind `"no_show"`, delta `-15`). The 2nd no-show inside a rolling 60-day
  window also suspends the player for 14 days; the 3rd flags a
  `"operator_review"` dispute (spec §2.9, §4 Q1). Returns `{:ok, event}`.
  """
  def record_no_show(player_id, queue_id) do
    player = Repo.get!(Player, player_id)
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    since = DateTime.add(now, -@no_show_window_days * 86_400, :second)

    Repo.transaction(fn ->
      %NoShow{}
      |> NoShow.changeset(%{player_id: player_id, queue_id: queue_id, occurred_at: now})
      |> Repo.insert!()

      prior =
        from(n in NoShow,
          where: n.player_id == ^player_id and n.occurred_at >= ^since
        )
        |> Repo.aggregate(:count, :id)

      rank_before = player.rank * 1.0
      rank_after = clamp(rank_before + @no_show_penalty)
      suspended? = prior >= 2

      breakdown = %{
        "no_show" => @no_show_penalty,
        "count_60d" => prior,
        "suspended" => suspended?
      }

      {:ok, event} =
        %RankEvent{}
        |> RankEvent.changeset(%{
          player_id: player_id,
          queue_id: queue_id,
          kind: "no_show",
          delta: @no_show_penalty,
          rank_before: rank_before,
          rank_after: rank_after,
          breakdown: breakdown
        })
        |> Repo.insert()

      changes = [rank: rank_after]

      changes =
        if suspended? do
          until = DateTime.add(now, @suspend_days * 86_400, :second)
          Keyword.put(changes, :suspended_until, until)
        else
          changes
        end

      Repo.get!(Player, player_id)
      |> Ecto.Changeset.change(changes)
      |> Repo.update!()

      if prior >= 3 do
        %Dispute{}
        |> Dispute.changeset(%{
          player_id: player_id,
          queue_id: queue_id,
          rank_event_id: event.id,
          kind: "operator_review",
          note: "#{prior} no-shows in #{@no_show_window_days} days",
          status: "open"
        })
        |> Repo.insert!()
      end

      event
    end)
  end

  ## --- Decay (spec §2.9 — drift idle players toward 50) ---

  @doc """
  Drifts the rank of players with no `"match"` `RankEvent` in the last 90 days
  toward `50.0` by `0.3` per idle week, capped so the drift never crosses 50
  (spec §2.9). Suspended players are exempt — "no double penalty" (spec §2.9).
  Writes one `"decay"` RankEvent per affected player per run. Returns the
  count of players decayed.
  """
  def apply_decay do
    now = DateTime.utc_now()
    idle_cutoff = DateTime.add(now, -@decay_idle_days * 86_400, :second)

    active_player_ids =
      from(e in RankEvent,
        where: e.kind == "match" and e.inserted_at >= ^idle_cutoff,
        select: e.player_id,
        distinct: true
      )
      |> Repo.all()
      |> MapSet.new()

    candidates =
      from(p in Player, where: p.rank != ^@decay_target)
      |> Repo.all()
      |> Enum.reject(&MapSet.member?(active_player_ids, &1.id))
      |> Enum.reject(&suspended?/1)

    events =
      Enum.flat_map(candidates, fn player ->
        case decay_player(player, now) do
          nil -> []
          event -> [event]
        end
      end)

    length(events)
  end

  defp decay_player(player, now) do
    last = last_match_at(player.id) || player.inserted_at
    weeks = DateTime.diff(now, last, :second) / (7 * 86_400)

    if weeks < @decay_idle_days / 7 do
      nil
    else
      rank_before = player.rank * 1.0
      drift = weeks * @decay_per_week

      rank_after =
        if rank_before > @decay_target,
          do: max(@decay_target, rank_before - drift),
          else: min(@decay_target, rank_before + drift)

      rank_after = clamp(rank_after)

      {:ok, event} =
        %RankEvent{}
        |> RankEvent.changeset(%{
          player_id: player.id,
          queue_id: nil,
          kind: "decay",
          delta: rank_after - rank_before,
          rank_before: rank_before,
          rank_after: rank_after,
          breakdown: %{
            "idle_weeks" => Float.round(weeks, 2),
            "per_week" => @decay_per_week,
            "target" => @decay_target
          }
        })
        |> Repo.insert()

      set_rank!(player, rank_after)
      event
    end
  end

  defp last_match_at(player_id) do
    from(e in RankEvent,
      where: e.player_id == ^player_id and e.kind == "match",
      order_by: [desc: e.inserted_at],
      limit: 1,
      select: e.inserted_at
    )
    |> Repo.one()
  end

  ## --- Read API (spec §2.9 — inspectable) ---

  @doc "All rank events for a player, newest first (spec §2.9)."
  def history(player_id) do
    from(e in RankEvent,
      where: e.player_id == ^player_id,
      order_by: [desc: e.inserted_at, desc: e.id]
    )
    |> Repo.all()
  end

  @doc "The match `RankEvent` for `(player_id, queue_id)` or nil (spec §2.9)."
  def event_for(player_id, queue_id) do
    Repo.get_by(RankEvent, player_id: player_id, queue_id: queue_id, kind: "match")
  end

  @doc "The player's current clamped rank (spec §2.9)."
  def current_rank(player_id) do
    Repo.get!(Player, player_id).rank
  end

  ## --- Disputes (spec §2.10 — amendment, never mutation) ---

  @doc """
  Files an append-only dispute, status `"open"` (spec §2.10). `attrs` may
  carry `:kind`, `:note`, `:rank_event_id`, `:queue_id`.
  """
  def file_dispute(player_id, attrs) do
    attrs =
      attrs
      |> Map.new(fn {k, v} -> {to_string(k), v} end)
      |> Map.put("player_id", player_id)
      |> Map.put_new("status", "open")

    %Dispute{} |> Dispute.changeset(attrs) |> Repo.insert()
  end

  @doc "Disputes filed by a player, newest first (spec §2.10)."
  def disputes_for(player_id) do
    from(d in Dispute,
      where: d.player_id == ^player_id,
      order_by: [desc: d.inserted_at, desc: d.id]
    )
    |> Repo.all()
  end

  @doc """
  Resolves a dispute by *amendment* (spec §2.10): sets status `"resolved"`
  and records `resolution`. The disputed `RankEvent` is never mutated — the
  ledger stays inspectable (spec §2.9).
  """
  def resolve_dispute(id, resolution) do
    case Repo.get(Dispute, id) do
      nil ->
        {:error, :not_found}

      dispute ->
        dispute
        |> Dispute.changeset(%{status: "resolved", resolution: resolution})
        |> Repo.update()
    end
  end

  ## --- Helpers ---

  @doc "Clamps a rank into the spec §2.9 band `[30.0, 100.0]`."
  def clamp(x), do: min(@rank_max, max(@rank_min, x))

  defp set_rank!(%Player{} = player, rank) do
    Repo.get!(Player, player.id)
    |> Ecto.Changeset.change(rank: rank)
    |> Repo.update!()
  end

  defp suspended?(%Player{suspended_until: nil}), do: false

  defp suspended?(%Player{suspended_until: until}),
    do: DateTime.compare(until, DateTime.utc_now()) == :gt
end
