defmodule FuWeb.QueueChatLive do
  @moduledoc """
  Per-queue chatroom (opens at ≥ `Fu.QueueChat.min_members/0` queued).
  Anyone can read once it's open; only queue members can post. Messages
  persist so late joiners read back. Telegram/WhatsApp-style bubble UI.
  """
  use FuWeb, :live_view

  alias Fu.{Queues, QueueChat}
  alias FuWeb.Avatars

  @impl true
  def mount(%{"queue_id" => qid}, _session, socket) do
    queue = Queues.get_queue!(qid)

    if connected?(socket) do
      QueueChat.subscribe(queue.id)
      Queues.subscribe(queue.id)
    end

    {:ok, socket |> assign(queue: queue, body: "") |> load()}
  end

  defp load(socket) do
    qid = socket.assigns.queue.id
    player = socket.assigns.current_player
    queue = Queues.get_queue!(qid)

    queued =
      queue.memberships
      |> Enum.filter(&(&1.status == "queued"))
      |> Enum.sort_by(& &1.id)

    assign(socket,
      queue: queue,
      messages: QueueChat.list_messages(qid),
      queued: queued,
      members: length(queued),
      open?: QueueChat.available?(qid),
      can_post?: QueueChat.member?(qid, player.id)
    )
  end

  @impl true
  def handle_event("send", %{"body" => body}, socket) do
    case String.trim(body) do
      "" ->
        {:noreply, socket}

      text ->
        case QueueChat.post_message(socket.assigns.queue.id, socket.assigns.current_player, text) do
          {:ok, _} -> {:noreply, assign(socket, body: "")}
          {:error, :not_open} -> {:noreply, put_flash(socket, :error, "Chat opens at #{QueueChat.min_members()}+ players.")}
          {:error, :not_member} -> {:noreply, put_flash(socket, :error, "Join this queue to send messages.")}
          {:error, _} -> {:noreply, put_flash(socket, :error, "Couldn't send.")}
        end
    end
  end

  def handle_event("join", _params, socket) do
    case Queues.join(socket.assigns.queue, socket.assigns.current_player) do
      {:ok, _} -> {:noreply, socket |> put_flash(:info, "Joined — you can chat now.") |> load()}
      {:error, reason} -> {:noreply, put_flash(socket, :error, "Couldn't join (#{reason}).")}
    end
  end

  @impl true
  def handle_info({:queue_message, msg}, socket),
    do: {:noreply, assign(socket, messages: socket.assigns.messages ++ [msg])}

  def handle_info({:queue_changed, _id}, socket), do: {:noreply, load(socket)}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_player={@current_player} active={:browse}>
      <div class="flex flex-col h-[calc(100vh-150px)]">
        <!-- Header (messenger style) -->
        <div class="flex items-center gap-3 pb-3 border-b border-[var(--fu-line)]">
          <.link
            navigate={~p"/browse"}
            aria-label="Back to queues"
            class="fu-ink-soft text-lg leading-none"
          >
            <span aria-hidden="true">←</span>
          </.link>
          <div class="size-9 rounded-full bg-base-200 grid place-items-center fu-serif fu-ink-soft">
            {String.first(@queue.field.name)}
          </div>
          <div class="flex-1 min-w-0">
            <div class="text-h3 truncate">{@queue.field.name}</div>
            <div class="text-caption fu-ink-soft">
              {@members} in queue · {@queue.format}
            </div>
          </div>
        </div>

        <!-- Body: the roster hugs the left, top→down, until the composer -->
        <div class="flex flex-1 min-h-0 mt-3 gap-3">
          <aside class="w-32 sm:w-40 shrink-0 overflow-y-auto border-r border-[var(--fu-line)] pr-2">
            <div class="fu-divider">In queue</div>
            <div class="divide-y divide-[var(--fu-line)]">
              <div
                :for={m <- @queued}
                class={[
                  "flex items-center gap-2 py-2",
                  m.player_id == @current_player.id && "text-primary"
                ]}
              >
                <div class="size-7 rounded-full bg-base-200 border border-neutral grid place-items-center overflow-hidden shrink-0">
                  <Avatars.avatar player={m.player} size={26} />
                </div>
                <div class="min-w-0 flex-1">
                  <div class="text-xs truncate">
                    {m.player.display_name |> String.split() |> hd()}
                  </div>
                  <div class="text-[10px] font-mono fu-ink-soft">
                    {Fu.Accounts.sub_label(m.player, m.declared_position)}
                  </div>
                </div>
              </div>
            </div>
          </aside>

          <div class="flex-1 min-w-0 flex flex-col">
            <%= if @open? do %>
              <div
                id="chat-log"
                phx-hook="ChatScroll"
                class="flex-1 overflow-y-auto py-4 space-y-1 pr-1"
              >
                <div :if={@messages == []} class="text-center fu-serif fu-ink-soft text-meta py-8">
                  No messages yet — say hi 👋
                </div>
                <.bubble
                  :for={m <- @messages}
                  mine={m.player_id == @current_player.id}
                  author={m.player}
                  body={m.body}
                  at={m.inserted_at}
                />
              </div>
            <% else %>
              <div class="flex-1 grid place-items-center text-center fu-serif fu-ink-soft text-meta px-6">
                Chatroom opens once {QueueChat.min_members()}+ players have joined.<br />
                Currently {@members}.
              </div>
            <% end %>
          </div>
        </div>

        <!-- Composer: full width; the roster above stops at this input box -->
        <%= if @open? do %>
          <%= if @can_post? do %>
            <.form for={%{}} phx-submit="send" class="flex gap-2 pt-2 border-t border-[var(--fu-line)]">
              <input
                type="text"
                name="body"
                value={@body}
                placeholder="Message…"
                autocomplete="off"
                class="input input-bordered input-sm flex-1 bg-base-200 rounded-full"
              />
              <button class="btn btn-sm btn-primary btn-circle" type="submit" aria-label="Send">
                ➤
              </button>
            </.form>
          <% else %>
            <div class="pt-2 border-t border-[var(--fu-line)] flex items-center justify-between gap-3">
              <span class="text-meta fu-ink-soft">Join the queue to chat.</span>
              <button phx-click="join" class="btn btn-sm btn-primary">Join queue</button>
            </div>
          <% end %>
        <% end %>
      </div>
    </Layouts.app>
    """
  end

  attr :mine, :boolean, required: true
  attr :author, :map, required: true
  attr :body, :string, required: true
  attr :at, :any, required: true

  defp bubble(assigns) do
    ~H"""
    <div class={["flex items-end gap-2", @mine && "justify-end", !@mine && "justify-start"]}>
      <div
        :if={!@mine}
        class="size-8 rounded-full bg-base-200 border border-neutral grid place-items-center overflow-hidden shrink-0"
      >
        <Avatars.avatar player={@author} size={30} />
      </div>
      <div class={[
        "max-w-[72%] px-3 py-2 rounded-2xl text-sm leading-snug",
        @mine && "bg-primary text-primary-content rounded-br-sm",
        !@mine && "bg-base-200 border border-neutral rounded-bl-sm"
      ]}>
        <div :if={!@mine} class="text-[11px] font-mono text-secondary mb-0.5">
          {@author.display_name}
        </div>
        <div class="whitespace-pre-wrap break-words">{@body}</div>
        <div class={[
          "text-[10px] font-mono mt-1 text-right",
          @mine && "text-primary-content/60",
          !@mine && "fu-ink-dim"
        ]}>
          {Calendar.strftime(@at, "%H:%M")}
        </div>
      </div>
    </div>
    """
  end
end
