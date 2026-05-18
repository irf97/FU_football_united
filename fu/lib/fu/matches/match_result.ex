defmodule Fu.Matches.MatchResult do
  use Ecto.Schema
  import Ecto.Changeset

  schema "match_results" do
    field :score_a, :integer, default: 0
    field :score_b, :integer, default: 0
    field :completed_at, :utc_datetime
    field :votes_close_at, :utc_datetime
    field :started_at, :utc_datetime
    field :paused_at, :utc_datetime
    field :pause_seconds, :integer, default: 0

    belongs_to :queue, Fu.Queues.Queue
    timestamps(type: :utc_datetime)
  end

  def changeset(result, attrs) do
    result
    |> cast(attrs, [
      :queue_id,
      :score_a,
      :score_b,
      :completed_at,
      :votes_close_at,
      :started_at,
      :paused_at,
      :pause_seconds
    ])
    |> validate_required([:queue_id])
    |> validate_number(:score_a, greater_than_or_equal_to: 0)
    |> validate_number(:score_b, greater_than_or_equal_to: 0)
    |> unique_constraint(:queue_id)
  end
end
