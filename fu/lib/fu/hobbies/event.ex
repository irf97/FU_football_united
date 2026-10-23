defmodule Fu.Hobbies.Event do
  use Ecto.Schema

  schema "hobby_events" do
    field :action, :string
    field :payload, :map, default: %{}
    belongs_to :session, Fu.Hobbies.Session
    belongs_to :actor, Fu.Accounts.Player
    timestamps(type: :utc_datetime, updated_at: false)
  end
end
