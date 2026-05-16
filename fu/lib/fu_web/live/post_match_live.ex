defmodule FuWeb.PostMatchLive do
  @moduledoc """
  Surface 6: the post-match surface (spec §2.8, §2.13). Hard signals (final
  score, goals), soft signals (4-category voting with per-category skip,
  spec §4 Q3), then the tally and the player's full, tappable rank
  derivation (spec §2.9).
  """
  use FuWeb, :live_view

  alias Fu.{Queues, Balance, Matches, Voting, Ranking}

  @impl true
  def mount(%{"queue_id" => qid}, _session, socket) do
    {:ok, socket |> assign(qid: qid, show_breakdown: false) |> load()}
  end

  defp load(socket) do
    qid = socket.assigns.qid
    queue = Queues.get_queue!(qid)
    rosters = Balance.rosters(queue.id)
    player = socket.assigns.current_player

    members = (rosters["A"] || []) ++ (rosters["B"] || [])
    roster_map = Map.new(members, &{&1.player.id, &1.player})
    me = Enum.find(members, &(&1.player.id == player.id))
    my_team = me && me.team
    opp_team = if(my_team == "A", do: "B", else: "A")
    opponents = (my_team && rosters[opp_team]) || []
    opp_keeper = Enum.find(opponents, &(&1.declared_position == "GK"))

    result = Matches.result(queue.id)
    voting_open? = Voting.voting_open?(queue.id)
    pending = if voting_open?, do: Voting.pending_categories(queue.id, player.id), else: []

    assign(socket,
      queue: queue,
      rosters: rosters,
      roster_map: roster_map,
      my_membership: me,
      my_team: my_team,
      opponents: opponents,
      opp_keeper: opp_keeper,
      result: result,
      winner: result && Matches.winner(queue.id),
      goals: Matches.goals_for(queue.id),
      voting_open?: voting_open?,
      pending: pending,
      tally: (if pending == [] or not voting_open?, do: Voting.tally(queue.id)),
      rank_event: Ranking.event_for(player.id, queue.id),
      keeper_score: 7
    )
  end

  ## --- events ---

  @impl true
  def handle_event("vote", %{"category" => cat, "subject" => sid}, socket) do
    Voting.cast(socket.assigns.qid, socket.assigns.current_player.id, cat,
      String.to_integer(sid), own_team: false)

    {:noreply, socket |> put_flash(:info, "Vote recorded — #{cat}.") |> load()}
  end

  def handle_event("vote-keeper", %{"score" => s}, socket) do
    kp = socket.assigns.opp_keeper

    if kp do
      Voting.cast(socket.assigns.qid, socket.assigns.current_player.id, "keeper",
        kp.player.id, own_team: false, score: String.to_integer(s))

      {:noreply, socket |> put_flash(:info, "Keeper scored #{s}/10.") |> load()}
    else
      {:noreply, put_flash(socket, :error, "No opponent keeper to score.")}
    end
  end

  def handle_event("set-keeper", %{"score" => s}, socket),
    do: {:noreply, assign(socket, keeper_score: String.to_integer(s))}

  def handle_event("skip", %{"category" => cat}, socket) do
    Voting.skip(socket.assigns.qid, socket.assigns.current_player.id, cat)
    {:noreply, socket |> put_flash(:info, "Skipped #{cat}.") |> load()}
  end

  def handle_event("skip-all", _, socket) do
    pid = socket.assigns.current_player.id

    Enum.each(socket.assigns.pending, &Voting.skip(socket.assigns.qid, pid, &1))
    {:noreply, socket |> put_flash(:info, "Skipped all categories.") |> load()}
  end

  def handle_event("toggle-breakdown", _, socket),
    do: {:noreply, assign(socket, show_breakdown: !socket.assigns.show_breakdown)}

  def handle_event("dispute", _, socket) do
    id = socket.assigns.queue.id
    pid = socket.assigns.current_player.id

    try do
      Ranking.file_dispute(pid, %{queue_id: id, kind: "rank", note: "player dispute"})
    rescue
      _ -> :ok
    catch
      _, _ -> :ok
    end

    {:noreply, put_flash(socket, :info, "Dispute filed for operator review (spec §2.10).")}
  end

  ## --- helpers ---

  defp name(_roster_map, nil), do: "—"
  defp name(roster_map, pid) do
    case roster_map[pid] do
      nil -> "Unknown"
      p -> p.display_name
    end
  end

  defp f1(n) when is_number(n), do: :erlang.float_to_binary(n / 1, decimals: 1)
  defp f1(_), do: "0.0"

  defp signed(n) when is_number(n) and n >= 0, do: "+#{f1(n)}"
  defp signed(n) when is_number(n), do: "−#{f1(abs(n))}"
  defp signed(_), do: "—"

  defp humanize(key) do
    key
    |> to_string()
    |> String.replace("_", " ")
    |> String.split()
    |> Enum.map_join(" ", &String.capitalize/1)
  end

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
    <Layouts.app flash={@flash} current_player={@current_player} active={nil}>
      <!-- Match header (spec §2.8) -->
      <div class="fu-card p-5 space-y-2">
        <div class="flex items-start justify-between">
          <div>
            <h1 class="text-h1">{@queue.field.name}</h1>
            <div class="text-xs fu-ink-soft">Post-match</div>
          </div>
          <span class={if @queue.rated, do: "fu-badge-rated", else: "fu-badge-casual"}>
            {if @queue.rated, do: "Rated", else: "Casual"}
          </span>
        </div>
        <div class="flex items-center justify-between text-sm">
          <span>{fmt_kickoff(@queue.scheduled_at)}</span>
          <span class="font-mono text-xs fu-ink-soft">{@queue.format}</span>
        </div>
      </div>

      <!-- Hard signals: final score (spec §2.8) -->
      <div :if={@result} class="fu-card p-6 text-center space-y-3">
        <div class="text-xs fu-ink-dim font-mono uppercase tracking-wider">Full time</div>
        <div class="flex items-center justify-center gap-4">
          <span class={["fu-serif text-5xl leading-none", @winner == "A" && "text-primary", @winner != "A" && "fu-ink-soft"]}>
            A {@result.score_a}
          </span>
          <span class="fu-ink-dim text-2xl">–</span>
          <span class={["fu-serif text-5xl leading-none", @winner == "B" && "text-primary", @winner != "B" && "fu-ink-soft"]}>
            {@result.score_b} B
          </span>
        </div>
        <div class="text-sm fu-ink-soft">
          {cond do
            @winner == :draw -> "Draw"
            @winner -> "Team #{@winner} win"
            true -> ""
          end}
        </div>

        <div :if={@goals != []} class="pt-3 border-t border-neutral space-y-1 text-left">
          <div class="text-xs fu-ink-dim font-mono uppercase tracking-wider">Goals</div>
          <div :for={g <- @goals} class="text-sm flex justify-between">
            <span>
              <span class="text-primary">{name(@roster_map, g.scorer_id)}</span>
              <span :if={g.assist_id} class="fu-ink-soft">
                · assist {name(@roster_map, g.assist_id)}
              </span>
            </span>
            <span class="font-mono text-xs fu-ink-soft">Team {g.team}</span>
          </div>
        </div>
      </div>

      <div :if={!@result} class="fu-card p-6 text-center fu-ink-soft text-sm">
        Result not finalized yet — check back once the operator confirms.
      </div>

      <!-- Soft signals: voting (spec §2.8, §4 Q3) -->
      <div :if={@voting_open? and @pending != []} class="space-y-3">
        <div class="flex items-center justify-between">
          <h2 class="text-h2">Rate your opponents</h2>
          <button phx-click="skip-all" class="pos-pill needs">Skip all</button>
        </div>

        <div :if={"mvp" in @pending} class="fu-card p-4 space-y-2">
          <div class="flex items-center justify-between">
            <span class="text-xs fu-ink-dim font-mono uppercase tracking-wider">MVP</span>
            <button phx-click="skip" phx-value-category="mvp" class="pos-pill needs">Skip</button>
          </div>
          <div class="flex flex-wrap gap-2">
            <button
              :for={m <- @opponents}
              phx-click="vote"
              phx-value-category="mvp"
              phx-value-subject={m.player.id}
              class="pos-pill"
            >
              {m.player.display_name} #{m.player.jersey_number}
            </button>
          </div>
        </div>

        <div :if={"defender" in @pending} class="fu-card p-4 space-y-2">
          <div class="flex items-center justify-between">
            <span class="text-xs fu-ink-dim font-mono uppercase tracking-wider">Best defender</span>
            <button phx-click="skip" phx-value-category="defender" class="pos-pill needs">Skip</button>
          </div>
          <div class="flex flex-wrap gap-2">
            <button
              :for={m <- @opponents}
              phx-click="vote"
              phx-value-category="defender"
              phx-value-subject={m.player.id}
              class="pos-pill"
            >
              {m.player.display_name} #{m.player.jersey_number}
            </button>
          </div>
        </div>

        <div :if={"keeper" in @pending} class="fu-card p-4 space-y-2">
          <div class="flex items-center justify-between">
            <span class="text-xs fu-ink-dim font-mono uppercase tracking-wider">
              Keeper score{if @opp_keeper, do: " · #{@opp_keeper.player.display_name}"}
            </span>
            <button phx-click="skip" phx-value-category="keeper" class="pos-pill needs">Skip</button>
          </div>
          <div :if={@opp_keeper} class="space-y-2">
            <div class="flex flex-wrap gap-1">
              <button
                :for={s <- 0..10}
                phx-click="set-keeper"
                phx-value-score={s}
                class={["pos-pill", s == @keeper_score && "full"]}
              >
                {s}
              </button>
            </div>
            <button
              phx-click="vote-keeper"
              phx-value-score={@keeper_score}
              class="btn btn-sm btn-primary w-full"
            >
              Submit {@keeper_score}/10
            </button>
          </div>
          <div :if={!@opp_keeper} class="text-xs fu-ink-soft">
            Opponent had no declared keeper.
          </div>
        </div>

        <div class="text-xs fu-ink-soft px-1">
          Skipping doesn't block you being voted on; skipping 2 matches in a row
          costs you −10 (spec §2.8).
        </div>
      </div>

      <!-- Tally (after voting closed or all done) -->
      <div :if={@tally} class="fu-card p-4 space-y-2">
        <div class="text-xs fu-ink-dim font-mono uppercase tracking-wider">Results</div>
        <div class="flex justify-between text-sm">
          <span class="fu-ink-soft">MVP</span>
          <span class="text-primary">{name(@roster_map, @tally.mvp.winner_id)}</span>
        </div>
        <div class="flex justify-between text-sm">
          <span class="fu-ink-soft">Best defender</span>
          <span class="text-primary">{name(@roster_map, @tally.defender.winner_id)}</span>
        </div>
        <div class="flex justify-between text-sm">
          <span class="fu-ink-soft">Keeper median</span>
          <span class="font-mono">
            A {f1(@tally.keeper["A"])} · B {f1(@tally.keeper["B"])}
          </span>
        </div>
      </div>

      <!-- Rank delta + full derivation (spec §2.9) -->
      <div class="fu-card p-5 space-y-3">
        <div class="text-xs fu-ink-dim font-mono uppercase tracking-wider">Your rank</div>

        <div :if={@rank_event}>
          <div class="text-center space-y-1">
            <div class={[
              "fu-serif text-5xl leading-none",
              @rank_event.delta >= 0 && "text-primary",
              @rank_event.delta < 0 && "text-warning"
            ]}>
              {signed(@rank_event.delta)}
            </div>
            <div class="text-sm fu-ink-soft font-mono">
              {f1(@rank_event.rank_before)} → {f1(@rank_event.rank_after)}
            </div>
          </div>

          <button phx-click="toggle-breakdown" class="btn btn-sm btn-outline w-full mt-3">
            {if @show_breakdown, do: "Hide derivation", else: "See full derivation"}
          </button>

          <div :if={@show_breakdown} class="mt-3 space-y-1 border-t border-neutral pt-3">
            <div class="text-xs fu-ink-dim font-mono uppercase tracking-wider">
              Every component (spec §2.9)
            </div>
            <div
              :for={{k, v} <- Enum.sort(@rank_event.breakdown)}
              class="flex justify-between text-sm"
            >
              <span class="fu-ink-soft">{humanize(k)}</span>
              <span class={[
                "font-mono",
                is_number(v) && v >= 0 && "text-primary",
                is_number(v) && v < 0 && "text-warning"
              ]}>
                {signed(v)}
              </span>
            </div>
            <div class="flex justify-between text-sm border-t border-neutral pt-2 mt-2">
              <span class="fu-serif">Net delta</span>
              <span class="font-mono">{signed(@rank_event.delta)}</span>
            </div>
          </div>
        </div>

        <div :if={!@rank_event} class="text-sm fu-ink-soft">
          Rank updates once results are finalized.
        </div>

        <button phx-click="dispute" class="text-xs fu-ink-dim underline mt-2">
          Dispute this
        </button>
      </div>
    </Layouts.app>
    """
  end
end
