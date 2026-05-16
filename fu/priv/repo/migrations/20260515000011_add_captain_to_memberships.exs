defmodule Fu.Repo.Migrations.AddCaptainToMemberships do
  use Ecto.Migration

  def change do
    alter table(:queue_memberships) do
      add :is_captain, :boolean, null: false, default: false
    end
  end
end
