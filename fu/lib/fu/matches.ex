defmodule Fu.Matches do
  @moduledoc """
  Match outcome capture — the **hard signals** of post-match assessment
  (spec §2.8). Captures the final score, individual goals/assists, and the
  match completion that opens the 24-hour peer-voting window.

  Hard signals (score, goals, assists, win/loss) are objective and recorded
  here; soft signals (peer recognition) live in `Fu.Voting` (spec §2.8).
  """

  import Ecto.Query
  alias Fu.Repo
  alias Fu.Queues
  alias Fu.Queues.{Queue, QueueMembership}
  alias Fu.Matches.{MatchResult, Goal}

  @vote_window_hours 24

  ## --- Result lifecycle (spec §2.8 hard signals) ---

  @doc "Fetches the queue's `MatchResult`, creating an empty one if absent (idempotent)."
  def get_or_create_result(queue_id) do
    case Repo.get_by(MatchResult, queue_id: queue_id) do
      nil ->
        %MatchResult{}
        |> MatchResult.changeset(%{queue_id: queue_id})
        |> Repo.insert!()

      result ->
        result
    end
  end

  @doc "Records the final score for the match (spec §2.8 hard signals)."
  def record_score(queue_id, score_a, score_b) do
    get_or_create_result(queue_id)
    |> MatchResult.changeset(%{score_a: score_a, score_b: score_b})
    |> Repo.update()
  end

  @doc """
  Inserts a goal. The scoring team is derived from the scorer's membership in
  this queue (spec §2.8); if the scorer is unknown the team is left `nil`.
  """
  def record_goal(queue_id, scorer_id, assist_id \\ nil) do
    %Goal{}
    |> Goal.changeset(%{
      queue_id: queue_id,
      scorer_id: scorer_id,
      assist_id: assist_id,
      team: team_of(queue_id, scorer_id)
    })
    |> Repo.insert()
  end

  @doc """
  Completes the match: stamps `completed_at`, opens the voting window until
  24 hours after the match end (spec §2.8 "Closes 24 hours after match end"),
  and moves the queue to `completed`. Idempotent.
  """
  def complete_match(queue_id) do
    result = get_or_create_result(queue_id)

    if result.completed_at do
      result
    else
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      closes = DateTime.add(now, @vote_window_hours * 3600, :second)

      {:ok, result} =
        result
        |> MatchResult.changeset(%{completed_at: now, votes_close_at: closes})
        |> Repo.update()

      queue = Queues.get_queue!(queue_id)

      queue
      |> Queue.changeset(%{state: "completed"})
      |> Repo.update!()

      result
    end
  end

  ## --- Reads (spec §2.8 hard signals feeding the rank engine §2.9) ---

  @doc "The queue's `MatchResult`, or `nil`."
  def result(queue_id), do: Repo.get_by(MatchResult, queue_id: queue_id)

  @doc "All goals for the queue, oldest first."
  def goals_for(queue_id) do
    from(g in Goal, where: g.queue_id == ^queue_id, order_by: [asc: g.id])
    |> Repo.all()
  end

  @doc "Number of goals `player_id` scored in this match."
  def goal_count(queue_id, player_id) do
    from(g in Goal, where: g.queue_id == ^queue_id and g.scorer_id == ^player_id)
    |> Repo.aggregate(:count, :id)
  end

  @doc "Number of assists `player_id` provided in this match."
  def assist_count(queue_id, player_id) do
    from(g in Goal, where: g.queue_id == ^queue_id and g.assist_id == ^player_id)
    |> Repo.aggregate(:count, :id)
  end

  @doc "Winning team A or B, or :draw — spec §2.8 hard signals."
  def winner(queue_id) do
    case result(queue_id) do
      nil ->
        :draw

      %MatchResult{score_a: a, score_b: b} ->
        cond do
          a > b -> "A"
          b > a -> "B"
          true -> :draw
        end
    end
  end

  @doc """
  The in-app match-completion trigger (AUDIT integration break #1).
  Records the final score, completes the match (opens voting, moves the
  queue to "completed"), and finalizes ranks — as one operation.

  Idempotent: once completed, a re-submit is a no-op returning the
  existing result (ranks never move twice). Refuses a queue that has not
  been confirmed.
  """
  def submit_result(queue_id, score_a, score_b) do
    queue = Queues.get_queue!(queue_id)
    existing = result(queue_id)

    cond do
      existing && existing.completed_at ->
        {:ok, existing}

      queue.state != "confirmed" ->
        {:error, :not_confirmed}

      true ->
        record_score(queue_id, score_a, score_b)
        complete_match(queue_id)
        {:ok, _events} = Fu.Ranking.finalize_match(queue_id)
        {:ok, result(queue_id)}
    end
  end

  ## --- In-play clock + captain pause (spec §2.7, AUDIT #12) ---

  @doc """
  Kicks off the match clock for a confirmed queue (idempotent). Returns
  `{:error, :not_confirmed}` if the queue hasn't been confirmed, otherwise
  `{:ok, result}` with `started_at` stamped (never re-stamped).
  """
  def kickoff(queue_id) do
    queue = Queues.get_queue!(queue_id)
    result = get_or_create_result(queue_id)

    cond do
      result.started_at -> {:ok, result}
      queue.state != "confirmed" -> {:error, :not_confirmed}
      true -> update_result(result, %{started_at: now()})
    end
  end

  @doc "Captain pauses the running clock (idempotent while paused)."
  def pause(queue_id) do
    result = get_or_create_result(queue_id)

    if result.started_at && is_nil(result.paused_at) && is_nil(result.completed_at) do
      update_result(result, %{paused_at: now()})
    else
      {:ok, result}
    end
  end

  @doc "Captain resumes a paused clock, banking the paused span (idempotent)."
  def resume(queue_id) do
    result = get_or_create_result(queue_id)

    case result.paused_at do
      nil ->
        {:ok, result}

      paused_at ->
        banked = result.pause_seconds + max(DateTime.diff(now(), paused_at), 0)
        update_result(result, %{paused_at: nil, pause_seconds: banked})
    end
  end

  @doc "Is the match clock currently paused?"
  def paused?(%MatchResult{paused_at: nil}), do: false
  def paused?(%MatchResult{}), do: true

  @doc """
  Seconds of *played* time at `now`: wall time since kickoff minus the banked
  paused span minus any in-progress pause. `0` before kickoff; never negative.
  """
  def elapsed_seconds(%MatchResult{started_at: nil}, _now), do: 0

  def elapsed_seconds(%MatchResult{} = r, %DateTime{} = now) do
    in_pause = if r.paused_at, do: max(DateTime.diff(now, r.paused_at), 0), else: 0
    max(DateTime.diff(now, r.started_at) - r.pause_seconds - in_pause, 0)
  end

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)

  defp update_result(%MatchResult{} = result, attrs) do
    result |> MatchResult.changeset(attrs) |> Repo.update()
  end

  ## --- Helpers ---

  # Team ("A"/"B") the player is on for this queue, or nil if unknown.
  defp team_of(_queue_id, nil), do: nil

  defp team_of(queue_id, player_id) do
    from(m in QueueMembership,
      where: m.queue_id == ^queue_id and m.player_id == ^player_id,
      select: m.team
    )
    |> Repo.one()
  end
end
