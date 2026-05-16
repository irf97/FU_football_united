defmodule Fu.Repo.Migrations.CreateRankEvents do
  use Ecto.Migration

  def change do
    # Append-only rank ledger (spec §2.9 "deterministic and inspectable").
    create table(:rank_events) do
      add :player_id, references(:players, on_delete: :delete_all), null: false
      add :queue_id, references(:queues, on_delete: :nilify_all)
      add :kind, :string, null: false, default: "match"
      add :delta, :float, null: false, default: 0.0
      add :rank_before, :float, null: false
      add :rank_after, :float, null: false
      add :breakdown, :map, null: false, default: %{}

      timestamps(type: :utc_datetime)
    end

    create index(:rank_events, [:player_id])
    create unique_index(:rank_events, [:player_id, :queue_id, :kind])
  end
end
