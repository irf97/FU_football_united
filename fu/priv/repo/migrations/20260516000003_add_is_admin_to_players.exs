defmodule Fu.Repo.Migrations.AddIsAdminToPlayers do
  use Ecto.Migration

  def change do
    alter table(:players) do
      add :is_admin, :boolean, null: false, default: false
    end
  end
end
