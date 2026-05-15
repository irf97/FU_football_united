defmodule Fu.Groups.GroupMembership do
  use Ecto.Schema
  import Ecto.Changeset

  schema "group_memberships" do
    belongs_to :group, Fu.Groups.Group
    belongs_to :player, Fu.Accounts.Player
    timestamps(type: :utc_datetime)
  end

  def changeset(m, attrs) do
    m
    |> cast(attrs, [:group_id, :player_id])
    |> validate_required([:group_id, :player_id])
    |> unique_constraint([:group_id, :player_id])
  end
end
