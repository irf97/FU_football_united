defmodule Fu.Repo.Migrations.CreateQueues do
  use Ecto.Migration

  def change do
    create table(:queues) do
      add :field_id, references(:fields, on_delete: :delete_all), null: false
      add :format, :string, null: false, default: "8v8"
      add :formation, :string, null: false, default: "1-3-3-1"
      add :scheduled_at, :utc_datetime, null: false
      add :state, :string, null: false, default: "open"
      add :region, :string, null: false, default: "Enschede"
      add :rated, :boolean, null: false, default: true
      add :extended_once, :boolean, null: false, default: false

      timestamps(type: :utc_datetime)
    end

    create index(:queues, [:field_id])
    create index(:queues, [:state])
    create index(:queues, [:scheduled_at])
  end
end
