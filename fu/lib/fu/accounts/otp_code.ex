defmodule Fu.Accounts.OtpCode do
  use Ecto.Schema
  import Ecto.Changeset

  schema "otp_codes" do
    field :phone, :string
    field :code, :string
    field :expires_at, :utc_datetime
    field :consumed_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  def changeset(otp, attrs) do
    otp
    |> cast(attrs, [:phone, :code, :expires_at, :consumed_at])
    |> validate_required([:phone, :code, :expires_at])
  end
end
