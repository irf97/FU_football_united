defmodule Fu.Repo.Migrations.CreateBookings do
  use Ecto.Migration

  def change do
    create table(:bookings) do
      add :queue_id, references(:queues, on_delete: :delete_all), null: false
      add :field_id, references(:fields, on_delete: :delete_all), null: false
      add :state, :string, null: false, default: "speculative"
      add :deposit_paid, :boolean, null: false, default: false
      add :balance_paid, :boolean, null: false, default: false
      add :operator_ref, :string

      timestamps(type: :utc_datetime)
    end

    create unique_index(:bookings, [:queue_id])
  end
end
