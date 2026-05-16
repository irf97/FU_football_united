defmodule FuWeb.AdminLive do
  @moduledoc "App-management dashboard: players, specs, avatars, live status."
  use FuWeb, :live_view

  alias Fu.Admin
  alias FuWeb.Avatars

  @impl true
  def mount(_params, _session, socket) do
    if socket.assigns.current_player.is_admin do
      {:ok, socket |> assign(filter: :all) |> load()}
    else
      {:ok,
       socket
       |> put_flash(:error, "Admins only.")
       |> redirect(to: ~p"/")}
    end
  end

  defp load(socket) do
    %{players: rows, stats: stats} = Admin.overview()
    assign(socket, rows: rows, stats: stats)
  end

  @impl true
  def handle_event("filter", %{"f" => f}, socket),
    do: {:noreply, assign(socket, filter: String.to_existing_atom(f))}

  def handle_event("toggle-suspend", %{"id" => id}, socket) do
    id |> Admin.get_player!() |> Admin.toggle_suspend()
    {:noreply, socket |> put_flash(:info, "Suspension toggled.") |> load()}
  end

  defp visible(rows, :all), do: rows
  defp visible(rows, f), do: Enum.filter(rows, &(&1.status == f))

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_player={@current_player} active={nil}>
      <h1 class="text-h1">Admin</h1>
      <div class="text-caption fu-ink-soft">app management · {@stats.total} players</div>

      <!-- Roll-up stats -->
      <div class="grid grid-cols-4 gap-2">
        <.stat label="Idle" n={@stats.idle} tone="fu-ink-soft" />
        <.stat label="In queue" n={@stats.in_queue} tone="text-base-content" />
        <.stat label="In match" n={@stats.in_match} tone="text-[var(--fu-warning)]" />
        <.stat label="Suspended" n={@stats.suspended} tone="text-[var(--fu-danger)]" />
      </div>

      <!-- Filter -->
      <div class="flex gap-2 overflow-x-auto">
        <.fchip f="all" cur={@filter} label="All" />
        <.fchip f="in_match" cur={@filter} label="In match" />
        <.fchip f="in_queue" cur={@filter} label="In queue" />
        <.fchip f="idle" cur={@filter} label="Idle" />
      </div>

      <div class="fu-divider">Players</div>

      <div :for={row <- visible(@rows, @filter)} class="fu-card p-3 flex items-center gap-3">
        <div class="size-11 rounded-full bg-base-200 ring-1 ring-[var(--fu-line)] grid place-items-center overflow-hidden shrink-0">
          <Avatars.avatar player={row.player} size={40} />
        </div>

        <div class="flex-1 min-w-0">
          <div class="flex items-center gap-2">
            <span class="text-h3 truncate">{row.player.display_name}</span>
            <span class="text-mono fu-ink-soft">#{row.player.jersey_number}</span>
          </div>
          <div class="text-caption fu-ink-soft truncate">
            {row.player.primary_position} · {row.player.secondary_position || "—"}
            · {row.player.playstyle || "no style"}{if row.player.fill_mode, do: " · fill"}
          </div>
        </div>

        <div class="text-right shrink-0">
          <div class="text-mono">{:erlang.float_to_binary(row.player.rank, decimals: 1)}</div>
          <.status_badge status={row.status} suspended={Fu.Accounts.suspended?(row.player)} />
        </div>

        <button
          phx-click="toggle-suspend"
          phx-value-id={row.player.id}
          class={[
            "text-caption px-2 py-1 rounded border shrink-0",
            Fu.Accounts.suspended?(row.player) && "border-[var(--fu-line)] fu-ink-soft",
            !Fu.Accounts.suspended?(row.player) && "border-[var(--fu-danger)] text-[var(--fu-danger)]"
          ]}
        >
          {if Fu.Accounts.suspended?(row.player), do: "Unsuspend", else: "Suspend"}
        </button>
      </div>

      <div :if={visible(@rows, @filter) == []} class="fu-serif fu-ink-soft text-meta text-center py-6">
        no players in this state.
      </div>
    </Layouts.app>
    """
  end

  attr :label, :string, required: true
  attr :n, :integer, required: true
  attr :tone, :string, required: true

  defp stat(assigns) do
    ~H"""
    <div class="fu-card p-3 text-center">
      <div class={["text-h2", @tone]}>{@n}</div>
      <div class="text-caption fu-ink-dim">{@label}</div>
    </div>
    """
  end

  attr :f, :string, required: true
  attr :cur, :atom, required: true
  attr :label, :string, required: true

  defp fchip(assigns) do
    ~H"""
    <button
      phx-click="filter"
      phx-value-f={@f}
      class={[
        "px-4 py-1.5 rounded-full text-meta border whitespace-nowrap",
        to_string(@cur) == @f && "bg-base-content text-base-300 border-transparent",
        to_string(@cur) != @f && "border-[var(--fu-line)] fu-ink-soft"
      ]}
    >
      {@label}
    </button>
    """
  end

  attr :status, :atom, required: true
  attr :suspended, :boolean, default: false

  defp status_badge(assigns) do
    ~H"""
    <span class={[
      "text-caption inline-flex items-center gap-1",
      @suspended && "text-[var(--fu-danger)]",
      !@suspended && @status == :in_match && "text-[var(--fu-warning)]",
      !@suspended && @status == :in_queue && "text-base-content",
      !@suspended && @status == :idle && "fu-ink-soft"
    ]}>
      <span class="size-1.5 rounded-full bg-current" aria-hidden="true" />
      {cond do
        @suspended -> "suspended"
        @status == :in_match -> "in match"
        @status == :in_queue -> "in queue"
        true -> "idle"
      end}
    </span>
    """
  end
end
