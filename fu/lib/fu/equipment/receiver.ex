defmodule Fu.Equipment.Receiver do
  use Ecto.Schema
  import Ecto.Changeset

  schema "equipment_receivers" do
    belongs_to :owner, Fu.Accounts.Player
    field :name, :string
    field :zone, :string
    field :token_hash, :binary, redact: true
    field :revoked_at, :utc_datetime
    timestamps(type: :utc_datetime)
  end

  def changeset(receiver, attrs) do
    receiver
    |> cast(attrs, [:name, :zone])
    |> update_change(:name, &String.trim/1)
    |> update_change(:zone, &String.trim/1)
    |> validate_required([:name, :zone, :token_hash])
    |> validate_length(:name, max: 120)
    |> validate_length(:zone, max: 120)
    |> unique_constraint(:token_hash)
    |> foreign_key_constraint(:owner_id)
  end
end
