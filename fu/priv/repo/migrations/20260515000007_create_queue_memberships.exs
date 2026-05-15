defmodule Fu.Repo.Migrations.CreateQueueMemberships do
  use Ecto.Migration

  def change do
    create table(:queue_memberships) do
      add :queue_id, references(:queues, on_delete: :delete_all), null: false
      add :player_id, references(:players, on_delete: :delete_all), null: false
      add :declared_position, :string, null: false
      add :status, :string, null: false, default: "queued"
      add :team, :string
      add :joined_in_lock, :boolean, null: false, default: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:queue_memberships, [:queue_id, :player_id])
    create index(:queue_memberships, [:queue_id])
    create index(:queue_memberships, [:player_id])
  end
end
