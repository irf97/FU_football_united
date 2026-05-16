defmodule FuWeb.LobbyLive do
  @moduledoc """
  The game lobby (spec §2.5): rosters, ephemeral PubSub chat (team / match /
  group), mutual-consent position swaps, and the captain-claim sequence.
  """
  use FuWeb, :live_view

  alias Fu.{Queues, Balance, Lobby}

  @channels ~w(team match group)

  @impl true
  def mount(%{"queue_id" => qid}, _session, socket) do
    queue = Queues.get_queue!(qid)

    queue =
      if Enum.any?(queued(queue), &is_nil(&1.team)) do
        {:ok, q} = Balance.assign_teams(queue)
        q
      else
        queue
      end

    if connected?(socket) do
      Queues.subscribe(queue.id)
      Phoenix.PubSub.subscribe(Fu.PubSub, lobby_topic(queue.id))
      :timer.send_interval(1000, self(), :tick)
    end

    {:ok,
     socket
     |> assign(
       queue: queue,
       chan: "team",
       messages: %{"team" => [], "match" => [], "group" => []},
       draft: "",
       now: DateTime.utc_now(),
       incoming_swap: nil
     )
     |> assign_lobby()}
  end

  defp assign_lobby(socket) do
    queue = socket.assigns.queue
    player = socket.assigns.current_player
    rosters = Balance.rosters(queue)
    {phase, remaining} = Lobby.claim_phase(queue, socket.assigns.now)

    me = Enum.find(queued(queue), &(&1.player_id == player.id))

    assign(socket,
      rosters: rosters,
      phase: phase,
      remaining: remaining,
      my_membership: me,
      can_claim?: Lobby.eligible_to_claim?(queue, player, phase)
    )
  end

  defp reload(socket) do
    socket
    |> assign(queue: Queues.get_queue!(socket.assigns.queue.id))
    |> assign_lobby()
  end

  ## --- ticking clock + captain random fallback ---

  @impl true
  def handle_info(:tick, socket) do
    socket = assign(socket, now: DateTime.utc_now())
    {phase, _} = Lobby.claim_phase(socket.assigns.queue, socket.assigns.now)

    if phase == :random and uncaptained_team?(socket.assigns.queue) do
      Lobby.random_assign(socket.assigns.queue)
      Phoenix.PubSub.broadcast(Fu.PubSub, lobby_topic(socket.assigns.queue.id), :captain_changed)
      {:noreply, reload(socket)}
    else
      {:noreply, assign_lobby(socket)}
    end
  end

  def handle_info({:queue_changed, _id}, socket), do: {:noreply, reload(socket)}
  def handle_info(:captain_changed, socket), do: {:noreply, reload(socket)}

  def handle_info({:chat, chan, msg}, socket) do
    msgs = Map.update(socket.assigns.messages, chan, [msg], &(&1 ++ [msg]))
    {:noreply, assign(socket, messages: msgs)}
  end

  def handle_info({:swap_request, from_m, to_player_id}, socket) do
    if socket.assigns.current_player.id == to_player_id do
      {:noreply, assign(socket, incoming_swap: from_m)}
    else
      {:noreply, socket}
    end
  end

  def handle_info(:swap_done, socket), do: {:noreply, reload(socket)}

  ## --- captain ---

  @impl true
  def handle_event("claim-captain", _, socket) do
    case Lobby.claim_captain(socket.assigns.queue, socket.assigns.current_player) do
      {:ok, _m} ->
        Phoenix.PubSub.broadcast(Fu.PubSub, lobby_topic(socket.assigns.queue.id), :captain_changed)
        {:noreply, socket |> put_flash(:info, "You're captain.") |> reload()}

      {:error, :taken} ->
        {:noreply, socket |> put_flash(:error, "Captaincy already taken.") |> reload()}
    end
  end

  ## --- chat ---

  def handle_event("chan", %{"c" => c}, socket) when c in @channels,
    do: {:noreply, assign(socket, chan: c)}

  def handle_event("draft", %{"body" => body}, socket),
    do: {:noreply, assign(socket, draft: body)}

  def handle_event("send", %{"body" => body}, socket) do
    body = String.trim(body)

    if body == "" do
      {:noreply, socket}
    else
      msg = %{from: socket.assigns.current_player.display_name, body: body, at: DateTime.utc_now()}
      chan = socket.assigns.chan
      Phoenix.PubSub.broadcast(Fu.PubSub, lobby_topic(socket.assigns.queue.id), {:chat, chan, msg})
      {:noreply, assign(socket, draft: "")}
    end
  end

  ## --- swap (two-step mutual consent) ---

  def handle_event("swap-request", %{"id" => to_mid}, socket) do
    me = socket.assigns.my_membership
    target = Enum.find(queued(socket.assigns.queue), &(&1.id == String.to_integer(to_mid)))

    cond do
      is_nil(me) or is_nil(target) ->
        {:noreply, socket}

      me.team != target.team ->
        {:noreply, put_flash(socket, :error, "Can only swap within your team.")}

      true ->
        Phoenix.PubSub.broadcast(
          Fu.PubSub,
          lobby_topic(socket.assigns.queue.id),
          {:swap_request, me, target.player_id}
        )

        {:noreply, put_flash(socket, :info, "Swap request sent.")}
    end
  end

  def handle_event("swap-accept", _, socket) do
    from_m = socket.assigns.incoming_swap
    me = socket.assigns.my_membership

    case from_m && me && Lobby.swap_positions(from_m.id, me.id) do
      {:ok, _} ->
        Phoenix.PubSub.broadcast(Fu.PubSub, lobby_topic(socket.assigns.queue.id), :swap_done)
        {:noreply, socket |> assign(incoming_swap: nil) |> put_flash(:info, "Positions swapped.") |> reload()}

      _ ->
        {:noreply, socket |> assign(incoming_swap: nil) |> put_flash(:error, "Swap failed.")}
    end
  end

  def handle_event("swap-decline", _, socket),
    do: {:noreply, assign(socket, incoming_swap: nil)}

  ## --- helpers ---

  defp lobby_topic(qid), do: "lobby:#{qid}"
  defp queued(queue), do: Enum.filter(queue.memberships, &(&1.status == "queued"))
  defp uncaptained_team?(queue) do
    queued(queue)
    |> Enum.reject(&is_nil(&1.team))
    |> Enum.group_by(& &1.team)
    |> Enum.any?(fn {_t, ms} -> not Enum.any?(ms, & &1.is_captain) end)
  end

  defp phase_label(:keeper), do: "Keeper priority"
  defp phase_label(:ranked), do: "Top-ranked priority"
  defp phase_label(:free), do: "Open claim"
  defp phase_label(:random), do: "Random assignment"

  defp fmt_kickoff(dt) do
    today = Date.utc_today()
    d = DateTime.to_date(dt)
    t = Calendar.strftime(dt, "%H:%M")

    cond do
      d == today -> "Today #{t}"
      d == Date.add(today, 1) -> "Tomorrow #{t}"
      true -> Calendar.strftime(dt, "%a %d %b · %H:%M")
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_player={@current_player} active={:browse}>
      <!-- Match header (spec §2.5) -->
      <div class="fu-card p-5 space-y-2">
        <div class="flex items-start justify-between">
          <div>
            <h1 class="text-h1">{@queue.field.name}</h1>
            <div class="text-xs fu-ink-soft">{@queue.field.operator_name}</div>
          </div>
          <span class={if @queue.rated, do: "fu-badge-rated", else: "fu-badge-casual"}>
            {if @queue.rated, do: "Rated", else: "Casual"}
          </span>
        </div>
        <div class="flex items-center justify-between text-sm">
          <span>{fmt_kickoff(@queue.scheduled_at)}</span>
          <span class="font-mono text-xs fu-ink-soft">{@queue.format} · {@queue.formation}</span>
        </div>
        <div :if={@my_membership} class="text-sm fu-ink-soft">
          You're on <span class="text-primary">Team {@my_membership.team}</span>
          at <span class="font-mono">{@my_membership.declared_position}</span>.
        </div>
      </div>

      <!-- Captain claim (spec §2.5, §4 Q5) -->
      <div class="fu-card p-4 space-y-2">
        <div class="flex items-center justify-between">
          <span class="text-xs fu-ink-dim font-mono uppercase tracking-wider">
            Captaincy · {phase_label(@phase)}
          </span>
          <span :if={@phase != :random} class="font-mono text-xs fu-ink-soft">
            {@remaining}s to next window
          </span>
        </div>
        <button
          :if={@can_claim?}
          phx-click="claim-captain"
          class="btn btn-sm btn-primary w-full"
        >
          Claim captain
        </button>
        <div :if={!@can_claim?} class="text-xs fu-ink-soft">
          Not your window — captaincy resolves automatically by 4:00.
        </div>
      </div>

      <!-- Incoming swap request (mutual consent step 2) -->
      <div :if={@incoming_swap} class="fu-card p-4 border-primary/40 space-y-2">
        <div class="text-sm">
          <span class="text-primary">{@incoming_swap.player.display_name}</span>
          ({@incoming_swap.declared_position}) wants to swap positions with you.
        </div>
        <div class="flex gap-2">
          <button phx-click="swap-accept" class="btn btn-xs btn-primary">Accept</button>
          <button phx-click="swap-decline" class="btn btn-xs btn-outline">Decline</button>
        </div>
      </div>

      <!-- Two team rosters -->
      <div class="grid grid-cols-2 gap-3">
        <.roster
          :for={team <- ["A", "B"]}
          team={team}
          members={@rosters[team]}
          me={@my_membership}
        />
      </div>

      <!-- Lobby chat (spec §2.5) -->
      <div class="fu-card p-4 space-y-3">
        <div class="flex gap-2">
          <button
            :for={{c, lbl} <- [{"team", "Team"}, {"match", "Match"}, {"group", "Group"}]}
            phx-click="chan"
            phx-value-c={c}
            class={[
              "px-3 py-1.5 rounded-full text-xs font-mono border transition",
              @chan == c && "border-primary text-primary",
              @chan != c && "border-neutral fu-ink-soft"
            ]}
          >
            {lbl}
          </button>
        </div>

        <div class="space-y-1 max-h-48 overflow-y-auto">
          <div :if={@messages[@chan] == []} class="text-xs fu-ink-soft">
            No messages yet — say hello.
          </div>
          <div :for={m <- @messages[@chan]} class="text-sm">
            <span class="text-primary font-semibold">{m.from}</span>
            <span class="fu-ink-soft text-[10px] font-mono">
              {Calendar.strftime(m.at, "%H:%M")}
            </span>
            <div class="fu-ink-soft">{m.body}</div>
          </div>
        </div>

        <form phx-submit="send" phx-change="draft" class="flex gap-2">
          <input
            type="text"
            name="body"
            value={@draft}
            autocomplete="off"
            placeholder={"Message #{@chan}…"}
            class="flex-1 bg-base-200 border border-neutral rounded px-3 py-1.5 text-sm"
          />
          <button type="submit" class="btn btn-sm btn-primary">Send</button>
        </form>
      </div>
    </Layouts.app>
    """
  end

  attr :team, :string, required: true
  attr :members, :list, required: true
  attr :me, :map, default: nil

  defp roster(assigns) do
    ~H"""
    <div class="fu-card p-3 space-y-2">
      <div class="text-xs fu-ink-dim font-mono uppercase tracking-wider">
        Team {@team} · {length(@members)}
      </div>
      <div
        :for={m <- @members}
        class={[
          "flex items-center gap-2 py-1.5 px-1 rounded",
          @me && m.id == @me.id && "bg-base-200"
        ]}
      >
        <div class="size-8 rounded-full bg-base-200 border border-neutral grid place-items-center text-xs fu-serif fu-ink-soft shrink-0">
          {String.first(m.player.display_name)}
        </div>
        <div class="flex-1 min-w-0">
          <div class="text-sm truncate">
            {m.player.display_name}
            <span :if={m.is_captain} class="text-primary" title="Captain">ⓒ</span>
          </div>
          <div class="text-[10px] fu-ink-soft font-mono">
            #{m.player.jersey_number} · {m.declared_position} · {m.player.playstyle}
            · rank {:erlang.float_to_binary(m.player.rank, decimals: 0)}
          </div>
        </div>
        <button
          :if={@me && m.team == @me.team && m.id != @me.id}
          phx-click="swap-request"
          phx-value-id={m.id}
          class="pos-pill needs shrink-0"
          title="Request a position swap"
        >
          swap
        </button>
      </div>
    </div>
    """
  end
end
