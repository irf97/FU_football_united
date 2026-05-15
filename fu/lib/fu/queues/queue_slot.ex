defmodule Fu.Queues.QueueSlot do
  use Ecto.Schema
  import Ecto.Changeset

  schema "queue_slots" do
    field :position, :string
    field :capacity, :integer

    belongs_to :queue, Fu.Queues.Queue
    timestamps(type: :utc_datetime)
  end

  def changeset(slot, attrs) do
    slot
    |> cast(attrs, [:queue_id, :position, :capacity])
    |> validate_required([:queue_id, :position, :capacity])
    |> validate_inclusion(:position, Fu.Positions.positions())
  end
end
