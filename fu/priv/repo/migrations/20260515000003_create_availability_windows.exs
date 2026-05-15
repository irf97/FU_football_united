defmodule Fu.Repo.Migrations.CreateAvailabilityWindows do
  use Ecto.Migration

  def change do
    create table(:availability_windows) do
      add :player_id, references(:players, on_delete: :delete_all), null: false
      add :kind, :string, null: false, default: "recurring"
      add :weekday, :integer
      add :date, :date
      add :start_time, :time, null: false
      add :end_time, :time, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:availability_windows, [:player_id])
  end
end
