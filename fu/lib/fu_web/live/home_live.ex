defmodule FuWeb.HomeLive do
  @moduledoc """
  Surface 2: the load-bearing home page (spec §2.13). Answers "can I play
  soon, and what does my card look like?" in under 3 seconds.
  """
  use FuWeb, :live_view

  alias Fu.{Accounts, Queues, Positions, Friends, Groups, Matching, Ranking}

  @impl true
  def mount(_params, _session, socket) do
    {:ok, load(socket)}
  end

  defp load(socket) do
    player = socket.assigns.current_player
    cards = Queues.browse(player)
    group = Groups.current_group(player)

    assign(socket,
      player: player,
      queue_count: length(cards),
      needing: Enum.count(cards, & &1.needs_my_position),
      suggestions: Matching.suggest(player),
      friends: Friends.list_friends(player),
      pending: Friends.pending_incoming(player),
      group: group,
      group_members: group && Groups.members(group),
      invite: Friends.invite_link(player),
      form: recent_form(player)
    )
  end

  # Last 5 rated matches as W/L/D, newest first — derived from the
  # rank-event outcome component (win +1.5 / draw +0.3 / loss −0.8).
  defp recent_form(player) do
    Ranking.history(player.id)
    |> Enum.filter(&(&1.kind == "match"))
    |> Enum.take(5)
    |> Enum.map(fn ev ->
      case ev.breakdown["outcome"] do
        o when is_number(o) and o >= 1.0 -> "W"
        o when is_number(o) and o <= -0.1 -> "L"
        _ -> "D"
      end
    end)
  end

  defp pad_form(form), do: form ++ List.duplicate("", max(5 - length(form), 0))

  @impl true
  def handle_event("accept-friend", %{"id" => id}, socket) do
    Friends.accept_friend(String.to_integer(id))
    {:noreply, load(socket)}
  end

  def handle_event("create-group", _, socket) do
    {:ok, _g} = Groups.create_group(socket.assigns.player)
    {:noreply, socket |> put_flash(:info, "Group created.") |> load()}
  end

  def handle_event("add-to-group", %{"id" => pid}, socket) do
    friend = Accounts.get_player!(String.to_integer(pid))

    case Groups.add_member(socket.assigns.group, friend) do
      {:ok, _} -> {:noreply, load(socket)}
      {:error, :group_full} -> {:noreply, put_flash(socket, :error, "Group is full (8 max).")}
      {:error, _} -> {:noreply, load(socket)}
    end
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
      <!-- Player card — the hero (frontend plan §5.3). Rank is NOT lime;
           lime is reserved for moments that land. -->
      <.link navigate={~p"/profile"} class="block fu-card p-6">
        <div class="flex items-start justify-between">
          <div>
            <div class="text-display leading-none">
              {:erlang.float_to_binary(@player.rank, decimals: 0)}
            </div>
            <div class="text-caption fu-ink-soft mt-1">rank</div>
          </div>
          <div class="size-14 rounded-full bg-base-200 ring-1 ring-[var(--fu-line-strong)] grid place-items-center overflow-hidden">
            <FuWeb.Avatars.avatar player={@player} size={52} />
          </div>
        </div>

        <div class="mt-5">
          <div class="text-h3">{@player.display_name}</div>
          <div class="text-meta fu-ink-soft">
            {@player.primary_position} · {@player.secondary_position || "—"}{if @player.fill_mode,
              do: " · fill"}
          </div>
        </div>

        <div class="flex gap-1.5 mt-4">
          <div
            :for={r <- pad_form(@form)}
            class={[
              "form-cell",
              r == "W" && "form-w",
              r == "L" && "form-l",
              r == "D" && "form-d",
              r == "" && "border border-[var(--fu-line)]"
            ]}
          >
            {r}
          </div>
        </div>

        <div class="fu-serif text-meta fu-ink-dim mt-5">
          Born to play · since {@player.inserted_at.year}
        </div>
      </.link>

      <!-- Queue button — the single most pressable thing (plan §5.4) -->
      <%= if @queue_count > 0 do %>
        <.link
          navigate={~p"/browse"}
          class="flex h-14 items-center justify-center rounded-xl bg-primary text-primary-content font-semibold text-base active:bg-primary/90"
        >
          ⚡ QUEUE — {if @needing > 0,
            do: "#{@needing} need your spot",
            else: "#{@queue_count} open nearby"}
        </.link>
      <% else %>
        <.link
          navigate={~p"/profile"}
          class="flex h-14 items-center justify-center rounded-xl bg-primary text-primary-content font-semibold text-base active:bg-primary/90"
        >
          ⚡ QUEUE — set availability
        </.link>
      <% end %>

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

      <!-- Auto-match suggestions (spec §2.6 — "can I play soon?") -->
      <div class="fu-card p-4">
        <div class="text-xs fu-ink-dim font-mono uppercase tracking-wider mb-2">
          Suggested for you
        </div>
        <div :if={@suggestions == []} class="text-sm fu-ink-soft">
          Add availability windows in your profile so we can match you.
        </div>
        <.link
          :for={c <- @suggestions}
          navigate={~p"/browse"}
          class="flex items-center justify-between py-2 border-b border-neutral last:border-0"
        >
          <span class="text-sm">{c.field.name}</span>
          <span class="text-xs fu-ink-soft font-mono">
            {c.format}{if c.needs_my_position, do: " · needs you"}
          </span>
        </.link>
      </div>

      <!-- Friends & group (spec §2.12) -->
      <div class="fu-card p-4 space-y-3">
        <div class="text-xs fu-ink-dim font-mono uppercase tracking-wider">Friends</div>

        <div :if={@pending != []} class="space-y-1">
          <div
            :for={f <- @pending}
            class="flex items-center justify-between text-sm"
          >
            <span>{f.requester.display_name} wants to connect</span>
            <button
              phx-click="accept-friend"
              phx-value-id={f.id}
              class="btn btn-xs btn-primary"
            >
              Accept
            </button>
          </div>
        </div>

        <div class="text-sm">
          <span :if={@friends == []} class="fu-ink-soft">No friends yet.</span>
          <span :if={@friends != []} class="fu-ink-soft">
            {@friends |> Enum.map(& &1.display_name) |> Enum.join(", ")}
          </span>
        </div>

        <div class="text-xs fu-ink-dim font-mono break-all">invite: {@invite}</div>

        <%= if @group do %>
          <div class="pt-2 border-t border-neutral space-y-2">
            <div class="text-sm">
              Group · {length(@group_members)}/8 —
              <span class="fu-serif fu-ink-soft">
                {Groups.expected_split(length(@group_members))}
              </span>
            </div>
            <div class="text-xs fu-ink-soft">
              {@group_members |> Enum.map(& &1.display_name) |> Enum.join(", ")}
            </div>
            <div :if={@friends != []} class="flex flex-wrap gap-1">
              <button
                :for={fr <- addable(@friends, @group_members)}
                phx-click="add-to-group"
                phx-value-id={fr.id}
                class="pos-pill needs"
              >
                + {fr.display_name}
              </button>
            </div>
          </div>
        <% else %>
          <button phx-click="create-group" class="btn btn-sm btn-outline w-full">
            Create a group to queue with friends
          </button>
        <% end %>
      </div>
    </Layouts.app>
    """
  end

  defp addable(friends, group_members) do
    member_ids = MapSet.new(group_members, & &1.id)
    Enum.reject(friends, &MapSet.member?(member_ids, &1.id))
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
