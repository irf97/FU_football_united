defmodule Fu.Repo.Migrations.CreateDisputes do
  use Ecto.Migration

  def change do
    # Disputes are appended as amendment events, never modifications (spec §2.10).
    create table(:disputes) do
      add :player_id, references(:players, on_delete: :delete_all), null: false
      add :rank_event_id, references(:rank_events, on_delete: :nilify_all)
      add :queue_id, references(:queues, on_delete: :nilify_all)
      add :kind, :string, null: false
      add :note, :text
      add :status, :string, null: false, default: "open"
      add :resolution, :text

      timestamps(type: :utc_datetime)
    end

    create index(:disputes, [:player_id])
    create index(:disputes, [:status])
  end
end
