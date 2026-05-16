defmodule Fu.QueueChat.QueueMessage do
  use Ecto.Schema
  import Ecto.Changeset

  schema "queue_messages" do
    field :body, :string

    belongs_to :queue, Fu.Queues.Queue
    belongs_to :player, Fu.Accounts.Player
    timestamps(type: :utc_datetime)
  end

  def changeset(msg, attrs) do
    msg
    |> cast(attrs, [:queue_id, :player_id, :body])
    |> validate_required([:queue_id, :player_id, :body])
    |> update_change(:body, &String.trim/1)
    |> validate_length(:body, min: 1, max: 500)
  end
end
