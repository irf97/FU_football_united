defmodule Fu.Equipment.Asset do
  use Ecto.Schema
  import Ecto.Changeset

  schema "equipment_assets" do
    belongs_to :owner, Fu.Accounts.Player
    field :name, :string
    field :hobby, :string
    field :home_zone, :string, default: "Unassigned"
    field :beacon_id, :string
    field :condition, :string, default: "ready"
    field :location, :map, virtual: true
    has_many :reservations, Fu.Equipment.Reservation
    timestamps(type: :utc_datetime)
  end

  def changeset(asset, attrs) do
    asset
    |> cast(attrs, [:name, :hobby, :home_zone, :beacon_id, :condition])
    |> update_change(:name, &String.trim/1)
    |> update_change(:home_zone, &String.trim/1)
    |> update_change(:beacon_id, &String.trim/1)
    |> validate_required([:name, :home_zone, :condition])
    |> validate_length(:name, max: 120)
    |> validate_length(:hobby, max: 60)
    |> validate_length(:home_zone, max: 120)
    |> validate_length(:beacon_id, max: 120)
    |> validate_inclusion(:condition, ["ready", "maintenance", "retired"])
    |> unique_constraint([:owner_id, :beacon_id])
    |> foreign_key_constraint(:owner_id)
    |> check_constraint(:condition, name: :equipment_condition_valid)
  end
end
