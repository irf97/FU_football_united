defmodule Fu.Events.SemanticEvent do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :id, autogenerate: true}
  schema "semantic_events" do
    field :type, :string
    field :domain, :string, default: "football"
    field :payload, :map, default: %{}
    field :ts, :utc_datetime_usec
  end

  def changeset(ev, attrs) do
    ev
    |> cast(attrs, [:type, :domain, :payload, :ts])
    |> validate_required([:type, :domain, :ts])
  end
end
