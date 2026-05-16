defmodule Fu.QueueChat do
  @moduledoc """
  Per-queue chatroom. A queue earns a chatroom once at least
  `min_members/0` players have joined it — players coordinate (lifts,
  kit, "who's bringing the keeper") during the open period, before the
  lobby exists. Messages persist (the queue fills over hours, so late
  joiners must be able to read back).
  """

  import Ecto.Query
  alias Fu.Repo
  alias Fu.Queues.QueueMembership
  alias Fu.QueueChat.QueueMessage

  @min_members 3

  @doc "How many queued players a queue needs before its chatroom opens."
  def min_members, do: @min_members

  def topic(queue_id), do: "queue_chat:#{queue_id}"

  def subscribe(queue_id),
    do: Phoenix.PubSub.subscribe(Fu.PubSub, topic(queue_id))

  @doc "Number of currently-queued players in a queue."
  def member_count(queue_id) do
    Repo.aggregate(
      from(m in QueueMembership, where: m.queue_id == ^queue_id and m.status == "queued"),
      :count,
      :id
    )
  end

  @doc "Does this queue have a chatroom yet (≥ #{@min_members} queued)?"
  def available?(queue_id), do: member_count(queue_id) >= @min_members

  @doc "Is the player a current member of this queue (gate for read/post)?"
  def member?(queue_id, player_id) do
    Repo.exists?(
      from m in QueueMembership,
        where:
          m.queue_id == ^queue_id and m.player_id == ^player_id and m.status == "queued"
    )
  end

  @doc "Messages oldest-first, each with its author preloaded."
  def list_messages(queue_id) do
    from(msg in QueueMessage,
      where: msg.queue_id == ^queue_id,
      order_by: [asc: msg.inserted_at, asc: msg.id],
      preload: [:player]
    )
    |> Repo.all()
  end

  @doc """
  Posts a message. Rejected unless the chatroom is open (`available?/1`)
  and the author is a member of the queue. Broadcasts `{:queue_message,
  message}` on the queue-chat topic.
  """
  def post_message(queue_id, %{id: player_id}, body) do
    cond do
      not available?(queue_id) ->
        {:error, :not_open}

      not member?(queue_id, player_id) ->
        {:error, :not_member}

      true ->
        %QueueMessage{}
        |> QueueMessage.changeset(%{queue_id: queue_id, player_id: player_id, body: body})
        |> Repo.insert()
        |> case do
          {:ok, msg} ->
            msg = Repo.preload(msg, :player)
            Phoenix.PubSub.broadcast(Fu.PubSub, topic(queue_id), {:queue_message, msg})
            {:ok, msg}

          err ->
            err
        end
    end
  end
end
