defmodule Fu.Voting.Vote do
  use Ecto.Schema
  import Ecto.Changeset

  @categories ~w(mvp defender keeper)

  schema "votes" do
    field :category, :string
    field :score, :integer
    field :own_team, :boolean, default: false
    field :skipped, :boolean, default: false

    belongs_to :queue, Fu.Queues.Queue
    belongs_to :voter, Fu.Accounts.Player
    belongs_to :subject, Fu.Accounts.Player
    timestamps(type: :utc_datetime)
  end

  def changeset(vote, attrs) do
    vote
    |> cast(attrs, [:queue_id, :voter_id, :subject_id, :category, :score, :own_team, :skipped])
    |> validate_required([:queue_id, :voter_id, :category])
    |> validate_inclusion(:category, @categories)
    |> validate_number(:score, greater_than_or_equal_to: 0, less_than_or_equal_to: 10)
    |> unique_constraint([:queue_id, :voter_id, :category])
  end

  def categories, do: @categories
end
