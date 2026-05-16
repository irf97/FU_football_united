defmodule Fu.Booking.Booking do
  use Ecto.Schema
  import Ecto.Changeset

  @states ~w(speculative provisional confirmed released)

  schema "bookings" do
    field :state, :string, default: "speculative"
    field :deposit_paid, :boolean, default: false
    field :balance_paid, :boolean, default: false
    field :operator_ref, :string

    belongs_to :queue, Fu.Queues.Queue
    belongs_to :field, Fu.Fields.Field
    timestamps(type: :utc_datetime)
  end

  def changeset(booking, attrs) do
    booking
    |> cast(attrs, [:queue_id, :field_id, :state, :deposit_paid, :balance_paid, :operator_ref])
    |> validate_required([:queue_id, :field_id, :state])
    |> validate_inclusion(:state, @states)
    |> unique_constraint(:queue_id)
  end

  def states, do: @states
end
