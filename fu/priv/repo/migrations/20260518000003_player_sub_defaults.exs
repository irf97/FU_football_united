defmodule Fu.Repo.Migrations.PlayerSubDefaults do
  use Ecto.Migration

  # Default sub-position per main position — display/preference only,
  # never read by the quota/fill/balance/matching engine. GK has no
  # variant. Replaces the earlier per-slot detail columns (no real data;
  # added and removed within iteration).
  def change do
    alter table(:players) do
      add :def_sub, :string
      add :mid_sub, :string
      add :fwd_sub, :string
      remove :primary_detail, :string
      remove :secondary_detail, :string
    end
  end
end
