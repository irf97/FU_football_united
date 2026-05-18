defmodule FuWeb.ProfileLive do
  @moduledoc "Surface 7: identity, position prefs, availability, history (spec §2.6, plan §10)."
  use FuWeb, :live_view

  alias Fu.{Accounts, Ranking}
  alias FuWeb.Avatars

  @days ~w(Mon Tue Wed Thu Fri Sat Sun)

  @impl true
  def mount(_params, _session, socket) do
    {:ok, load(socket)}
  end

  defp load(socket) do
    p = socket.assigns.current_player

    socket
    |> assign(:player, p)
    |> assign(:preview, p)
    |> assign(:days, @days)
    |> assign(:nations, Fu.Nations.names())
    |> assign(:legends, Avatars.legends())
    |> assign(:kits, Avatars.kits())
    |> assign(:form, to_form(Accounts.change_profile(p)))
    |> assign(:windows, Accounts.list_availability(p))
    |> assign(:history, Ranking.history(p.id))
  end

  @impl true
  def handle_event("preview", %{"player" => attrs}, socket) do
    p = socket.assigns.player

    preview = %{
      p
      | avatar_legend: attrs["avatar_legend"] || p.avatar_legend,
        avatar_kit: attrs["avatar_kit"] || p.avatar_kit,
        avatar_color: attrs["avatar_color"] || p.avatar_color,
        jersey_number: parse_int(attrs["jersey_number"], p.jersey_number)
    }

    {:noreply, assign(socket, preview: preview)}
  end

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
      <h1 class="text-h1">Profile</h1>

      <!-- Identity summary (player-card echo) -->
      <div class="fu-card p-5 flex items-center gap-4">
        <div class="size-14 rounded-full bg-base-200 ring-1 ring-[var(--fu-line-strong)] grid place-items-center overflow-hidden">
          <Avatars.avatar player={@preview} size={52} />
        </div>
        <div class="flex-1 min-w-0">
          <div :if={@player.nickname not in [nil, ""]} class="text-h3 font-bold truncate">
            {@player.nickname}
          </div>
          <div class={[
            "truncate",
            (@player.nickname not in [nil, ""] && "text-meta fu-ink-soft") || "text-h3"
          ]}>
            {@player.display_name}
          </div>
          <div class="text-meta">
            <span class="font-bold text-[var(--fu-accent)]">
              {Fu.Accounts.sub_label(@player, @player.primary_position)}
            </span>
            <span class="fu-ink-soft">
              · {(@player.secondary_position &&
                Fu.Accounts.sub_label(@player, @player.secondary_position)) || "—"}</span>
            <span :if={Fu.Accounts.age(@player)} class="fu-ink-soft">
              · {Fu.Accounts.age(@player)}
            </span>
            <span :if={@player.nation} class="fu-ink-soft">
              · {Fu.Nations.flag(@player.nation)} {@player.nation}
            </span>
          </div>
        </div>
        <div class="text-right">
          <div class="text-display leading-none">
            {:erlang.float_to_binary(@player.rank, decimals: 0)}
          </div>
          <div class="text-caption fu-ink-soft">rank</div>
        </div>
      </div>

      <.form for={@form} phx-submit="save" phx-change="preview" class="fu-card p-5 space-y-4">
        <div class="fu-divider">Avatar</div>
        <div class="flex flex-col items-center gap-3">
          <div class="size-32 rounded-2xl bg-base-200 ring-1 ring-[var(--fu-line-strong)] grid place-items-center overflow-hidden">
            <Avatars.avatar player={@preview} size={120} />
          </div>
          <div class="text-caption fu-ink-dim">live preview · tap to restyle</div>
        </div>

        <Avatars.picker
          name="player[avatar_legend]"
          label="Legend"
          options={@legends}
          selected={@preview.avatar_legend}
        >
          <:swatch :let={lg}>
            <span class="block size-full" style={"background:#{Avatars.legend_skin(lg)}"} />
          </:swatch>
        </Avatars.picker>

        <Avatars.picker
          name="player[avatar_kit]"
          label="Nation kit"
          options={@kits}
          selected={@preview.avatar_kit}
        >
          <:swatch :let={kt}>
            <span
              class="block size-full"
              style={"background:#{elem(Avatars.kit_colors(kt, @preview.avatar_color), 0)}"}
            />
          </:swatch>
        </Avatars.picker>

        <div class="flex items-center gap-3">
          <label class="text-meta fu-ink-soft">Jersey colour</label>
          <input
            type="color"
            name="player[avatar_color]"
            value={@preview.avatar_color}
            class="h-9 w-16 rounded border border-neutral bg-base-200"
          />
          <span class="text-caption fu-ink-dim">used when kit = Custom</span>
        </div>

        <div class="fu-divider">Identity</div>
        <.input
          field={@form[:nickname]}
          label="Display name (shown bold)"
          placeholder="e.g. The Wall — optional"
        />
        <.input field={@form[:display_name]} label="Full name" />
        <div class="grid grid-cols-2 gap-3">
          <.input field={@form[:birthdate]} type="date" label="Birthdate" />
          <.input
            field={@form[:nation]}
            type="select"
            label="Nation"
            options={[{"—", ""} | Enum.map(@nations, &{"#{Fu.Nations.flag(&1)} #{&1}", &1})]}
          />
        </div>
        <div class="grid grid-cols-2 gap-3">
          <.input field={@form[:jersey_number]} type="number" label="Jersey" />
          <.input field={@form[:queue_region_km]} type="number" label="Region (km)" />
        </div>
        <.input field={@form[:home_label]} label="Home area" />
        <div class="grid grid-cols-2 gap-3">
          <.input field={@form[:home_lat]} type="text" label="Home lat" />
          <.input field={@form[:home_lng]} type="text" label="Home lng" />
        </div>

        <div class="fu-divider">Position preferences</div>
        <p class="text-caption fu-ink-dim">
          Pick your preferred variant for each position. You swap which one
          you're playing on the home screen — it shows the variant you set here.
        </p>
        <div class="flex items-center justify-between gap-3">
          <span class="text-sm fu-ink-soft w-24">Goalkeeper</span>
          <span class="text-mono text-sm flex-1 text-right fu-ink-dim">GK · no variant</span>
        </div>
        <.sub_select label="Defender" main="DEF" name="player[def_sub]" selected={@player.def_sub} />
        <.sub_select label="Midfield" main="MID" name="player[mid_sub]" selected={@player.mid_sub} />
        <.sub_select label="Forward" main="FWD" name="player[fwd_sub]" selected={@player.fwd_sub} />
        <label class="flex items-center gap-2 text-meta">
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

      <!-- Availability (spec §2.6, plan §10.3) -->
      <div class="fu-card p-5 space-y-3">
        <div class="fu-divider">Availability</div>

        <div :if={@windows == []} class="fu-serif fu-ink-soft text-meta">
          No windows yet — add one so the auto-matcher can find you.
        </div>

        <div
          :for={w <- @windows}
          class="flex items-center justify-between text-meta border-b border-[var(--fu-line)] pb-2"
        >
          <span>
            <span class="text-mono fu-ink-soft">{window_label(w)}</span>
            · {Calendar.strftime(w.start_time, "%H:%M")}–{Calendar.strftime(w.end_time, "%H:%M")}
          </span>
          <button phx-click="del-window" phx-value-id={w.id} class="text-error text-caption">
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
          <input type="date" name="win[date]" class="input input-sm input-bordered bg-base-200" />
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

      <!-- Rank trajectory + history (plan §10.4) -->
      <div class="fu-card p-5 space-y-3">
        <div class="fu-divider">Rank trajectory</div>
        <%= case spark(@history) do %>
          <% {:ok, points, lo, hi} -> %>
            <svg viewBox="0 0 300 60" class="w-full h-16" preserveAspectRatio="none">
              <polyline
                points={points}
                fill="none"
                stroke="var(--fu-accent)"
                stroke-width="2"
                stroke-linejoin="round"
                stroke-linecap="round"
                vector-effect="non-scaling-stroke"
              />
            </svg>
            <div class="flex justify-between text-caption fu-ink-dim">
              <span>{lo}</span>
              <span>now {:erlang.float_to_binary(@player.rank, decimals: 1)}</span>
              <span>{hi}</span>
            </div>
          <% :none -> %>
            <div class="fu-serif fu-ink-soft text-meta">
              Play a rated match to start your trajectory.
            </div>
        <% end %>

        <div class="fu-divider">Matches</div>
        <div :if={@history == []} class="text-meta fu-ink-soft">No rank events yet.</div>
        <div
          :for={ev <- Enum.take(@history, 10)}
          class="flex items-center justify-between border-b border-[var(--fu-line)] py-2"
        >
          <span class="text-meta">{ev_label(ev)}</span>
          <span class="text-mono">
            <span class={delta_class(ev.delta)}>{signed(ev.delta)}</span>
            <span class="fu-ink-soft">
              → {:erlang.float_to_binary(ev.rank_after, decimals: 1)}
            </span>
          </span>
        </div>
      </div>

      <!-- Theme -->
      <div class="fu-card p-5 space-y-3">
        <div class="fu-divider">Theme</div>
        <div class="grid grid-cols-3 gap-2">
          <button
            :for={
              {val, label} <- [
                {"dark", "Dark"},
                {"midnight", "Midnight"},
                {"pitch", "Pitch"},
                {"light", "Daylight"},
                {"system", "System"}
              ]
            }
            type="button"
            phx-click={Phoenix.LiveView.JS.dispatch("phx:set-theme")}
            data-phx-theme={val}
            class="min-h-[44px] rounded-lg border border-[var(--fu-line)] text-meta transition-colors hover:border-[var(--fu-accent)] hover:text-[var(--fu-accent)]"
          >
            {label}
          </button>
        </div>
        <p class="text-caption fu-ink-dim">
          Applies instantly and is remembered on this device.
        </p>
      </div>

      <.link href={~p"/session"} method="delete" class="btn btn-ghost btn-sm w-full">
        Sign out
      </.link>
    </Layouts.app>
    """
  end

  ## components

  # Per-main default-sub picker (scoped to one main position's variants).
  # Display/preference only — matchmaking still uses the main position.
  attr :label, :string, required: true
  attr :main, :string, required: true
  attr :name, :string, required: true
  attr :selected, :string, default: nil

  defp sub_select(assigns) do
    ~H"""
    <div class="flex items-center gap-3">
      <span class="text-sm fu-ink-soft w-24 shrink-0">{@label}</span>
      <select
        name={@name}
        class="select select-sm select-bordered bg-base-200 flex-1 text-meta"
        aria-label={"#{@label} variant (optional)"}
      >
        <option value="" selected={@selected in [nil, ""]}>
          {@main} · no preference
        </option>
        <option
          :for={{abbr, name} <- Fu.Positions.subs_for(@main)}
          value={abbr}
          selected={abbr == @selected}
        >
          {name} ({abbr})
        </option>
      </select>
    </div>
    """
  end

  ## helpers

  defp parse_int(nil, default), do: default
  defp parse_int("", default), do: default

  defp parse_int(s, default) do
    case Integer.parse(s) do
      {n, _} -> n
      :error -> default
    end
  end

  defp window_label(%{kind: "recurring", weekday: wd}), do: Enum.at(@days, wd || 0)
  defp window_label(%{kind: "oneoff", date: d}), do: Calendar.strftime(d, "%d %b")
  defp window_label(_), do: "—"

  defp ev_label(%{kind: "match"} = ev), do: "Match · queue #{ev.queue_id || "—"}"
  defp ev_label(%{kind: k}), do: String.capitalize(to_string(k))

  defp signed(d) when is_number(d) and d >= 0, do: "+#{:erlang.float_to_binary(d / 1, decimals: 1)}"
  defp signed(d) when is_number(d), do: "−#{:erlang.float_to_binary(abs(d) / 1, decimals: 1)}"
  defp signed(_), do: "—"

  defp delta_class(d) when is_number(d) and d > 0, do: "text-primary"
  defp delta_class(d) when is_number(d) and d < 0, do: "text-[var(--fu-danger)]"
  defp delta_class(_), do: "fu-ink-soft"

  # Build an SVG polyline over rank_after, oldest→newest, scaled to 300×60.
  defp spark(history) do
    pts =
      history
      |> Enum.reverse()
      |> Enum.map(& &1.rank_after)
      |> Enum.filter(&is_number/1)

    case pts do
      [] ->
        :none

      [_one] ->
        :none

      vals ->
        lo = Enum.min(vals)
        hi = Enum.max(vals)
        span = max(hi - lo, 1.0)
        n = length(vals)

        points =
          vals
          |> Enum.with_index()
          |> Enum.map_join(" ", fn {v, i} ->
            x = i * 300 / (n - 1)
            y = 56 - (v - lo) / span * 52
            "#{Float.round(x, 1)},#{Float.round(y, 1)}"
          end)

        {:ok, points, round(lo), round(hi)}
    end
  end
end
