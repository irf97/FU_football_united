defmodule Fu.Friends do
  @moduledoc """
  Symmetric friendships + invite-link and phone-contact-match stubs
  (spec §2.12 "Adding friends"). No asymmetric follows in v1: a friend
  link exists only once both sides have confirmed.
  """

  import Ecto.Query
  alias Fu.Repo
  alias Fu.Accounts.Player
  alias Fu.Friends.Friendship

  @doc """
  Sends a friend request `requester` → `addressee` (pending). If the
  addressee has already requested the requester, the existing reverse
  request is accepted instead. Returns `{:ok, friendship}` or
  `{:error, changeset | reason}`.
  """
  def request_friend(%Player{id: rid}, %Player{id: aid}) do
    case Repo.get_by(Friendship, requester_id: aid, addressee_id: rid) do
      %Friendship{status: "pending"} = reverse ->
        accept_friend(reverse)

      _ ->
        %Friendship{}
        |> Friendship.changeset(%{requester_id: rid, addressee_id: aid, status: "pending"})
        |> Repo.insert()
    end
  end

  @doc "Marks a friendship as accepted (spec §2.12 — both sides confirm)."
  def accept_friend(%Friendship{} = friendship) do
    friendship
    |> Friendship.changeset(%{status: "accepted"})
    |> Repo.update()
  end

  def accept_friend(id) when is_integer(id) do
    case Repo.get(Friendship, id) do
      nil -> {:error, :not_found}
      friendship -> accept_friend(friendship)
    end
  end

  @doc "Lists accepted friends of `player` (either direction)."
  def list_friends(%Player{id: pid}) do
    from(p in Player,
      join: f in Friendship,
      on:
        (f.requester_id == ^pid and f.addressee_id == p.id) or
          (f.addressee_id == ^pid and f.requester_id == p.id),
      where: f.status == "accepted",
      order_by: [asc: p.display_name]
    )
    |> Repo.all()
  end

  @doc "Pending friend requests addressed to `player` (preloads :requester)."
  def pending_incoming(%Player{id: pid}) do
    from(f in Friendship,
      where: f.addressee_id == ^pid and f.status == "pending",
      order_by: [desc: f.inserted_at],
      preload: [:requester]
    )
    |> Repo.all()
  end

  @doc "Pending requests `player` has sent that aren't accepted yet."
  def pending_outgoing(%Player{id: pid}) do
    from(f in Friendship,
      where: f.requester_id == ^pid and f.status == "pending",
      order_by: [desc: f.inserted_at],
      preload: [:addressee]
    )
    |> Repo.all()
  end

  @doc """
  Sends a friend request to whoever owns `phone` (spec §2.12 "Adding
  friends" — phone-number match). Returns `{:ok, friendship}` or
  `{:error, :not_found | :self | :already_friends | :already_requested}`.
  """
  def request_by_phone(%Player{} = requester, phone) do
    norm = phone |> to_string() |> String.replace(~r/[^\d+]/, "")

    case Repo.get_by(Player, phone: norm) do
      nil ->
        {:error, :not_found}

      %Player{} = addressee ->
        cond do
          addressee.id == requester.id ->
            {:error, :self}

          friends?(requester, addressee) ->
            {:error, :already_friends}

          true ->
            case request_friend(requester, addressee) do
              {:ok, f} -> {:ok, f}
              {:error, %Ecto.Changeset{}} -> {:error, :already_requested}
              other -> other
            end
        end
    end
  end

  @doc "Declines/cancels a pending friend request (removes the row)."
  def decline_friend(id) when is_integer(id) do
    case Repo.get(Friendship, id) do
      nil -> {:error, :not_found}
      %Friendship{} = f -> Repo.delete(f)
    end
  end

  @doc "Is there an accepted friendship between `a` and `b` (either direction)?"
  def friends?(%Player{id: a}, %Player{id: b}) do
    from(f in Friendship,
      where:
        f.status == "accepted" and
          ((f.requester_id == ^a and f.addressee_id == ^b) or
             (f.requester_id == ^b and f.addressee_id == ^a))
    )
    |> Repo.exists?()
  end

  @doc "Direct invite link for `player` (spec §2.12 — share to add a friend)."
  def invite_link(%Player{id: pid}) do
    code = Base.url_encode64("p:#{pid}", padding: false)
    "https://fu.app/invite/" <> code
  end

  @doc """
  Phone-contact import stub (spec §2.12): given a list of phone strings,
  returns the players whose `:phone` matches one of them.
  """
  def find_by_phone_contacts(phones) when is_list(phones) do
    from(p in Player, where: p.phone in ^phones)
    |> Repo.all()
  end
end
