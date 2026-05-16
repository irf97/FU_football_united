defmodule Fu.Ranking.NoShow do
  use Ecto.Schema
  import Ecto.Changeset

  @moduledoc """
  A recorded no-show for a confirmed queue (spec §2.9, §4 Q1). Used to count
  repeat offences in a rolling 60-day window: the 2nd triggers a 14-day
  suspension on top of the rank penalty.
  """

  schema "no_shows" do
    field :occurred_at, :utc_datetime

    belongs_to :player, Fu.Accounts.Player
    belongs_to :queue, Fu.Queues.Queue
    timestamps(type: :utc_datetime)
  end

  @doc "Validates a no-show record (spec §2.9)."
  def changeset(no_show, attrs) do
    no_show
    |> cast(attrs, [:player_id, :queue_id, :occurred_at])
    |> validate_required([:player_id, :occurred_at])
  end
end
