defmodule Fu.Repo.Migrations.AddAttemptsToOtpCodes do
  use Ecto.Migration

  def change do
    alter table(:otp_codes) do
      add :attempts, :integer, null: false, default: 0
    end

    # Rate-limit + attempt-cap lookups filter by phone within a recent window.
    create index(:otp_codes, [:phone, :inserted_at])
  end
end
