defmodule Fu.Repo.Migrations.AddLockedAtToMemberships do
  use Ecto.Migration

  # Soft join (status "queued") → hard commitment (locked_at set). A match
  # is "good to go" when every quota slot is filled by locked members.
  def change do
    alter table(:queue_memberships) do
      add :locked_at, :utc_datetime
    end
  end
end
