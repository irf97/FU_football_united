defmodule Fu.Voting do
  @moduledoc """
  Post-match peer voting — the **soft signals** of assessment (spec §2.8).

  After the whistle each player rates the *opposing* team on three
  categories: their MVP, their best defender, and a 0–10 score for their
  keeper. Voting is triggered ~5 minutes after the whistle and closes 24
  hours after match end (spec §2.8). The recognised keeper score is the
  **median** of opponent scores ("Median is the recognized score", §2.8).

  Skips are first-class (spec §4 Q3): a player may skip any category, and a
  player who skips *every* category (or casts none) is flagged so the rank
  engine can apply the −10 consecutive-skip penalty (§4 Q3, §2.9).

  Own-team votes are kept but tracked separately so the rank engine can
  weight them lower than opponent votes (spec §2.9).
  """

  import Ecto.Query
  alias Fu.Repo
  alias Fu.Balance
  alias Fu.Voting.Vote
  alias Fu.Matches.MatchResult

  @categories ~w(mvp defender keeper)

  @doc "The three voting categories (spec §2.8 soft signals)."
  def categories, do: @categories

  ## --- Casting (spec §2.8 soft signals, §4 Q3) ---

  @doc """
  Casts (or replaces) `voter`'s vote in `category` about `subject`. `opts`:

    * `:score` — keeper score 0..10 (spec §2.8)
    * `:own_team` — true if the subject is on the voter's own team
      (kept but weighted lower by the rank engine, spec §2.9)

  Upserts on `(queue_id, voter_id, category)` so a voter can change their
  mind before the window closes.
  """
  def cast(queue_id, voter_id, category, subject_id, opts \\ []) do
    upsert(%{
      queue_id: queue_id,
      voter_id: voter_id,
      category: category,
      subject_id: subject_id,
      score: opts[:score],
      own_team: Keyword.get(opts, :own_team, false),
      skipped: false
    })
  end

  @doc "Records that `voter` skipped `category` (spec §4 Q3 vote-skip)."
  def skip(queue_id, voter_id, category) do
    upsert(%{
      queue_id: queue_id,
      voter_id: voter_id,
      category: category,
      subject_id: nil,
      score: nil,
      own_team: false,
      skipped: true
    })
  end

  defp upsert(attrs) do
    %Vote{}
    |> Vote.changeset(attrs)
    |> Repo.insert(
      on_conflict: {:replace, [:subject_id, :score, :own_team, :skipped, :updated_at]},
      conflict_target: [:queue_id, :voter_id, :category]
    )
  end

  ## --- Voter status (spec §2.8, §4 Q3) ---

  @doc "Has `voter` recorded a vote (cast or skip) in every category?"
  def voted?(queue_id, voter_id) do
    pending_categories(queue_id, voter_id) == []
  end

  @doc "Categories `voter` has not yet recorded for this match."
  def pending_categories(queue_id, voter_id) do
    done =
      from(v in Vote,
        where: v.queue_id == ^queue_id and v.voter_id == ^voter_id,
        select: v.category
      )
      |> Repo.all()
      |> MapSet.new()

    Enum.reject(@categories, &MapSet.member?(done, &1))
  end

  @doc """
  Is the voting window still open? True iff a `MatchResult` exists with
  `votes_close_at` in the future (spec §2.8: opens 5 min after the whistle,
  closes 24 hours after match end).
  """
  def voting_open?(queue_id) do
    case Repo.get_by(MatchResult, queue_id: queue_id) do
      %MatchResult{votes_close_at: %DateTime{} = closes} ->
        DateTime.compare(closes, DateTime.utc_now()) == :gt

      _ ->
        false
    end
  end

  @doc """
  True if `player_id` skipped ALL categories (or cast none) for this match —
  the consecutive-skip signal the rank engine penalises by −10 (spec §4 Q3,
  §2.9).
  """
  def skip_streak_delta(queue_id, player_id) do
    votes =
      from(v in Vote,
        where: v.queue_id == ^queue_id and v.voter_id == ^player_id
      )
      |> Repo.all()

    votes == [] or Enum.all?(votes, & &1.skipped)
  end

  @doc "Canonical alias for `skip_streak_delta/2` (spec §2.9 consecutive-skip detector)."
  def fully_skipped?(queue_id, player_id), do: skip_streak_delta(queue_id, player_id)

  ## --- Tally (spec §2.8 "Median is the recognized score", §2.9 own-team weighting) ---

  @doc """
  Aggregates the soft signals for the rank engine (spec §2.8, §2.9):

      %{
        mvp:      %{winner_id: id | nil, counts: %{pid => n}, own_counts: %{pid => n}},
        defender: %{winner_id: id | nil, counts: %{pid => n}, own_counts: %{pid => n}},
        keeper:   %{"A" => median | nil, "B" => median | nil,
                    keeper_player: %{pid => median}}
      }

  MVP/defender winner = the subject with the most NON-skipped *opponent*
  (`own_team == false`) votes; ties break to the lowest player id for
  determinism (spec §2.7/§2.9 derivable answers). Own-team votes are tallied
  separately under `:own_counts` so the rank engine can weight them lower
  (spec §2.9).

  Keeper: each team's recognised score is the **median** of all non-skipped
  opponent keeper scores about that team's keeper (spec §2.8). The keeper is
  the membership declared `"GK"` on that team.
  """
  def tally(queue_id) do
    votes =
      from(v in Vote, where: v.queue_id == ^queue_id and v.skipped == false)
      |> Repo.all()

    %{
      mvp: count_category(votes, "mvp"),
      defender: count_category(votes, "defender"),
      keeper: keeper_tally(queue_id, votes)
    }
  end

  # Opponent (own_team == false) counts decide the winner; own-team counts are
  # exposed separately for the rank engine's lower weighting (spec §2.9).
  defp count_category(votes, category) do
    cat = Enum.filter(votes, &(&1.category == category and &1.subject_id))
    {opp, own} = Enum.split_with(cat, &(&1.own_team == false))

    counts = Enum.frequencies_by(opp, & &1.subject_id)
    own_counts = Enum.frequencies_by(own, & &1.subject_id)

    %{winner_id: best(counts), counts: counts, own_counts: own_counts}
  end

  # Most votes wins; tie-break by lowest player id (deterministic, spec §2.9).
  defp best(counts) when map_size(counts) == 0, do: nil

  defp best(counts) do
    counts
    |> Enum.min_by(fn {pid, n} -> {-n, pid} end)
    |> elem(0)
  end

  defp keeper_tally(queue_id, votes) do
    rosters = Balance.rosters(queue_id)
    keepers = Map.new(["A", "B"], fn team -> {team, keeper_id(rosters, team)} end)

    scores =
      votes
      |> Enum.filter(&(&1.category == "keeper" and &1.own_team == false and &1.score))
      |> Enum.group_by(& &1.subject_id, & &1.score)

    by_player =
      keepers
      |> Map.values()
      |> Enum.reject(&is_nil/1)
      |> Map.new(fn pid -> {pid, median(Map.get(scores, pid, []))} end)

    %{
      "A" => keepers["A"] && by_player[keepers["A"]],
      "B" => keepers["B"] && by_player[keepers["B"]],
      keeper_player: by_player
    }
  end

  defp keeper_id(rosters, team) do
    rosters
    |> Map.get(team, [])
    |> Enum.find(&(&1.declared_position == "GK"))
    |> case do
      nil -> nil
      m -> m.player.id
    end
  end

  @doc """
  Median of a list of numbers (spec §2.8 "Median is the recognized score"):
  sorted middle value, average of the two middles when even, `nil` if empty.
  """
  def median([]), do: nil

  def median(scores) do
    sorted = Enum.sort(scores)
    n = length(sorted)
    mid = div(n, 2)

    if rem(n, 2) == 1 do
      Enum.at(sorted, mid)
    else
      (Enum.at(sorted, mid - 1) + Enum.at(sorted, mid)) / 2
    end
  end
end
