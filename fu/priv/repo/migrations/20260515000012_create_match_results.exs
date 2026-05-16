defmodule Fu.Repo.Migrations.CreateMatchResults do
  use Ecto.Migration

  def change do
    create table(:match_results) do
      add :queue_id, references(:queues, on_delete: :delete_all), null: false
      add :score_a, :integer, null: false, default: 0
      add :score_b, :integer, null: false, default: 0
      add :completed_at, :utc_datetime
      add :votes_close_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:match_results, [:queue_id])

    create table(:goals) do
      add :queue_id, references(:queues, on_delete: :delete_all), null: false
      add :scorer_id, references(:players, on_delete: :nilify_all)
      add :assist_id, references(:players, on_delete: :nilify_all)
      add :team, :string

      timestamps(type: :utc_datetime)
    end

    create index(:goals, [:queue_id])
  end
end
