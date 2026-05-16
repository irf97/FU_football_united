defmodule Fu.Repo.Migrations.AddAvatarToPlayers do
  use Ecto.Migration

  def change do
    alter table(:players) do
      add :avatar_legend, :string, null: false, default: "Pelé"
      add :avatar_kit, :string, null: false, default: "Custom"
      add :avatar_color, :string, null: false, default: "#67e8f9"
    end
  end
end
