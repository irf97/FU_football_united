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
    assign(socket, cards: cards, joined: Queues.joined_queue_ids(player))
  end

  @impl true
  def handle_event("join", %{"id" => id}, socket) do
    q = Queues.get_queue!(id)

    case Queues.join(q, socket.assigns.current_player) do
      {:ok, m} ->
        {:noreply, socket |> put_flash(:info, "Joined as #{m.declared_position}.") |> reload()}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, join_error(reason))}
    end
  end

  def handle_event("leave", %{"id" => id}, socket) do
    q = Queues.get_queue!(id)

    case Queues.leave(q, socket.assigns.current_player) do
      :ok -> {:noreply, socket |> put_flash(:info, "Left the queue.") |> reload()}
      {:error, :locked} -> {:noreply, put_flash(socket, :error, "Locked — you're committed (spec §2.4).")}
      {:error, _} -> {:noreply, reload(socket)}
    end
  end

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
  defp join_error(other), do: "Couldn't join (#{other})."

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_player={@current_player} active={:browse}>
      <h1 class="fu-serif text-xl text-primary">Open queues</h1>

      <!-- Filter chips (spec §2.13 Surface 3) -->
      <div class="flex flex-wrap gap-2">
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
      <div class="flex flex-wrap gap-2">
        <.chip :for={f <- Positions.formats()} active={@fmt == f} click="format" val={%{"fmt" => f}}>
          {f}
        </.chip>
      </div>

      <div :if={@cards == []} class="fu-card p-6 text-center fu-ink-soft text-sm">
        No queues match. Loosen a filter, or check back — density compounds.
      </div>

      <.queue_card
        :for={c <- @cards}
        card={c}
        joined={MapSet.member?(@joined, c.queue.id)}
      />
    </Layouts.app>
    """
  end

  attr :card, :map, required: true
  attr :joined, :boolean, default: false

  defp queue_card(assigns) do
    ~H"""
    <div class="fu-card p-4 space-y-3">
      <div class="flex items-start justify-between">
        <div>
          <div class="font-semibold">{@card.field.name}</div>
          <div class="text-xs fu-ink-soft">
            {@card.field.operator_name}
            <span :if={@card.distance_km}>· {fmt_km(@card.distance_km)}</span>
          </div>
        </div>
        <span class={if @card.rated, do: "fu-badge-rated", else: "fu-badge-casual"}>
          {if @card.rated, do: "Rated", else: "Casual"}
        </span>
      </div>

      <div class="flex items-center justify-between text-sm">
        <span>{fmt_when(@card.scheduled_at)}</span>
        <span class="font-mono text-xs fu-ink-soft">
          {@card.format} · {@card.formation}
        </span>
      </div>

      <!-- Position-by-position fill (spec §2.2) -->
      <div class="flex flex-wrap gap-1.5">
        <span
          :for={pos <- ~w(GK DEF MID FWD)}
          class={[
            "pos-pill",
            fill_full?(@card.fill[pos]) && "full",
            !fill_full?(@card.fill[pos]) && "needs"
          ]}
        >
          {pos} {@card.fill[pos].filled}/{@card.fill[pos].capacity}
        </span>
      </div>

      <div class="flex items-center justify-between text-xs fu-ink-soft">
        <span :if={@card.avg_rank}>
          avg rank {:erlang.float_to_binary(@card.avg_rank, decimals: 0)}
        </span>
        <span :if={!@card.avg_rank}>no players yet</span>
        <span class={@card.locked && "text-warning"}>{lock_label(@card)}</span>
      </div>

      <%= cond do %>
        <% @joined and @card.locked -> %>
          <button class="btn btn-sm btn-block" disabled>
            Committed · in this match
          </button>
        <% @joined -> %>
          <button phx-click="leave" phx-value-id={@card.queue.id} class="btn btn-sm btn-block btn-outline btn-error">
            Leave queue
          </button>
        <% true -> %>
          <button phx-click="join" phx-value-id={@card.queue.id} class="btn btn-sm btn-block btn-primary">
            Join {if @card.locked, do: "(commit now)", else: "queue"}
          </button>
      <% end %>
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
        "px-3 py-1.5 rounded-full text-xs font-mono border transition",
        @active && "border-primary text-primary",
        !@active && "border-neutral fu-ink-soft"
      ]}
    >
      {render_slot(@inner_block)}
    </button>
    """
  end

  defp fill_full?(%{filled: f, capacity: c}), do: f >= c
  defp fill_full?(_), do: false

  defp fmt_km(km) when is_number(km), do: "#{:erlang.float_to_binary(km, decimals: 1)} km"
  defp fmt_km(_), do: ""

  defp fmt_when(dt) do
    today = Date.utc_today()
    d = DateTime.to_date(dt)
    t = Calendar.strftime(dt, "%H:%M")

    cond do
      d == today -> "Today #{t}"
      d == Date.add(today, 1) -> "Tomorrow #{t}"
      true -> Calendar.strftime(dt, "%a %d %b · %H:%M")
    end
  end

  defp lock_label(%{locked: true}), do: "● locked"

  defp lock_label(%{seconds_to_lock: s}) when s > 0 do
    h = div(s, 3600)
    m = div(rem(s, 3600), 60)
    "locks in #{h}h #{m}m"
  end

  defp lock_label(_), do: "locking now"
end
