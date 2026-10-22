defmodule Fu.Equipment.Reservation do
  use Ecto.Schema

  schema "equipment_reservations" do
    belongs_to :asset, Fu.Equipment.Asset
    belongs_to :session, Fu.Hobbies.Session
    field :status, :string, default: "reserved"
    field :starts_at, :utc_datetime
    field :ends_at, :utc_datetime
    timestamps(type: :utc_datetime)
  end
end
