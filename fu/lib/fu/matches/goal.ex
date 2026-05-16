defmodule Fu.Matches.Goal do
  use Ecto.Schema
  import Ecto.Changeset

  schema "goals" do
    field :team, :string

    belongs_to :queue, Fu.Queues.Queue
    belongs_to :scorer, Fu.Accounts.Player
    belongs_to :assist, Fu.Accounts.Player
    timestamps(type: :utc_datetime)
  end

  def changeset(goal, attrs) do
    goal
    |> cast(attrs, [:queue_id, :scorer_id, :assist_id, :team])
    |> validate_required([:queue_id])
    |> validate_inclusion(:team, ~w(A B))
  end
end
