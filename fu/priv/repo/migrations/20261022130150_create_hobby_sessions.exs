defmodule Fu.Repo.Migrations.CreateHobbySessions do
  use Ecto.Migration

  def change do
    create table(:hobby_sessions) do
      add :host_id, references(:players), null: false
      add :title, :string, null: false, size: 120
      add :hobby, :string, null: false, size: 60
      add :mode, :string, null: false, default: "open"
      add :place, :string, null: false, size: 200
      add :access_status, :string, null: false, default: "pending"
      add :access_note, :text
      add :starts_at, :utc_datetime, null: false
      add :ends_at, :utc_datetime, null: false
      add :capacity, :integer, null: false
      add :min_participants, :integer, null: false, default: 1
      add :status, :string, null: false, default: "scheduled"
      add :cancellation_reason, :text
      timestamps(type: :utc_datetime)
    end

    create index(:hobby_sessions, [:status, :starts_at])
    create index(:hobby_sessions, [:hobby, :starts_at])

    create constraint(:hobby_sessions, :hobby_sessions_capacity_bounds,
             check: "capacity > 0 AND capacity <= 1000"
           )

    create constraint(:hobby_sessions, :hobby_sessions_minimum_bounds,
             check: "min_participants > 0 AND min_participants <= capacity"
           )

    create constraint(:hobby_sessions, :hobby_sessions_time_window, check: "ends_at > starts_at")

    create constraint(:hobby_sessions, :hobby_sessions_modes,
             check: "mode IN ('open', 'practice', 'committed')"
           )

    create constraint(:hobby_sessions, :hobby_sessions_states,
             check: "status IN ('scheduled', 'active', 'completed', 'cancelled')"
           )

    create constraint(:hobby_sessions, :hobby_sessions_access_states,
             check: "access_status IN ('pending', 'host_confirmed')"
           )

    create table(:hobby_participants) do
      add :session_id, references(:hobby_sessions, on_delete: :delete_all), null: false
      add :player_id, references(:players), null: false
      add :status, :string, null: false, default: "joined"
      add :committed_at, :utc_datetime
      add :attended_at, :utc_datetime
      add :left_at, :utc_datetime
      add :withdrawal_reason, :text
      timestamps(type: :utc_datetime)
    end

    create unique_index(:hobby_participants, [:session_id, :player_id])
    create index(:hobby_participants, [:session_id, :status])

    create constraint(:hobby_participants, :hobby_participants_states,
             check: "status IN ('joined', 'committed', 'attended', 'left', 'cancelled')"
           )

    create table(:hobby_events) do
      add :session_id, references(:hobby_sessions, on_delete: :delete_all), null: false
      add :actor_id, references(:players), null: false
      add :action, :string, null: false
      add :payload, :map, null: false, default: %{}
      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:hobby_events, [:session_id, :id])
  end
end
