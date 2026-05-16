defmodule Fu.Ranking.Dispute do
  use Ecto.Schema
  import Ecto.Changeset

  @moduledoc """
  A player-filed dispute against a rank event or queue outcome (spec §2.10).
  Disputes are append-only and resolved by *amendment*: the disputed
  `RankEvent` is never edited — the resolution is recorded here instead, so
  the ledger stays inspectable (spec §2.9, §2.10).
  """

  @statuses ~w(open resolved)

  schema "disputes" do
    field :kind, :string
    field :note, :string
    field :status, :string, default: "open"
    field :resolution, :string

    belongs_to :player, Fu.Accounts.Player
    belongs_to :rank_event, Fu.Ranking.RankEvent
    belongs_to :queue, Fu.Queues.Queue
    timestamps(type: :utc_datetime)
  end

  @doc "Validates a dispute filing (spec §2.10)."
  def changeset(dispute, attrs) do
    dispute
    |> cast(attrs, [:player_id, :rank_event_id, :queue_id, :kind, :note, :status, :resolution])
    |> validate_required([:player_id, :kind, :status])
    |> validate_inclusion(:status, @statuses)
  end
end
