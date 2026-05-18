defmodule Fu.Repo.Migrations.AddPositionDetailToPlayers do
  use Ecto.Migration

  # Display/preference metadata only — deliberately NOT used by the
  # quota/fill/balance engine (those speak the main 4: GK/DEF/MID/FWD).
  def change do
    alter table(:players) do
      add :primary_detail, :string
      add :secondary_detail, :string
    end
  end
end
