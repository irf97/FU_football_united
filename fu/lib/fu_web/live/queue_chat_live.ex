defmodule FuWeb.QueueChatLive do
  @moduledoc """
  Per-queue chatroom (opens at ≥ `Fu.QueueChat.min_members/0` queued).
  Members only; persists so late joiners read back the conversation.
  """
  use FuWeb, :live_view

  alias Fu.{Queues, QueueChat}

  @impl true
  def mount(%{"queue_id" => qid}, _session, socket) do
    queue = Queues.get_queue!(qid)
    player = socket.assigns.current_player

    if QueueChat.member?(queue.id, player.id) do
      if connected?(socket) do
        QueueChat.subscribe(queue.id)
        Queues.subscribe(queue.id)
      end

      {:ok,
       socket
       |> assign(queue: queue, body: "")
       |> load()}
    else
      {:ok,
       socket
       |> put_flash(:error, "Join this queue to see its chat.")
       |> redirect(to: ~p"/browse")}
    end
  end

  defp load(socket) do
    qid = socket.assigns.queue.id

    assign(socket,
      messages: QueueChat.list_messages(qid),
      members: QueueChat.member_count(qid),
      open?: QueueChat.available?(qid)
    )
  end

  @impl true
  def handle_event("send", %{"body" => body}, socket) do
    case String.trim(body) do
      "" ->
        {:noreply, socket}

      text ->
        case QueueChat.post_message(socket.assigns.queue.id, socket.assigns.current_player, text) do
          {:ok, _} ->
            {:noreply, assign(socket, body: "")}

          {:error, :not_open} ->
            {:noreply, put_flash(socket, :error, "Chat opens at #{QueueChat.min_members()}+ players.")}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Couldn't send.")}
        end
    end
  end

  @impl true
  def handle_info({:queue_message, msg}, socket) do
    {:noreply, assign(socket, messages: socket.assigns.messages ++ [msg])}
  end

  def handle_info({:queue_changed, _id}, socket), do: {:noreply, load(socket)}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_player={@current_player} active={:browse}>
      <div class="flex items-center justify-between">
        <div>
          <h1 class="fu-serif text-xl text-primary">{@queue.field.name}</h1>
          <div class="text-xs fu-ink-soft font-mono">
            {@queue.format} · {Calendar.strftime(@queue.scheduled_at, "%a %d %b %H:%M")}
          </div>
        </div>
        <span class="pos-pill">{@members} in queue</span>
      </div>

      <.link navigate={~p"/browse"} class="text-xs fu-ink-soft">← back to queues</.link>

      <div :if={!@open?} class="fu-card p-6 text-center fu-ink-soft text-sm">
        Chatroom opens once {QueueChat.min_members()}+ players have joined.
        Currently {@members}.
      </div>

      <div :if={@open?} class="fu-card p-3 space-y-3">
        <div id="qchat-log" class="space-y-2 max-h-[55vh] overflow-y-auto">
          <div :if={@messages == []} class="text-sm fu-ink-soft text-center py-4">
            No messages yet — say hi 👋
          </div>
          <div :for={m <- @messages} class="text-sm">
            <span class={[
              "font-mono text-xs",
              m.player_id == @current_player.id && "text-primary",
              m.player_id != @current_player.id && "fu-ink-soft"
            ]}>
              {m.player.display_name}
            </span>
            <span class="fu-ink-dim text-[10px] font-mono">
              {Calendar.strftime(m.inserted_at, "%H:%M")}
            </span>
            <div>{m.body}</div>
          </div>
        </div>

        <.form for={%{}} phx-submit="send" class="flex gap-2">
          <input
            type="text"
            name="body"
            value={@body}
            placeholder="Message the queue…"
            autocomplete="off"
            class="input input-bordered input-sm flex-1 bg-base-200"
          />
          <button class="btn btn-sm btn-primary" type="submit">Send</button>
        </.form>
      </div>
    </Layouts.app>
    """
  end
end
