defmodule Fu.Groups.Group do
  use Ecto.Schema
  import Ecto.Changeset

  schema "groups" do
    field :invite_code, :string

    belongs_to :leader, Fu.Accounts.Player
    belongs_to :queue, Fu.Queues.Queue
    has_many :memberships, Fu.Groups.GroupMembership
    timestamps(type: :utc_datetime)
  end

  def changeset(group, attrs) do
    group
    |> cast(attrs, [:leader_id, :invite_code, :queue_id])
    |> validate_required([:leader_id, :invite_code])
    |> unique_constraint(:invite_code)
  end
end
