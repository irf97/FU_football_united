defmodule Fu.Repo.Migrations.CreateFriendships do
  use Ecto.Migration

  def change do
    create table(:friendships) do
      add :requester_id, references(:players, on_delete: :delete_all), null: false
      add :addressee_id, references(:players, on_delete: :delete_all), null: false
      add :status, :string, null: false, default: "pending"

      timestamps(type: :utc_datetime)
    end

    create unique_index(:friendships, [:requester_id, :addressee_id])
    create index(:friendships, [:addressee_id])
  end
end
