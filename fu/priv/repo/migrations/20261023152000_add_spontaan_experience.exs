defmodule Fu.Repo.Migrations.AddSpontaanExperience do
  use Ecto.Migration

  def change do
    alter table(:players) do
      add(:main_hobby, :string, size: 60)
      add(:experience_theme, :string, null: false, default: "auto")
    end

    create(
      constraint(:players, :player_experience_valid,
        check:
          "experience_theme IN ('auto', 'spontaan', 'football', 'court', 'music', 'outdoors', 'making')"
      )
    )
  end
end
