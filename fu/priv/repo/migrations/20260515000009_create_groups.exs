defmodule Fu.Repo.Migrations.CreateGroups do
  use Ecto.Migration

  def change do
    create table(:groups) do
      add :leader_id, references(:players, on_delete: :delete_all), null: false
      add :invite_code, :string, null: false
      add :queue_id, references(:queues, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create unique_index(:groups, [:invite_code])

    create table(:group_memberships) do
      add :group_id, references(:groups, on_delete: :delete_all), null: false
      add :player_id, references(:players, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:group_memberships, [:group_id, :player_id])
    create index(:group_memberships, [:player_id])
  end
end
