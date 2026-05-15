defmodule Fu.Queues.QueueMembership do
  use Ecto.Schema
  import Ecto.Changeset

  schema "queue_memberships" do
    field :declared_position, :string
    field :status, :string, default: "queued"
    field :team, :string
    field :joined_in_lock, :boolean, default: false

    belongs_to :queue, Fu.Queues.Queue
    belongs_to :player, Fu.Accounts.Player
    timestamps(type: :utc_datetime)
  end

  def changeset(m, attrs) do
    m
    |> cast(attrs, [:queue_id, :player_id, :declared_position, :status, :team, :joined_in_lock])
    |> validate_required([:queue_id, :player_id, :declared_position, :status])
    |> validate_inclusion(:declared_position, Fu.Positions.positions())
    |> validate_inclusion(:status, ~w(queued left))
    |> unique_constraint([:queue_id, :player_id])
  end
end
