defmodule FuWeb.ProfileLive do
  @moduledoc "Surface 7: identity, position prefs, availability windows (spec §2.6, §2.13)."
  use FuWeb, :live_view

  alias Fu.Accounts

  @days ~w(Mon Tue Wed Thu Fri Sat Sun)
  @playstyles ~w(Aggressive Possession Counter Defensive Box-to-box Playmaker Finisher)

  @impl true
  def mount(_params, _session, socket) do
    {:ok, load(socket)}
  end

  defp load(socket) do
    p = socket.assigns.current_player

    socket
    |> assign(:player, p)
    |> assign(:days, @days)
    |> assign(:playstyles, @playstyles)
    |> assign(:form, to_form(Accounts.change_profile(p)))
    |> assign(:windows, Accounts.list_availability(p))
  end

  @impl true
  def handle_event("save", %{"player" => attrs}, socket) do
    case Accounts.update_profile(socket.assigns.player, attrs) do
      {:ok, p} ->
        {:noreply,
         socket
         |> assign(current_player: p)
         |> put_flash(:info, "Profile saved.")
         |> load()}

      {:error, cs} ->
        {:noreply, assign(socket, form: to_form(cs))}
    end
  end

  def handle_event("add-window", %{"win" => w}, socket) do
    case Accounts.add_availability(socket.assigns.player, w) do
      {:ok, _} -> {:noreply, socket |> put_flash(:info, "Availability added.") |> load()}
      {:error, _} -> {:noreply, put_flash(socket, :error, "Check the times/day.")}
    end
  end

  def handle_event("del-window", %{"id" => id}, socket) do
    Accounts.delete_availability(socket.assigns.player, String.to_integer(id))
    {:noreply, load(socket)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_player={@player} active={:profile}>
      <h1 class="fu-serif text-xl text-primary">Profile</h1>

      <.form for={@form} phx-submit="save" class="fu-card p-4 space-y-3">
        <div class="text-xs fu-ink-dim font-mono uppercase tracking-wider">Identity</div>
        <.input field={@form[:display_name]} label="Display name" />
        <div class="grid grid-cols-2 gap-3">
          <.input field={@form[:jersey_number]} type="number" label="Jersey" />
          <.input field={@form[:queue_region_km]} type="number" label="Region (km)" />
        </div>
        <.input field={@form[:home_label]} label="Home area" />
        <div class="grid grid-cols-2 gap-3">
          <.input field={@form[:home_lat]} type="text" label="Home lat" />
          <.input field={@form[:home_lng]} type="text" label="Home lng" />
        </div>

        <div class="text-xs fu-ink-dim font-mono uppercase tracking-wider pt-2">Play</div>
        <.input
          field={@form[:primary_position]}
          type="select"
          label="Primary"
          options={Fu.Positions.positions()}
        />
        <.input
          field={@form[:secondary_position]}
          type="select"
          label="Secondary"
          options={[{"—", ""} | Enum.map(Fu.Positions.positions(), &{&1, &1})]}
        />
        <.input
          field={@form[:playstyle]}
          type="select"
          label="Playstyle"
          options={[{"—", ""} | Enum.map(@playstyles, &{&1, &1})]}
        />
        <label class="flex items-center gap-2 text-sm">
          <input
            type="checkbox"
            name="player[fill_mode]"
            value="true"
            checked={@player.fill_mode}
            class="checkbox checkbox-sm"
          />
          Fill mode — primary + any open position
        </label>

        <button class="btn btn-primary w-full" type="submit">Save profile</button>
      </.form>

      <!-- Availability windows (spec §2.6) -->
      <div class="fu-card p-4 space-y-3">
        <div class="text-xs fu-ink-dim font-mono uppercase tracking-wider">Availability</div>

        <div :if={@windows == []} class="text-sm fu-ink-soft">
          No windows yet. Add one so the auto-matcher can find you.
        </div>

        <div
          :for={w <- @windows}
          class="flex items-center justify-between text-sm border-b border-neutral pb-2"
        >
          <span>
            {window_label(w)} · {Calendar.strftime(w.start_time, "%H:%M")}–{Calendar.strftime(
              w.end_time,
              "%H:%M"
            )}
          </span>
          <button phx-click="del-window" phx-value-id={w.id} class="text-error text-xs">
            remove
          </button>
        </div>

        <.form for={%{}} phx-submit="add-window" class="grid grid-cols-2 gap-2 pt-1">
          <select name="win[kind]" class="select select-sm select-bordered bg-base-200 col-span-2">
            <option value="recurring">Recurring weekly</option>
            <option value="oneoff">One-off date</option>
          </select>
          <select name="win[weekday]" class="select select-sm select-bordered bg-base-200">
            <option :for={{d, i} <- Enum.with_index(@days)} value={i}>{d}</option>
          </select>
          <input
            type="date"
            name="win[date]"
            class="input input-sm input-bordered bg-base-200"
          />
          <input
            type="time"
            name="win[start_time]"
            value="19:00"
            class="input input-sm input-bordered bg-base-200"
          />
          <input
            type="time"
            name="win[end_time]"
            value="22:00"
            class="input input-sm input-bordered bg-base-200"
          />
          <button class="btn btn-sm btn-outline col-span-2" type="submit">Add window</button>
        </.form>
      </div>

      <.link href={~p"/session"} method="delete" class="btn btn-ghost btn-sm w-full">
        Sign out
      </.link>
    </Layouts.app>
    """
  end

  defp window_label(%{kind: "recurring", weekday: wd}), do: Enum.at(@days, wd || 0)
  defp window_label(%{kind: "oneoff", date: d}), do: Calendar.strftime(d, "%d %b")
  defp window_label(_), do: "—"
end
