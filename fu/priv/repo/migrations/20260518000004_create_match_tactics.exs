defmodule Fu.Repo.Migrations.CreateMatchTactics do
  use Ecto.Migration

  def change do
    create table(:match_tactics) do
      add :queue_id, references(:queues, on_delete: :delete_all), null: false
      add :team, :string, null: false
      add :formation, :string, null: false
      add :style, :string, null: false
      add :notes, :string, size: 280, default: ""
      timestamps(type: :utc_datetime)
    end

    create unique_index(:match_tactics, [:queue_id, :team])
  end
end
