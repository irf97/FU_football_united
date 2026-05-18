defmodule Fu.Repo.Migrations.AddIdentityFieldsToPlayers do
  use Ecto.Migration

  def change do
    alter table(:players) do
      add :nickname, :string
      add :nation, :string
      add :birthdate, :date
    end
  end
end
