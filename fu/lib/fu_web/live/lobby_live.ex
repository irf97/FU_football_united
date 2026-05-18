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

  ## --- lock-in (commitment) ---

  @impl true
  def handle_event("lock-in", _, socket) do
    case Fu.Queues.lock_in(socket.assigns.queue, socket.assigns.current_player) do
      {:ok, _} ->
        # lock_in already broadcasts {:queue_changed, id} on the queue topic
        # the lobby is subscribed to — teammates' counts refresh from that.
        {:noreply, socket |> put_flash(:info, "Locked in — you're committed.") |> reload()}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Couldn't lock in.")}
    end
  end

  def handle_event("bail", _, socket) do
    case Fu.Queues.leave(socket.assigns.queue, socket.assigns.current_player) do
      {:penalised, tier, until} ->
        label = if tier == :week, do: "1-week", else: "1-day"

        {:noreply,
         socket
         |> put_flash(
           :error,
           "You bailed after locking in — #{label} ban until #{Calendar.strftime(until, "%a %d %b %H:%M")}."
         )
         |> push_navigate(to: ~p"/browse")}

      :ok ->
        {:noreply, socket |> put_flash(:info, "Left the queue.") |> push_navigate(to: ~p"/browse")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Couldn't leave.")}
    end
  end

  ## --- captain ---

  def handle_event("claim-captain", _, socket) do
    case Lobby.claim_captain(socket.assigns.queue, socket.assigns.current_player) do
      {:ok, _m} ->
        Phoenix.PubSub.broadcast(Fu.PubSub, lobby_topic(socket.assigns.queue.id), :captain_changed)
        {:noreply, socket |> put_flash(:info, "You're captain.") |> reload()}

      {:error, :taken} ->
        {:noreply, socket |> put_flash(:error, "Captaincy already taken.") |> reload()}
    end
  end

  ## --- match completion (AUDIT #1) ---

  @impl true
  def handle_event("submit-result", %{"score_a" => a, "score_b" => b}, socket) do
    qid = socket.assigns.queue.id

    case Fu.Matches.submit_result(qid, to_int(a), to_int(b)) do
      {:ok, _result} ->
        Phoenix.PubSub.broadcast(Fu.PubSub, lobby_topic(qid), :queue_changed)
        {:noreply, push_navigate(socket, to: ~p"/postmatch/#{qid}")}

      {:error, :not_confirmed} ->
        {:noreply, put_flash(socket, :error, "Match isn't confirmed yet.")}
    end
  end

  defp to_int(s) do
    case Integer.parse(to_string(s)) do
      {n, _} when n >= 0 -> n
      _ -> 0
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

  defp avg_rank([]), do: 0

  defp avg_rank(members) do
    ranks = Enum.map(members, & &1.player.rank)
    round(Enum.sum(ranks) / length(ranks))
  end

  defp rank_str(rank), do: :erlang.float_to_binary(rank * 1.0, decimals: 0)

  defp mmss(seconds) when is_integer(seconds) and seconds >= 0 do
    "#{div(seconds, 60)}:#{String.pad_leading("#{rem(seconds, 60)}", 2, "0")}"
  end

  defp mmss(_), do: "0:00"

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_player={@current_player} active={:browse}>
      <!-- Match header (spec §2.5) -->
      <div class="fu-card p-5 space-y-3">
        <div class="flex items-start justify-between gap-3">
          <div>
            <h1 class="text-h1">{@queue.field.name}</h1>
            <div class="text-meta fu-ink-soft">{@queue.field.operator_name}</div>
          </div>
          <span class={if @queue.rated, do: "fu-badge-rated", else: "fu-badge-casual"}>
            {if @queue.rated, do: "Rated", else: "Casual"}
          </span>
        </div>
        <div class="flex items-center justify-between">
          <span class="text-body">{fmt_kickoff(@queue.scheduled_at)}</span>
          <span class="text-mono fu-ink-soft">{@queue.format} · {@queue.formation}</span>
        </div>
        <div :if={@my_membership} class="text-meta fu-ink-soft">
          You're on <span class="text-primary">Team {@my_membership.team}</span>
          at <span class="text-mono">{Fu.Accounts.sub_label(@my_membership.player, @my_membership.declared_position)}</span>.
        </div>
        <div class="flex items-center justify-between gap-3 pt-1">
          <span class="text-caption fu-ink-soft">
            🔒 {Fu.Queues.locked_count(@queue)} locked in
          </span>
          <div :if={@my_membership && @my_membership.locked_at} class="flex items-center gap-3">
            <span class="text-meta font-bold text-[var(--fu-accent)]">✓ You're locked in</span>
            <button
              phx-click="bail"
              data-confirm="Bail after locking in? You'll be banned — 1 day if it's >24h before kickoff, 1 week if within 24h."
              class="btn btn-xs btn-ghost text-[var(--fu-danger)]"
              title="Leaving now bans you"
            >
              Bail
            </button>
          </div>
          <button
            :if={@my_membership && is_nil(@my_membership.locked_at)}
            phx-click="lock-in"
            class="btn btn-primary btn-sm min-h-[44px]"
            title="Commit — leaving after this bans you"
          >
            🔒 Lock in
          </button>
        </div>
      </div>

      <!-- Confirmed → the match is live: everyone moves to the in-play
           surface (synced clock + captain pause, spec §2.7). -->
      <.link
        :if={@queue.state == "confirmed"}
        navigate={~p"/match/#{@queue.id}"}
        class="btn btn-primary w-full min-h-[44px]"
      >
        Enter live match →
      </.link>

      <!-- Captain-only: record the final score (AUDIT #1 — the in-app
           match-completion trigger). spec §2.5: the captain issues the
           post-match step. -->
      <.form
        :if={@my_membership && @my_membership.is_captain && @queue.state == "confirmed"}
        id="submit-result"
        for={%{}}
        phx-submit="submit-result"
        class="fu-card p-4 space-y-3"
      >
        <div class="fu-divider">Final score</div>
        <div class="flex items-center justify-center gap-3">
          <input
            type="number"
            name="score_a"
            min="0"
            value="0"
            aria-label="Team A score"
            class="input input-bordered w-20 text-center text-h2 bg-base-200 min-h-[44px]"
            required
          />
          <span class="fu-ink-soft">A&nbsp;–&nbsp;B</span>
          <input
            type="number"
            name="score_b"
            min="0"
            value="0"
            aria-label="Team B score"
            class="input input-bordered w-20 text-center text-h2 bg-base-200 min-h-[44px]"
            required
          />
        </div>
        <button type="submit" class="btn btn-primary w-full min-h-[44px]">
          End match & finalize ranks
        </button>
      </.form>

      <!-- FE06 — Captain claim widget (plan §7.4) -->
      <.captain_widget
        phase={@phase}
        remaining={@remaining}
        can_claim?={@can_claim?}
        rosters={@rosters}
      />

      <!-- FE07 — Position swap (incoming request, mutual consent step 2) -->
      <div :if={@incoming_swap} class="fu-sheet p-4 space-y-3">
        <div class="text-h3">Position swap request</div>
        <div class="border border-[var(--fu-line)] rounded-lg px-4 py-3 text-body">
          <span class="font-medium">{@incoming_swap.player.display_name}</span>
          <span class="text-meta fu-ink-soft">
            ({Fu.Accounts.sub_label(@incoming_swap.player, @incoming_swap.declared_position)})
          </span>
          wants to swap positions with you.
        </div>
        <div class="flex gap-2">
          <button phx-click="swap-accept" class="btn btn-primary flex-1">Accept</button>
          <button phx-click="swap-decline" class="btn btn-sm flex-1">Decline</button>
        </div>
      </div>

      <!-- FE05 — Roster (plan §7.3) -->
      <div class="space-y-3">
        <.roster
          team_label="A"
          members={@rosters["A"]}
          current_player={@current_player}
          my_team={@my_membership && @my_membership.team}
        />
        <div class="text-center fu-serif fu-ink-soft py-1">VS</div>
        <.roster
          team_label="B"
          members={@rosters["B"]}
          current_player={@current_player}
          my_team={@my_membership && @my_membership.team}
        />
      </div>

      <!-- FE08 — Lobby chat (spec §2.5, plan §7.6) -->
      <div class="fu-card p-4 space-y-4">
        <div class="flex gap-5 border-b border-[var(--fu-line)]">
          <button
            :for={{c, lbl} <- [{"team", "Team"}, {"match", "Match"}, {"group", "Group"}]}
            phx-click="chan"
            phx-value-c={c}
            class={[
              "pb-2 -mb-px text-meta transition",
              @chan == c && "text-base-content border-b border-[var(--fu-line-strong)]",
              @chan != c && "fu-ink-soft"
            ]}
          >
            {lbl}
          </button>
        </div>

        <div class="space-y-3 max-h-48 overflow-y-auto">
          <div :if={@messages[@chan] == []} class="fu-serif fu-ink-soft text-meta">
            No messages yet — say hello.
          </div>
          <div :for={m <- @messages[@chan]} class="space-y-0.5">
            <div class="flex items-baseline gap-2 text-meta fu-ink-soft">
              <span class="font-medium">{m.from}</span>
              <span class="text-mono">{Calendar.strftime(m.at, "%H:%M")}</span>
            </div>
            <div class="text-body">{m.body}</div>
          </div>
        </div>

        <form phx-submit="send" phx-change="draft" class="flex gap-2">
          <input
            type="text"
            name="body"
            value={@draft}
            autocomplete="off"
            placeholder={"Message #{@chan}…"}
            class="flex-1 bg-base-200 border border-[var(--fu-line)] rounded px-3 py-1.5 text-body"
          />
          <button type="submit" class="btn btn-primary btn-sm">Send</button>
        </form>
      </div>
    </Layouts.app>
    """
  end

  # FE06 — captain-claim states driven by the existing phase / can_claim? assigns.
  attr :phase, :atom, required: true
  attr :remaining, :integer, required: true
  attr :can_claim?, :boolean, required: true
  attr :rosters, :map, required: true

  defp captain_widget(assigns) do
    captains =
      assigns.rosters
      |> Map.values()
      |> List.flatten()
      |> Enum.filter(& &1.is_captain)

    assigns = assign(assigns, captains: captains)

    ~H"""
    <div class="fu-divider">CAPTAINCY · {phase_label(@phase)}</div>
    <%= cond do %>
      <% @captains != [] -> %>
        <!-- state (4) / (5): resolved -->
        <div class="fu-card p-4 space-y-2">
          <div :for={c <- @captains} class="flex items-center gap-2 text-body">
            <span class="text-primary" title="Captain">★</span>
            <span class="font-medium">{c.player.display_name}</span>
            <span class="text-meta fu-ink-soft">Team {c.team}</span>
            <span :if={@phase == :random} class="text-meta fu-ink-soft">
              · randomly assigned
            </span>
            <span :if={@phase != :random} class="text-meta fu-ink-soft">· ✓ claimed</span>
          </div>
        </div>
      <% @can_claim? -> %>
        <!-- state (2): open to me -->
        <div class="fu-card p-4 border border-primary space-y-2">
          <button phx-click="claim-captain" class="btn btn-primary w-full">
            Claim captain
          </button>
        </div>
      <% true -> %>
        <!-- state (1): not yet open to me -->
        <div class="fu-card p-4 border-2 border-dashed border-[var(--fu-line)] space-y-1">
          <div class="text-mono fu-ink-soft">
            Opens to you in {mmss(@remaining)}
          </div>
          <div class="text-meta fu-ink-dim">
            Captaincy resolves automatically by 4:00.
          </div>
        </div>
    <% end %>
    """
  end

  # FE05 — one team's roster card.
  attr :team_label, :string, required: true
  attr :members, :list, required: true
  attr :current_player, :map, required: true
  attr :my_team, :string, default: nil

  defp roster(assigns) do
    ~H"""
    <div class="fu-card divide-y divide-[var(--fu-line)]">
      <div class="fu-divider">
        TEAM {@team_label} · avg rank {avg_rank(@members)}
      </div>
      <div
        :for={m <- @members}
        class={[
          "flex items-center gap-3 px-4 py-3",
          m.player.id == @current_player.id &&
            "bg-[color-mix(in_oklab,var(--fu-accent)_8%,transparent)]"
        ]}
      >
        <span class="text-mono fu-ink-soft w-6 shrink-0">
          {m.player.jersey_number}
        </span>
        <div class="size-8 rounded-full overflow-hidden shrink-0">
          <FuWeb.Avatars.avatar player={m.player} size={32} />
        </div>
        <div class="flex-1 min-w-0">
          <div class="flex items-center gap-1.5">
            <span class="text-body font-medium truncate">
              {m.player.display_name}
            </span>
            <span :if={m.is_captain} class="text-primary" title="Captain">★</span>
            <span
              :if={m.player.id == @current_player.id}
              class="bg-primary text-primary-content text-caption px-1.5 rounded"
            >
              you
            </span>
          </div>
        </div>
        <span class="text-meta fu-ink-soft shrink-0">{Fu.Accounts.sub_label(m.player, m.declared_position)}</span>
        <span class={[
          "text-mono shrink-0",
          m.player.rank > 75 && "text-primary"
        ]}>
          {rank_str(m.player.rank)}
        </span>
        <button
          :if={
            @my_team && m.team == @my_team &&
              m.player.id != @current_player.id
          }
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
