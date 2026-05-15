defmodule Fu.Friends.Friendship do
  use Ecto.Schema
  import Ecto.Changeset

  schema "friendships" do
    field :status, :string, default: "pending"

    belongs_to :requester, Fu.Accounts.Player
    belongs_to :addressee, Fu.Accounts.Player
    timestamps(type: :utc_datetime)
  end

  def changeset(friendship, attrs) do
    friendship
    |> cast(attrs, [:requester_id, :addressee_id, :status])
    |> validate_required([:requester_id, :addressee_id, :status])
    |> validate_inclusion(:status, ~w(pending accepted))
    |> validate_distinct_players()
    |> unique_constraint([:requester_id, :addressee_id])
  end

  defp validate_distinct_players(changeset) do
    requester = get_field(changeset, :requester_id)
    addressee = get_field(changeset, :addressee_id)

    if not is_nil(requester) and requester == addressee do
      add_error(changeset, :addressee_id, "cannot friend yourself")
    else
      changeset
    end
  end
end
