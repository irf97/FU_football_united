defmodule Fu.Ranking.RankEvent do
  use Ecto.Schema
  import Ecto.Changeset

  @moduledoc """
  Append-only ranking ledger entry (spec §2.9 — the ranking engine must be
  "deterministic and inspectable"). One row records a single rank change with
  its full `breakdown` so any delta is auditable after the fact. Rows are
  never mutated; corrections happen via `Fu.Ranking.Dispute` (spec §2.10).
  """

  @kinds ~w(match no_show decay skip_penalty)

  schema "rank_events" do
    field :kind, :string, default: "match"
    field :delta, :float, default: 0.0
    field :rank_before, :float
    field :rank_after, :float
    field :breakdown, :map, default: %{}

    belongs_to :player, Fu.Accounts.Player
    belongs_to :queue, Fu.Queues.Queue
    timestamps(type: :utc_datetime)
  end

  @doc "Validates an append-only rank event (spec §2.9)."
  def changeset(event, attrs) do
    event
    |> cast(attrs, [:player_id, :queue_id, :kind, :delta, :rank_before, :rank_after, :breakdown])
    |> validate_required([:player_id, :kind, :delta, :rank_before, :rank_after, :breakdown])
    |> validate_inclusion(:kind, @kinds)
    |> unique_constraint([:player_id, :queue_id, :kind])
  end
end
