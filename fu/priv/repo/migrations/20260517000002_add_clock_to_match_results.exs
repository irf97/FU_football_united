defmodule Fu.Repo.Migrations.AddClockToMatchResults do
  use Ecto.Migration

  def change do
    alter table(:match_results) do
      add :started_at, :utc_datetime
      add :paused_at, :utc_datetime
      add :pause_seconds, :integer, null: false, default: 0
    end
  end
end
