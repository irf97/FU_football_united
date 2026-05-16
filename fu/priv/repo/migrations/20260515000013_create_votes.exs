defmodule Fu.Repo.Migrations.CreateVotes do
  use Ecto.Migration

  def change do
    create table(:votes) do
      add :queue_id, references(:queues, on_delete: :delete_all), null: false
      add :voter_id, references(:players, on_delete: :delete_all), null: false
      add :subject_id, references(:players, on_delete: :delete_all)
      add :category, :string, null: false
      add :score, :integer
      add :own_team, :boolean, null: false, default: false
      add :skipped, :boolean, null: false, default: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:votes, [:queue_id, :voter_id, :category])
    create index(:votes, [:queue_id, :category])
  end
end
