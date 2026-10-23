defmodule Fu.Assistant.Event do
  use Ecto.Schema

  schema "assistant_events" do
    belongs_to :session, Fu.Hobbies.Session
    belongs_to :actor, Fu.Accounts.Player
    field :action, :string
    field :request_id, :string
    field :fingerprint, :binary, redact: true
    field :revision, :integer
    field :payload, :map, default: %{}
    timestamps(type: :utc_datetime, updated_at: false)
  end
end
