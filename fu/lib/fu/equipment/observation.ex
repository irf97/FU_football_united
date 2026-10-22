defmodule Fu.Equipment.Observation do
  use Ecto.Schema

  schema "equipment_observations" do
    belongs_to :asset, Fu.Equipment.Asset
    belongs_to :receiver, Fu.Equipment.Receiver
    field :source, :string
    field :zone, :string
    field :observed_at, :utc_datetime
    field :message_id, :string
    field :rssi, :integer
    timestamps(type: :utc_datetime, updated_at: false)
  end
end
