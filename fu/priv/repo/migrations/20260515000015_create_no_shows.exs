defmodule Fu.Repo.Migrations.CreateNoShows do
  use Ecto.Migration

  def change do
    create table(:no_shows) do
      add :player_id, references(:players, on_delete: :delete_all), null: false
      add :queue_id, references(:queues, on_delete: :nilify_all)
      add :occurred_at, :utc_datetime, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:no_shows, [:player_id])
  end
end
