defmodule Fu.Queues.Queue do
  use Ecto.Schema
  import Ecto.Changeset

  @states ~w(open locked confirmed cancelled completed)

  schema "queues" do
    field :format, :string, default: "8v8"
    field :formation, :string, default: "1-3-3-1"
    field :scheduled_at, :utc_datetime
    field :state, :string, default: "open"
    field :region, :string, default: "Enschede"
    field :rated, :boolean, default: true
    field :extended_once, :boolean, default: false

    belongs_to :field, Fu.Fields.Field
    has_many :slots, Fu.Queues.QueueSlot
    has_many :memberships, Fu.Queues.QueueMembership
    timestamps(type: :utc_datetime)
  end

  def changeset(queue, attrs) do
    queue
    |> cast(attrs, [:field_id, :format, :formation, :scheduled_at, :state, :region, :rated, :extended_once])
    |> validate_required([:field_id, :format, :formation, :scheduled_at, :state, :region])
    |> validate_inclusion(:format, Fu.Positions.formats())
    |> validate_inclusion(:state, @states)
  end

  def states, do: @states
end
