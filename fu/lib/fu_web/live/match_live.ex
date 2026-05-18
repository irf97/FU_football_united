defmodule FuWeb.MatchLive do
  @moduledoc """
  Surface: the live in-play match (spec §2.7, AUDIT #12). A synced clock,
  the running score, and captain-only controls — kick off, pause/resume,
  and the final whistle that completes the match and opens voting.

  The clock state lives on `MatchResult`; every control broadcasts on the
  match topic so all participants' screens stay in lock-step.
  """
  use FuWeb, :live_view

  alias Fu.{Queues, Balance, Matches}

  @impl true
  def mount(%{"queue_id" => qid}, _session, socket) do
    queue = Queues.get_queue!(qid)
    Matches.get_or_create_result(queue.id)

    if connected?(socket) do
      Queues.subscribe(queue.id)
      Phoenix.PubSub.subscribe(Fu.PubSub, topic(queue.id))
      :timer.send_interval(1000, self(), :tick)
    end

    {:ok, socket |> assign(queue: queue, now: now()) |> load()}
  end

  defp load(socket) do
    queue = Queues.get_queue!(socket.assigns.queue.id)
    player = socket.assigns.current_player
    me = Enum.find(queued(queue), &(&1.player_id == player.id))

    team = me && me.team

    assign(socket,
      queue: queue,
      result: Matches.result(queue.id),
      rosters: Balance.rosters(queue),
      me: me,
      captain?: !!(me && me.is_captain),
      team: team,
      tactics: team && Fu.Tactics.get(queue.id, team),
      formations: Fu.Tactics.formations(),
      styles: Fu.Tactics.styles()
    )
  end

  ## --- ticking + sync ---

  @impl true
  def handle_info(:tick, socket),
    do: {:noreply, assign(socket, now: now(), result: Matches.result(socket.assigns.queue.id))}

  def handle_info({:queue_changed, _id}, socket), do: {:noreply, load(socket)}
  def handle_info(:match_changed, socket), do: {:noreply, load(socket)}
  def handle_info(_msg, socket), do: {:noreply, socket}

  ## --- captain tactics ---

  @impl true
  def handle_event("save-tactics", %{"formation" => f, "style" => s} = p, socket) do
    attrs = %{"formation" => f, "style" => s, "notes" => Map.get(p, "notes", "")}

    case Fu.Tactics.set(socket.assigns.queue.id, socket.assigns.team, attrs, socket.assigns.current_player) do
      {:ok, _t} ->
        broadcast(socket)
        {:noreply, socket |> put_flash(:info, "Tactics updated.") |> load()}

      {:error, :not_captain} ->
        {:noreply, put_flash(socket, :error, "Only your captain can set tactics.")}

      {:error, _cs} ->
        {:noreply, put_flash(socket, :error, "Pick a formation and style from the list.")}
    end
  end

  ## --- captain controls ---

  def handle_event("kickoff", _, socket) do
    case Matches.kickoff(socket.assigns.queue.id) do
      {:ok, _} ->
        broadcast(socket)
        {:noreply, load(socket)}

      {:error, :not_confirmed} ->
        {:noreply, put_flash(socket, :error, "Match isn't confirmed yet.")}
    end
  end

  def handle_event("pause", _, socket) do
    Matches.pause(socket.assigns.queue.id)
    broadcast(socket)
    {:noreply, load(socket)}
  end

  def handle_event("resume", _, socket) do
    Matches.resume(socket.assigns.queue.id)
    broadcast(socket)
    {:noreply, load(socket)}
  end

  def handle_event("submit-result", %{"score_a" => a, "score_b" => b}, socket) do
    qid = socket.assigns.queue.id

    case Matches.submit_result(qid, to_int(a), to_int(b)) do
      {:ok, _result} ->
        Phoenix.PubSub.broadcast(Fu.PubSub, topic(qid), :match_changed)
        {:noreply, push_navigate(socket, to: ~p"/postmatch/#{qid}")}

      {:error, :not_confirmed} ->
        {:noreply, put_flash(socket, :error, "Match isn't confirmed yet.")}
    end
  end

  ## --- helpers ---

  defp topic(qid), do: "match:#{qid}"
  defp broadcast(socket), do: Phoenix.PubSub.broadcast(Fu.PubSub, topic(socket.assigns.queue.id), :match_changed)
  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)
  defp queued(queue), do: Enum.filter(queue.memberships, &(&1.status == "queued"))
  defp by_line(members, line), do: Enum.filter(members || [], &(&1.declared_position == line))

  defp lineup(members, line) do
    members
    |> by_line(line)
    |> Enum.map_join(" · ", fn m ->
      "#{Fu.Accounts.sub_label(m.player, m.declared_position)} #{m.player.display_name |> String.split() |> hd()}"
    end)
  end
  defp started?(result), do: !!(result && result.started_at)
  defp completed?(result), do: !!(result && result.completed_at)

  defp to_int(s) do
    case Integer.parse(to_string(s)) do
      {n, _} when n >= 0 -> n
      _ -> 0
    end
  end

  defp clock(result, now) do
    s = Matches.elapsed_seconds(result, now)
    "#{String.pad_leading("#{div(s, 60)}", 2, "0")}:#{String.pad_leading("#{rem(s, 60)}", 2, "0")}"
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_player={@current_player} active={:browse}>
      <div class="fu-card p-5 space-y-4 text-center">
        <div class="flex items-center justify-between text-meta fu-ink-soft">
          <span class="truncate">{@queue.field.name}</span>
          <span class="text-mono">{@queue.format} · {@queue.formation}</span>
        </div>

        <div class="flex items-center justify-center gap-6">
          <div>
            <div class="text-caption fu-ink-soft">TEAM A</div>
            <div class="text-display leading-none">{(@result && @result.score_a) || 0}</div>
          </div>
          <div class="fu-ink-dim text-h2">–</div>
          <div>
            <div class="text-caption fu-ink-soft">TEAM B</div>
            <div class="text-display leading-none">{(@result && @result.score_b) || 0}</div>
          </div>
        </div>

        <div class="text-mono text-h3 tabular-nums">
          <%= cond do %>
            <% completed?(@result) -> %>
              Full time
            <% started?(@result) -> %>
              {clock(@result, @now)}
            <% true -> %>
              Not started
          <% end %>
        </div>

        <div
          :if={@result && Matches.paused?(@result)}
          id="paused-banner"
          class="fu-badge-casual inline-block"
        >
          ⏸ Paused by the captain
        </div>
      </div>

      <!-- Captain controls (spec §2.7) -->
      <div :if={@captain? && not completed?(@result)} class="fu-card p-4 space-y-3">
        <div class="fu-divider">Captain</div>

        <button
          :if={not started?(@result)}
          id="kickoff"
          phx-click="kickoff"
          class="btn btn-primary w-full min-h-[44px]"
        >
          ▶ Kick off
        </button>

        <button
          :if={started?(@result) && not Matches.paused?(@result)}
          id="pause"
          phx-click="pause"
          class="btn btn-outline w-full min-h-[44px]"
        >
          ⏸ Pause
        </button>

        <button
          :if={started?(@result) && Matches.paused?(@result)}
          id="resume"
          phx-click="resume"
          class="btn btn-primary w-full min-h-[44px]"
        >
          ▶ Resume
        </button>

        <.form
          :if={started?(@result)}
          id="match-finish"
          for={%{}}
          phx-submit="submit-result"
          class="space-y-3 pt-1"
        >
          <div class="fu-divider">Final whistle</div>
          <div class="flex items-center justify-center gap-3">
            <input
              type="number"
              name="score_a"
              min="0"
              value={(@result && @result.score_a) || 0}
              aria-label="Team A final score"
              class="input input-bordered w-20 text-center text-h2 bg-base-200 min-h-[44px]"
              required
            />
            <span class="fu-ink-soft">A&nbsp;–&nbsp;B</span>
            <input
              type="number"
              name="score_b"
              min="0"
              value={(@result && @result.score_b) || 0}
              aria-label="Team B final score"
              class="input input-bordered w-20 text-center text-h2 bg-base-200 min-h-[44px]"
              required
            />
          </div>
          <button type="submit" class="btn btn-primary w-full min-h-[44px]">
            Blow the whistle & finalize ranks
          </button>
        </.form>
      </div>

      <p :if={not @captain? && not completed?(@result)} class="fu-serif fu-ink-soft text-center">
        Your captain runs the clock. Hang tight.
      </p>

      <.link
        :if={completed?(@result)}
        navigate={~p"/postmatch/#{@queue.id}"}
        class="btn btn-primary w-full min-h-[44px]"
      >
        Go to post-match →
      </.link>

      <!-- Tactics — captain edits, the squad previews (spec §2.7) -->
      <div :if={@me} class="fu-card p-4 space-y-3">
        <div class="fu-divider">Tactics · Team {@team}</div>

        <%= if @captain? do %>
          <.form id="tactics-form" for={%{}} phx-submit="save-tactics" class="space-y-3">
            <div class="grid grid-cols-2 gap-3">
              <label class="space-y-1">
                <span class="text-caption fu-ink-soft">Formation</span>
                <select
                  name="formation"
                  class="select select-sm select-bordered bg-base-200 w-full"
                >
                  <option
                    :for={f <- @formations}
                    value={f}
                    selected={f == @tactics.formation}
                  >
                    {f}
                  </option>
                </select>
              </label>
              <label class="space-y-1">
                <span class="text-caption fu-ink-soft">Style</span>
                <select name="style" class="select select-sm select-bordered bg-base-200 w-full">
                  <option :for={s <- @styles} value={s} selected={s == @tactics.style}>
                    {s}
                  </option>
                </select>
              </label>
            </div>
            <textarea
              name="notes"
              maxlength="280"
              placeholder="Instructions for the squad…"
              class="textarea textarea-bordered bg-base-200 w-full text-sm"
            >{@tactics.notes}</textarea>
            <button type="submit" class="btn btn-primary w-full min-h-[44px]">
              Save tactics
            </button>
          </.form>
        <% else %>
          <div id="tactics-preview" class="space-y-1 text-meta">
            <div>
              <span class="fu-ink-soft">Formation</span>
              <span class="font-bold text-[var(--fu-accent)]">{@tactics.formation}</span>
              <span class="fu-ink-soft ml-3">Style</span>
              <span class="font-bold">{@tactics.style}</span>
            </div>
            <p :if={@tactics.notes not in [nil, ""]} class="fu-serif fu-ink-soft">
              "{@tactics.notes}"
            </p>
            <p class="text-caption fu-ink-dim">Set by your captain · preview only</p>
          </div>
        <% end %>

        <div class="pt-2 border-t border-[var(--fu-line)] space-y-1">
          <div
            :for={line <- ~w(GK DEF MID FWD)}
            :if={by_line(@rosters[@team], line) != []}
            class="flex items-baseline gap-2 text-meta"
          >
            <span class="text-mono fu-ink-soft w-9 shrink-0">{line}</span>
            <span class="flex-1 min-w-0">{lineup(@rosters[@team], line)}</span>
          </div>
        </div>
      </div>

      <!-- Rosters -->
      <div :for={t <- ["A", "B"]} class="fu-card divide-y divide-[var(--fu-line)]">
        <div class="fu-divider">TEAM {t}</div>
        <div
          :for={m <- @rosters[t] || []}
          class={[
            "flex items-center gap-3 px-4 py-2.5",
            @me && m.player.id == @me.player_id &&
              "bg-[color-mix(in_oklab,var(--fu-accent)_8%,transparent)]"
          ]}
        >
          <div class="size-7 rounded-full overflow-hidden shrink-0">
            <FuWeb.Avatars.avatar player={m.player} size={28} />
          </div>
          <span class="text-body flex-1 min-w-0 truncate">{m.player.display_name}</span>
          <span :if={m.is_captain} class="text-primary" title="Captain">★</span>
          <span class="text-meta fu-ink-soft shrink-0">{Fu.Accounts.sub_label(m.player, m.declared_position)}</span>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
