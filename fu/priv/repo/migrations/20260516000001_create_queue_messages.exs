defmodule Fu.Repo.Migrations.CreateQueueMessages do
  use Ecto.Migration

  def change do
    create table(:queue_messages) do
      add :queue_id, references(:queues, on_delete: :delete_all), null: false
      add :player_id, references(:players, on_delete: :delete_all), null: false
      add :body, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:queue_messages, [:queue_id])
  end
end
