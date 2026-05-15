defmodule Fu.Repo.Migrations.CreateFields do
  use Ecto.Migration

  def change do
    create table(:fields) do
      add :name, :string, null: false
      add :operator_name, :string, null: false
      add :address, :string
      add :lat, :float, null: false
      add :lng, :float, null: false
      add :region, :string, null: false, default: "Enschede"
      add :formats, {:array, :string}, null: false, default: []

      timestamps(type: :utc_datetime)
    end

    create index(:fields, [:region])
  end
end
