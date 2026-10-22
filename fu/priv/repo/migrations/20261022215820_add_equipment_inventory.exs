defmodule Fu.Repo.Migrations.AddEquipmentInventory do
  use Ecto.Migration

  def change do
    create table(:equipment_assets) do
      add :owner_id, references(:players, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :hobby, :string
      add :home_zone, :string, null: false, default: "Unassigned"
      add :beacon_id, :string
      add :condition, :string, null: false, default: "ready"
      timestamps(type: :utc_datetime)
    end

    create unique_index(:equipment_assets, [:owner_id, :beacon_id])

    create constraint(:equipment_assets, :equipment_condition_valid,
             check: "condition IN ('ready','maintenance','retired')"
           )

    create table(:equipment_receivers) do
      add :owner_id, references(:players, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :zone, :string, null: false
      add :token_hash, :binary, null: false
      add :revoked_at, :utc_datetime
      timestamps(type: :utc_datetime)
    end

    create unique_index(:equipment_receivers, [:token_hash])
    create index(:equipment_receivers, [:owner_id])

    create table(:equipment_observations) do
      add :asset_id, references(:equipment_assets, on_delete: :delete_all), null: false
      add :receiver_id, references(:equipment_receivers, on_delete: :delete_all)
      add :source, :string, null: false
      add :zone, :string, null: false
      add :observed_at, :utc_datetime, null: false
      add :message_id, :string
      add :rssi, :integer
      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:equipment_observations, [:asset_id, :observed_at, :id])
    create unique_index(:equipment_observations, [:receiver_id, :message_id])

    create constraint(:equipment_observations, :equipment_source_valid,
             check:
               "(source = 'manual' AND receiver_id IS NULL AND message_id IS NULL) OR (source = 'receiver_report' AND receiver_id IS NOT NULL AND message_id IS NOT NULL)"
           )

    create constraint(:equipment_observations, :equipment_rssi_bounds,
             check: "rssi IS NULL OR rssi BETWEEN -127 AND 20"
           )

    create table(:equipment_reservations) do
      add :asset_id, references(:equipment_assets, on_delete: :delete_all), null: false
      add :session_id, references(:hobby_sessions, on_delete: :delete_all), null: false
      add :status, :string, null: false, default: "reserved"
      add :starts_at, :utc_datetime, null: false
      add :ends_at, :utc_datetime, null: false
      timestamps(type: :utc_datetime)
    end

    create unique_index(:equipment_reservations, [:asset_id, :session_id])
    create index(:equipment_reservations, [:session_id])

    create constraint(:equipment_reservations, :equipment_reservation_valid,
             check: "status IN ('reserved','released') AND ends_at > starts_at"
           )
  end
end
