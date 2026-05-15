defmodule Fu.Repo.Migrations.CreateOtpCodes do
  use Ecto.Migration

  def change do
    create table(:otp_codes) do
      add :phone, :string, null: false
      add :code, :string, null: false
      add :expires_at, :utc_datetime, null: false
      add :consumed_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:otp_codes, [:phone])
  end
end
