defmodule FuWeb.MatchmakingLive do
  @moduledoc """
  Auto-queue (spec §2.6). The player presses QUEUE and we actively hunt:
  a running timer plus a live list of "pops" — queues that fit them right
  now. Several can appear; the player Accepts one (joins it) or stops.
  """
  use FuWeb, :live_view

  alias Fu.{Matching, Queues}

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Queues.subscribe_all()
      :timer.send_interval(1000, self(), :tick)
    end

    {:ok,
     socket
     |> assign(started_at: System.system_time(:second), now: System.system_time(:second))
     |> refresh()}
  end

  defp refresh(socket) do
    # ASAP: soonest kickoff first — "whatever is possible immediately".
    pops =
      socket.assigns.current_player
      |> Matching.pops()
      |> Enum.sort_by(&DateTime.to_unix(&1.scheduled_at))

    assign(socket, pops: pops)
  end

  @impl true
  def handle_info(:tick, socket),
    do: {:noreply, assign(socket, now: System.system_time(:second))}

  def handle_info({:queue_changed, _id}, socket), do: {:noreply, refresh(socket)}
  def handle_info(_msg, socket), do: {:noreply, socket}

  @impl true
  def handle_event("accept", %{"id" => id}, socket) do
    q = Queues.get_queue!(id)

    player = socket.assigns.current_player

    case Queues.join(q, player) do
      {:ok, m} ->
        # Accepting a pop IS locking in — it's a commitment.
        Queues.lock_in(q, player)
        pos = Fu.Accounts.sub_label(player, m.declared_position)

        {:noreply,
         socket
         |> put_flash(
           :info,
           "Locked in at #{q.field.name} as #{pos}. You're committed — see you there."
         )
         |> push_navigate(to: ~p"/browse")}

      {:error, _} ->
        {:noreply, socket |> put_flash(:error, "That match just filled — still looking.") |> refresh()}
    end
  end

  def handle_event("stop", _, socket), do: {:noreply, push_navigate(socket, to: ~p"/")}

  defp mmss(s) when is_integer(s) and s >= 0,
    do: "#{div(s, 60)}:#{String.pad_leading("#{rem(s, 60)}", 2, "0")}"

  defp mmss(_), do: "0:00"

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_player={@current_player} active={:home}>
      <div class="fu-card p-6 text-center space-y-3">
        <div class="flex items-center justify-center gap-2">
          <span class="size-2.5 rounded-full bg-[var(--fu-accent)] animate-pulse"></span>
          <span class="text-caption fu-ink-soft">SEARCHING FOR A MATCH</span>
        </div>
        <div class="text-display leading-none tabular-nums">{mmss(@now - @started_at)}</div>
        <p class="fu-serif fu-ink-soft">
          {if @pops == [],
            do: "Scanning nearby queues that fit you — hang tight.",
            else: "#{length(@pops)} match#{if length(@pops) == 1, do: "", else: "es"} found. Accept one."}
        </p>
        <button phx-click="stop" class="btn btn-outline btn-sm min-h-[44px] w-full">
          Stop searching
        </button>
      </div>

      <div :for={c <- @pops} class="fu-card p-5 space-y-3">
        <div class="flex items-center gap-2 text-caption">
          <span>{c.format}</span>
          <span class="fu-ink-dim">·</span>
          <span class={if c.rated, do: "fu-badge-rated", else: "fu-badge-casual"}>
            {if c.rated, do: "RATED", else: "CASUAL"}
          </span>
          <span class="ml-auto text-base-content font-bold tabular-nums">
            <span :if={c.avg_rank}>★ {:erlang.float_to_binary(c.avg_rank, decimals: 0)} ·</span>
            {fill_totals(c.fill)}
          </span>
        </div>

        <div>
          <div class="text-h3">{c.field.name}</div>
          <div class="text-meta fu-ink-soft">
            {c.field.operator_name}<span :if={c.distance_km}> · {fmt_km(c.distance_km)}</span>
          </div>
        </div>

        <div class="flex items-center justify-between gap-3">
          <span class="text-meta fu-ink-soft">
            You'd play
            <span class="font-bold text-[var(--fu-accent)]">
              {Queues.pick_position(c.queue, @current_player)}
            </span>
          </span>
          <button
            phx-click="accept"
            phx-value-id={c.queue.id}
            class="btn btn-primary btn-sm min-h-[44px]"
            title="Accepting locks you in — it's a commitment"
          >
            Accept &amp; lock in
          </button>
        </div>
      </div>
    </Layouts.app>
    """
  end

  defp fill_totals(fill) do
    {f, t} =
      fill
      |> Map.values()
      |> Enum.reduce({0, 0}, fn %{filled: a, capacity: c}, {af, at} -> {af + a, at + c} end)

    "#{f}/#{t} players"
  end

  defp fmt_km(km) when is_number(km), do: "#{:erlang.float_to_binary(km, decimals: 1)} km"
  defp fmt_km(_), do: ""
end
