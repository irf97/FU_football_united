defmodule Fu.Repo.Migrations.AddSessionAssistant do
  use Ecto.Migration

  def change do
    create table(:assistant_boards) do
      add :session_id, references(:hobby_sessions, on_delete: :delete_all), null: false
      add :referee_id, references(:players, on_delete: :nilify_all)
      add :team_a, :string, null: false, default: "Side A"
      add :team_b, :string, null: false, default: "Side B"
      add :unit, :string, null: false, default: "points"
      add :duration_seconds, :integer, null: false, default: 600
      add :remaining_seconds, :integer, null: false, default: 600
      add :deadline_at, :utc_datetime
      add :status, :string, null: false, default: "idle"
      add :score_a, :integer, null: false, default: 0
      add :score_b, :integer, null: false, default: 0
      add :revision, :integer, null: false, default: 1
      timestamps(type: :utc_datetime)
    end

    create unique_index(:assistant_boards, [:session_id])

    create constraint(:assistant_boards, :assistant_board_bounds,
             check:
               "duration_seconds BETWEEN 1 AND 14400 AND remaining_seconds BETWEEN 0 AND 14400 AND score_a BETWEEN 0 AND 99999 AND score_b BETWEEN 0 AND 99999 AND revision > 0 AND unit IN ('points','goals','rounds')"
           )

    create constraint(:assistant_boards, :assistant_clock_valid,
             check:
               "(status = 'running' AND deadline_at IS NOT NULL) OR (status IN ('idle','paused','finalized') AND deadline_at IS NULL)"
           )

    create table(:assistant_events) do
      add :session_id, references(:hobby_sessions, on_delete: :delete_all), null: false
      add :actor_id, references(:players, on_delete: :nilify_all)
      add :action, :string, null: false
      add :request_id, :string, null: false
      add :fingerprint, :binary, null: false
      add :revision, :integer, null: false
      add :payload, :map, null: false, default: %{}
      timestamps(type: :utc_datetime, updated_at: false)
    end

    create unique_index(:assistant_events, [:session_id, :request_id])
    create unique_index(:assistant_events, [:session_id, :revision])
  end
end
