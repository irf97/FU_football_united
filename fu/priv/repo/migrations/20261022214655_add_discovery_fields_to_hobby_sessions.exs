defmodule Fu.Repo.Migrations.AddDiscoveryFieldsToHobbySessions do
  use Ecto.Migration

  def change do
    alter table(:hobby_sessions) do
      add :category, :string, null: false, default: "other"
      add :kind, :string, null: false, default: "session"
    end

    create constraint(:hobby_sessions, :hobby_category_valid,
             check:
               "category IN ('sport','music','arts','games','outdoors','making','learning','social','other')"
           )

    create constraint(:hobby_sessions, :hobby_kind_valid,
             check: "kind IN ('session','event','class','meetup')"
           )

    create index(:hobby_sessions, [:category, :status, :starts_at])
  end
end
