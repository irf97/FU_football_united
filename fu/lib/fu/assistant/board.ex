defmodule Fu.Assistant.Board do
  use Ecto.Schema
  import Ecto.Changeset

  schema "assistant_boards" do
    belongs_to :session, Fu.Hobbies.Session
    belongs_to :referee, Fu.Accounts.Player
    field :team_a, :string, default: "Side A"
    field :team_b, :string, default: "Side B"
    field :unit, :string, default: "points"
    field :duration_seconds, :integer, default: 600
    field :remaining_seconds, :integer, default: 600
    field :deadline_at, :utc_datetime
    field :status, :string, default: "idle"
    field :score_a, :integer, default: 0
    field :score_b, :integer, default: 0
    field :revision, :integer, default: 1
    timestamps(type: :utc_datetime)
  end

  def changeset(board, attrs) do
    board
    |> cast(attrs, [:team_a, :team_b, :unit, :duration_seconds, :referee_id])
    |> update_change(:team_a, &String.trim/1)
    |> update_change(:team_b, &String.trim/1)
    |> validate_required([:team_a, :team_b, :unit, :duration_seconds, :referee_id])
    |> validate_length(:team_a, max: 60)
    |> validate_length(:team_b, max: 60)
    |> validate_inclusion(:unit, ["points", "goals", "rounds"])
    |> validate_number(:duration_seconds, greater_than: 0, less_than_or_equal_to: 14_400)
    |> foreign_key_constraint(:referee_id)
    |> unique_constraint(:session_id)
    |> check_constraint(:duration_seconds, name: :assistant_board_bounds)
  end
end
