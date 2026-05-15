defmodule FuWeb.HomeLive do
  @moduledoc """
  Surface 2: the load-bearing home page (spec §2.13). Answers "can I play
  soon, and what does my card look like?" in under 3 seconds.
  """
  use FuWeb, :live_view

  alias Fu.{Accounts, Queues, Positions}

  @impl true
  def mount(_params, _session, socket) do
    {:ok, load(socket)}
  end

  defp load(socket) do
    player = socket.assigns.current_player
    cards = Queues.browse(player)
    needing = Enum.count(cards, & &1.needs_my_position)
    assign(socket, player: player, queue_count: length(cards), needing: needing)
  end

  @impl true
  def handle_event("set-pos", %{"slot" => slot, "pos" => pos}, socket) do
    attrs =
      case slot do
        "primary" -> %{"primary_position" => pos}
        "secondary" -> %{"secondary_position" => pos}
      end

    case Accounts.update_profile(socket.assigns.player, attrs) do
      {:ok, p} -> {:noreply, load(assign(socket, current_player: p))}
      {:error, _} -> {:noreply, put_flash(socket, :error, "Couldn't change position.")}
    end
  end

  def handle_event("toggle-fill", _, socket) do
    p = socket.assigns.player
    {:ok, p} = Accounts.update_profile(p, %{"fill_mode" => !p.fill_mode})
    {:noreply, load(assign(socket, current_player: p))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_player={@player} active={:home}>
      <!-- Player card -->
      <div class="fu-card p-5">
        <div class="flex items-center gap-4">
          <div class="size-14 rounded-full bg-base-200 border border-neutral grid place-items-center text-xl fu-serif text-primary">
            {String.first(@player.display_name)}
          </div>
          <div class="flex-1">
            <div class="font-semibold">{@player.display_name}</div>
            <div class="text-xs fu-ink-soft font-mono">
              {@player.primary_position} · {@player.secondary_position || "—"}
              {if @player.fill_mode, do: " · fill"}
            </div>
          </div>
          <div class="text-right">
            <div class="text-3xl font-semibold text-primary leading-none">
              {:erlang.float_to_binary(@player.rank, decimals: 0)}
            </div>
            <div class="text-[10px] fu-ink-dim font-mono uppercase tracking-wider">rank</div>
          </div>
        </div>
      </div>

      <!-- Queue button (primary action) -->
      <.link
        navigate={~p"/browse"}
        class="block fu-card p-5 text-center border-primary/40 hover:border-primary transition"
      >
        <div class="text-lg font-semibold text-primary">Find a match</div>
        <div class="text-sm fu-ink-soft mt-1">
          <%= cond do %>
            <% @needing > 0 -> %>
              {@needing} {if @needing == 1, do: "queue needs", else: "queues need"} your spot
            <% @queue_count > 0 -> %>
              {@queue_count} open {if @queue_count == 1, do: "queue", else: "queues"} nearby
            <% true -> %>
              no open queues — check back soon
          <% end %>
        </div>
      </.link>

      <!-- Position quick-edit -->
      <div class="fu-card p-4 space-y-3">
        <div class="text-xs fu-ink-dim font-mono uppercase tracking-wider">Position</div>
        <.pos_row
          label="Primary"
          slot="primary"
          current={@player.primary_position}
          disabled={[]}
        />
        <.pos_row
          label="Secondary"
          slot="secondary"
          current={@player.secondary_position}
          disabled={[@player.primary_position]}
        />
        <button
          phx-click="toggle-fill"
          class={["btn btn-sm w-full", @player.fill_mode && "btn-primary", !@player.fill_mode && "btn-outline"]}
        >
          Fill mode {if @player.fill_mode, do: "on", else: "off"}
          <span class="fu-ink-soft text-xs">· primary + any open position</span>
        </button>
      </div>

      <!-- Friends row (Phase 2 placeholder, spec §2.12) -->
      <div class="fu-card p-4">
        <div class="text-xs fu-ink-dim font-mono uppercase tracking-wider mb-1">Friends</div>
        <div class="text-sm fu-ink-soft">Group queuing arrives in the next slice.</div>
      </div>

      <!-- Recent matches (Phase 4 placeholder, spec §2.13) -->
      <div class="fu-card p-4">
        <div class="text-xs fu-ink-dim font-mono uppercase tracking-wider mb-1">Recent matches</div>
        <div class="text-sm fu-ink-soft">No matches played yet.</div>
      </div>
    </Layouts.app>
    """
  end

  attr :label, :string, required: true
  attr :slot, :string, required: true
  attr :current, :string, default: nil
  attr :disabled, :list, default: []

  defp pos_row(assigns) do
    assigns = assign(assigns, :positions, Positions.positions())

    ~H"""
    <div class="flex items-center gap-2">
      <span class="text-sm fu-ink-soft w-20">{@label}</span>
      <div class="flex gap-1 flex-1">
        <button
          :for={pos <- @positions}
          phx-click="set-pos"
          phx-value-slot={@slot}
          phx-value-pos={pos}
          disabled={pos in @disabled}
          class={[
            "pos-pill flex-1",
            pos == @current && "full",
            pos in @disabled && "opacity-30"
          ]}
        >
          {pos}
        </button>
      </div>
    </div>
    """
  end
end
