defmodule Fu.Fields.Field do
  use Ecto.Schema
  import Ecto.Changeset

  schema "fields" do
    field :name, :string
    field :operator_name, :string
    field :address, :string
    field :lat, :float
    field :lng, :float
    field :region, :string, default: "Enschede"
    field :formats, {:array, :string}, default: []

    has_many :queues, Fu.Queues.Queue
    timestamps(type: :utc_datetime)
  end

  def changeset(field, attrs) do
    field
    |> cast(attrs, [:name, :operator_name, :address, :lat, :lng, :region, :formats])
    |> validate_required([:name, :operator_name, :lat, :lng, :region])
  end
end
