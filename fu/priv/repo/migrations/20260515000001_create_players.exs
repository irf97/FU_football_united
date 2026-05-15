defmodule Fu.Repo.Migrations.CreatePlayers do
  use Ecto.Migration

  def change do
    create table(:players) do
      add :phone, :string, null: false
      add :display_name, :string, null: false
      add :avatar_url, :string
      add :jersey_number, :integer, default: 10
      add :home_lat, :float
      add :home_lng, :float
      add :home_label, :string
      add :rank, :float, null: false, default: 50.0
      add :playstyle, :string
      add :primary_position, :string, null: false, default: "MID"
      add :secondary_position, :string
      add :fill_mode, :boolean, null: false, default: false
      add :queue_region_km, :integer, null: false, default: 25
      add :suspended_until, :utc_datetime
      add :last_played_at, :utc_datetime
      add :skip_streak, :integer, null: false, default: 0

      timestamps(type: :utc_datetime)
    end

    create unique_index(:players, [:phone])
  end
end
