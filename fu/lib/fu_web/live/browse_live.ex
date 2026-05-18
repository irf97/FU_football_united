defmodule FuWeb.BrowseLive do
  @moduledoc "Surface 3: the multi-field, position-aware queue browser (spec §2.1, §2.13)."
  use FuWeb, :live_view

  alias Fu.{Queues, Positions}

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Queues.subscribe_all()
    {:ok, socket |> assign(filters: %{}, fmt: nil) |> reload()}
  end

  defp reload(socket) do
    player = socket.assigns.current_player
    cards = Queues.browse(player, socket.assigns.filters)
    assign(socket,
      cards: cards,
      joined: Queues.joined_queue_ids(player),
      locked: Queues.locked_queue_ids(player)
    )
  end

  @impl true
  def handle_event("join", %{"id" => id}, socket) do
    q = Queues.get_queue!(id)

    case Queues.join(q, socket.assigns.current_player) do
      {:ok, m} ->
        {:noreply,
         socket
         |> put_flash(
           :info,
           "Joined as #{Fu.Accounts.sub_label(socket.assigns.current_player, m.declared_position)}."
         )
         |> reload()}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, join_error(reason))}
    end
  end

  def handle_event("lock", %{"id" => id}, socket) do
    q = Queues.get_queue!(id)

    case Queues.lock_in(q, socket.assigns.current_player) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Locked in — you're committed to this match.")
         |> reload()}

      {:error, _} ->
        {:noreply, socket |> put_flash(:error, "Couldn't lock in.") |> reload()}
    end
  end

  def handle_event("leave", %{"id" => id}, socket) do
    q = Queues.get_queue!(id)

    case Queues.leave(q, socket.assigns.current_player) do
      :ok ->
        {:noreply, socket |> put_flash(:info, "Left the queue.") |> reload()}

      {:penalised, tier, until} ->
        {:noreply,
         socket
         |> put_flash(:error, "You bailed after locking in — #{ban_label(tier)} ban (until #{fmt_until(until)}).")
         |> reload()}

      {:error, _} ->
        {:noreply, reload(socket)}
    end
  end

  defp ban_label(:day), do: "1-day"
  defp ban_label(:week), do: "1-week"
  defp fmt_until(dt), do: Calendar.strftime(dt, "%a %d %b %H:%M")

  @impl true
  def handle_event("toggle", %{"key" => key}, socket) do
    k = String.to_existing_atom(key)
    filters = Map.update(socket.assigns.filters, k, true, fn v -> !v end)
    filters = if filters[k] == false, do: Map.delete(filters, k), else: filters
    {:noreply, socket |> assign(filters: filters) |> reload()}
  end

  def handle_event("time", %{"window" => w}, socket) do
    filters =
      if socket.assigns.filters[:time] == w,
        do: Map.delete(socket.assigns.filters, :time),
        else: Map.put(socket.assigns.filters, :time, w)

    {:noreply, socket |> assign(filters: filters) |> reload()}
  end

  def handle_event("format", %{"fmt" => fmt}, socket) do
    {sel, filters} =
      if socket.assigns.fmt == fmt,
        do: {nil, Map.delete(socket.assigns.filters, :format)},
        else: {fmt, Map.put(socket.assigns.filters, :format, fmt)}

    {:noreply, socket |> assign(fmt: sel, filters: filters) |> reload()}
  end

  @impl true
  def handle_info({:queue_changed, _id}, socket), do: {:noreply, reload(socket)}

  defp join_error(:no_slot), do: "No open slot for your positions here."
  defp join_error(:already_joined), do: "You're already in this queue."
  defp join_error(:queue_closed), do: "This queue is no longer open."
  defp join_error(:suspended), do: "You're on a queue suspension."
  defp join_error(reason) when is_atom(reason), do: "Couldn't join (#{reason})."
  # Never interpolate a non-atom (e.g. an Ecto.Changeset) — that raised
  # Protocol.UndefinedError and crashed the LiveView.
  defp join_error(_), do: "Couldn't join — please try again."

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_player={@current_player} active={:browse}>
      <h1 class="text-h1">Open queues</h1>

      <!-- Filter chips (spec §2.13 Surface 3, plan §6.5) -->
      <div class="flex overflow-x-auto gap-2 -mx-1 px-1 py-1">
        <.chip active={@filters[:time] == "today"} click="time" val={%{"window" => "today"}}>
          Today
        </.chip>
        <.chip active={@filters[:time] == "week"} click="time" val={%{"window" => "week"}}>
          This week
        </.chip>
        <.chip active={@filters[:time] == "weekend"} click="time" val={%{"window" => "weekend"}}>
          Weekend
        </.chip>
        <.chip active={@filters[:needs_my_position]} click="toggle" val={%{"key" => "needs_my_position"}}>
          Needs my position
        </.chip>
        <.chip active={@filters[:rated_only]} click="toggle" val={%{"key" => "rated_only"}}>
          Rated only
        </.chip>
      </div>
      <div class="flex overflow-x-auto gap-2 -mx-1 px-1 py-1">
        <.chip :for={f <- Positions.formats()} active={@fmt == f} click="format" val={%{"fmt" => f}}>
          {f}
        </.chip>
      </div>

      <div :if={@cards == []} class="fu-card p-8 text-center space-y-4">
        <p class="fu-serif text-h3">
          no queues yet — set your availability and we'll find you a match.
        </p>
        <.link navigate={~p"/profile"} class="btn btn-primary btn-sm">
          Set availability
        </.link>
      </div>

      <.queue_card
        :for={c <- @cards}
        card={c}
        joined={MapSet.member?(@joined, c.queue.id)}
        locked={MapSet.member?(@locked, c.queue.id)}
      />
    </Layouts.app>
    """
  end

  attr :card, :map, required: true
  attr :joined, :boolean, default: false
  attr :locked, :boolean, default: false

  defp queue_card(assigns) do
    ~H"""
    <div class="fu-card p-5 rounded-2xl space-y-4 transition-colors hover:border-strong">
      <!-- Meta row (plan §6.3) -->
      <div class="flex items-center gap-2 text-caption">
        <span>{time_bucket(@card.scheduled_at)}</span>
        <span class="fu-ink-dim">·</span>
        <span class={if @card.rated, do: "fu-badge-rated", else: "fu-badge-casual"}>
          {if @card.rated, do: "RATED", else: "CASUAL"}
        </span>
        <span class="ml-auto text-base-content font-bold tabular-nums">
          <span :if={@card.avg_rank}>
            ★ {:erlang.float_to_binary(@card.avg_rank, decimals: 0)} ·
          </span>
          {fill_totals(@card.fill)} players
        </span>
      </div>

      <!-- Who's in & what they play (no avatars) -->
      <div
        :if={queued_in(@card) != []}
        class="flex flex-wrap gap-x-3 gap-y-1.5 text-caption fu-ink-soft -mt-2"
      >
        <span :for={m <- queued_in(@card)} class="inline-flex items-center gap-1">
          <span class={["pos-pill", m.locked_at && "full"]}>
            {Fu.Accounts.sub_label(m.player, m.declared_position)}
          </span>
          <span class="truncate max-w-[6rem]">
            {m.player.display_name |> String.split() |> hd()}
          </span>
        </span>
      </div>

      <div :if={queued_in(@card) != []} class="text-caption fu-ink-soft -mt-1">
        🔒 {Queues.locked_count(@card.queue)} locked in — match is on once every slot is locked
      </div>

      <div>
        <div class="text-h3">{@card.field.name}</div>
        <div class="text-meta fu-ink-soft">
          {@card.field.operator_name}<span :if={@card.distance_km}> · {fmt_km(@card.distance_km)} away</span>
        </div>
      </div>

      <!-- Position-by-position fill (spec §2.2, plan §6.4) -->
      <.position_fill fill={@card.fill} />

      <div class="flex items-center justify-between gap-3">
        <span class={["text-mono", lock_class(@card)]}>{lock_label(@card)}</span>

        <div class="flex items-center gap-2">
          <%= if @joined do %>
            <.link
              navigate={~p"/queue/#{@card.queue.id}/chat"}
              class="btn btn-sm btn-outline border-neutral"
              aria-label="Open queue chatroom"
            >
              💬 Chat
            </.link>
          <% else %>
            <button
              type="button"
              disabled
              title="Join the queue to unlock the chatroom"
              class="btn btn-sm btn-outline border-[var(--fu-line)] fu-ink-dim opacity-40 cursor-not-allowed"
            >
              💬 Chat
            </button>
          <% end %>

          <%= cond do %>
            <% @locked -> %>
              <span class="text-meta font-bold text-[var(--fu-accent)] px-2">✓ Locked in</span>
              <button
                phx-click="leave"
                phx-value-id={@card.queue.id}
                data-confirm="Bail after locking in? You'll be banned — 1 day if it's >24h before kickoff, 1 week if within 24h."
                class="btn btn-sm btn-ghost text-[var(--fu-danger)]"
                title="Leaving now bans you"
              >
                Bail
              </button>
              <.link
                navigate={~p"/lobby/#{@card.queue.id}"}
                class="btn btn-primary btn-sm"
              >
                Lobby →
              </.link>
            <% @joined and @card.locked -> %>
              <button
                phx-click="lock"
                phx-value-id={@card.queue.id}
                class="btn btn-primary btn-sm"
                title="Commit — leaving after this bans you"
              >
                🔒 Lock in
              </button>
            <% @joined -> %>
              <button
                phx-click="lock"
                phx-value-id={@card.queue.id}
                class="btn btn-primary btn-sm"
                title="Commit — leaving after this bans you"
              >
                🔒 Lock in
              </button>
              <button
                phx-click="leave"
                phx-value-id={@card.queue.id}
                class="btn btn-sm btn-outline border-neutral fu-ink-soft"
              >
                Leave
              </button>
            <% true -> %>
              <button phx-click="join" phx-value-id={@card.queue.id} class="btn btn-primary btn-sm">
                Join
              </button>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  attr :fill, :map, required: true

  defp position_fill(assigns) do
    ~H"""
    <div class="space-y-1.5">
      <div :for={pos <- ~w(GK DEF MID FWD)} class="flex items-center gap-3">
        <span class="text-mono fu-ink-soft w-10">{pos}</span>
        <span class={["text-mono w-12", fill_count_class(@fill[pos])]}>
          {@fill[pos].filled}/{@fill[pos].capacity}
        </span>
        <div class="flex gap-1">
          <span
            :for={i <- 1..@fill[pos].capacity}
            class={["slot-cell", i <= @fill[pos].filled && "on"]}
          />
        </div>
      </div>
    </div>
    """
  end

  attr :active, :boolean, default: false
  attr :click, :string, required: true
  attr :val, :map, required: true
  slot :inner_block, required: true

  defp chip(assigns) do
    ~H"""
    <button
      phx-click={@click}
      {Map.new(@val, fn {k, v} -> {"phx-value-#{k}", v} end)}
      class={[
        "rounded-full px-4 py-1.5 text-meta whitespace-nowrap transition-colors",
        @active && "bg-base-content text-base-300",
        !@active && "border border-neutral fu-ink-soft"
      ]}
    >
      {render_slot(@inner_block)}
    </button>
    """
  end

  defp fill_count_class(%{filled: f, capacity: c}) when f >= c, do: "fu-ink-dim"
  defp fill_count_class(_), do: "text-warning"

  defp fill_totals(fill) do
    {filled, total} =
      fill
      |> Map.values()
      |> Enum.reduce({0, 0}, fn %{filled: f, capacity: c}, {af, at} -> {af + f, at + c} end)

    "#{filled}/#{total}"
  end

  # Queued members of a card (player preloaded by Queues.browse), join order.
  defp queued_in(card) do
    card.queue.memberships
    |> Enum.filter(&(&1.status == "queued"))
    |> Enum.sort_by(& &1.id)
  end

  defp lock_class(%{locked: true}), do: "text-warning"

  defp lock_class(%{seconds_to_lock: s}) when is_integer(s) and s > 0 and s < 10_800,
    do: "text-warning"

  defp lock_class(_), do: "fu-ink-soft"

  defp time_bucket(dt) do
    Calendar.strftime(dt, "%a %d %b · %H:%M") |> String.upcase()
  end

  defp fmt_km(km) when is_number(km), do: "#{:erlang.float_to_binary(km, decimals: 1)} km"
  defp fmt_km(_), do: ""

  defp lock_label(%{locked: true}), do: "● locked"

  defp lock_label(%{seconds_to_lock: s}) when s > 0 do
    h = div(s, 3600)
    m = div(rem(s, 3600), 60)
    "locks in #{h}h #{m}m"
  end

  defp lock_label(_), do: "locking now"
end
