defmodule Fu.Tactics.Tactics do
  use Ecto.Schema
  import Ecto.Changeset

  schema "match_tactics" do
    field :team, :string
    field :formation, :string
    field :style, :string
    field :notes, :string, default: ""

    belongs_to :queue, Fu.Queues.Queue
    timestamps(type: :utc_datetime)
  end

  def changeset(t, attrs) do
    t
    |> cast(attrs, [:queue_id, :team, :formation, :style, :notes])
    |> validate_required([:queue_id, :team, :formation, :style])
    |> validate_inclusion(:team, ["A", "B"])
    |> validate_inclusion(:formation, Fu.Tactics.formations(),
      message: "pick a formation from the list"
    )
    |> validate_inclusion(:style, Fu.Tactics.styles(), message: "pick a style from the list")
    |> validate_length(:notes, max: 280)
    |> unique_constraint([:queue_id, :team])
  end
end
