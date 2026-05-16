defmodule Fu.Repo.Migrations.CreateSemanticEvents do
  use Ecto.Migration

  # Append-only semantic event log — IrfTek paper §3 EVENT LAYER / §6
  # AI-readable runtime. The runtime already broadcasts these over
  # PubSub; this persists them in the paper's §6.3 shape.
  def change do
    create table(:semantic_events) do
      add :type, :string, null: false
      add :domain, :string, null: false, default: "football"
      add :payload, :map, null: false, default: %{}
      add :ts, :utc_datetime_usec, null: false
    end

    create index(:semantic_events, [:type])
    create index(:semantic_events, [:ts])
  end
end
