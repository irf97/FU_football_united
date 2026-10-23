defmodule Fu.Hobbies.Participant do
  use Ecto.Schema

  schema "hobby_participants" do
    field :status, :string, default: "joined"
    field :committed_at, :utc_datetime
    field :attended_at, :utc_datetime
    field :left_at, :utc_datetime
    field :withdrawal_reason, :string
    belongs_to :session, Fu.Hobbies.Session
    belongs_to :player, Fu.Accounts.Player
    timestamps(type: :utc_datetime)
  end
end
