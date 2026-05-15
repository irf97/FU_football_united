defmodule Fu.Repo.Migrations.CreateQueueSlots do
  use Ecto.Migration

  def change do
    create table(:queue_slots) do
      add :queue_id, references(:queues, on_delete: :delete_all), null: false
      add :position, :string, null: false
      add :capacity, :integer, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:queue_slots, [:queue_id, :position])
  end
end
