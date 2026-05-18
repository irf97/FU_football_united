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

  # editorial verdict line from my result, falling back to @winner only
  defp verdict(winner, nil) do
    case winner do
      :draw -> "All square."
      "A" -> "Team A win."
      "B" -> "Team B win."
      _ -> ""
    end
  end

  defp verdict(:draw, _my_team), do: "All square."
  defp verdict(winner, my_team) when winner == my_team, do: "You won."
  defp verdict(_winner, _my_team), do: "Next time."

  defp tagline("mvp"), do: "Who hurt your team the most?"
  defp tagline("defender"), do: "Who shut your attack down?"
  defp tagline("keeper"), do: "How good was their keeper?"
  defp tagline(_), do: ""

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_player={@current_player} active={nil}>
      <!-- Match header (spec §2.8) -->
      <div class="fu-card p-5 space-y-2">
        <div class="flex items-start justify-between">
          <div>
            <h1 class="text-h1">{@queue.field.name}</h1>
            <div class="text-meta fu-ink-soft">Post-match</div>
          </div>
          <span class={if @queue.rated, do: "fu-badge-rated", else: "fu-badge-casual"}>
            {if @queue.rated, do: "Rated", else: "Casual"}
          </span>
        </div>
        <div class="flex items-center justify-between text-meta">
          <span>{fmt_kickoff(@queue.scheduled_at)}</span>
          <span class="text-mono fu-ink-soft">{@queue.format}</span>
        </div>
      </div>

      <!-- FE09 — Final score (plan §9.2/§9.3) -->
      <div :if={@result} class="fu-card p-6 text-center space-y-4">
        <div class="fu-divider">FULL TIME</div>
        <div class="flex items-end justify-center gap-5">
          <span class={[
            "text-display leading-none",
            @winner == "A" && "text-primary",
            @winner != "A" && "fu-ink-soft"
          ]}>
            {@result.score_a}
          </span>
          <span class="fu-ink-dim text-h2 pb-2">–</span>
          <span class={[
            "text-display leading-none",
            @winner == "B" && "text-primary",
            @winner != "B" && "fu-ink-soft"
          ]}>
            {@result.score_b}
          </span>
        </div>
        <p class="fu-serif text-h3 fu-ink-soft">
          {verdict(@winner, assigns[:my_team])}
        </p>

        <div :if={@goals != []} class="space-y-2 text-left">
          <div class="fu-divider">GOALS</div>
          <div :for={g <- @goals} class="flex items-baseline justify-between">
            <span>
              <span class="text-body">{name(@roster_map, g.scorer_id)}</span>
              <span :if={g.assist_id} class="fu-ink-soft text-meta">
                · assist {name(@roster_map, g.assist_id)}
              </span>
            </span>
            <span class="text-mono fu-ink-soft">Team {g.team}</span>
          </div>
        </div>
      </div>

      <div :if={!@result} class="fu-card p-6 text-center fu-serif fu-ink-soft">
        Result not finalized yet — check back once the operator confirms.
      </div>

      <!-- FE11 — Voting (plan §9.5) -->
      <div :if={@voting_open? and @pending != []} class="space-y-3">
        <div class="flex items-start justify-between gap-3">
          <div>
            <h2 class="text-h2">Rate your opponents</h2>
            <div class="text-meta fu-ink-soft">Vote closes after 24h</div>
          </div>
          <button phx-click="skip-all" class="pos-pill needs">Skip all</button>
        </div>

        <div :if={"mvp" in @pending} class="fu-card p-4 space-y-3">
          <div class="flex items-start justify-between gap-3">
            <p class="fu-serif fu-ink-soft text-meta">{tagline("mvp")}</p>
            <button phx-click="skip" phx-value-category="mvp" class="pos-pill needs">Skip</button>
          </div>
          <div class="space-y-2">
            <button
              :for={m <- @opponents}
              phx-click="vote"
              phx-value-category="mvp"
              phx-value-subject={m.player.id}
              class="w-full flex items-center justify-between border border-neutral rounded-lg px-3 py-2 text-left hover:bg-primary hover:text-primary-content transition"
            >
              <span class="text-body">{m.player.display_name}</span>
              <span class="flex items-center gap-2 text-meta">
                <span class="pos-pill">{Fu.Accounts.sub_label(m.player, m.declared_position)}</span>
                <span class="text-mono fu-ink-soft">{f1(m.player.rank)}</span>
              </span>
            </button>
          </div>
        </div>

        <div :if={"defender" in @pending} class="fu-card p-4 space-y-3">
          <div class="flex items-start justify-between gap-3">
            <p class="fu-serif fu-ink-soft text-meta">{tagline("defender")}</p>
            <button phx-click="skip" phx-value-category="defender" class="pos-pill needs">Skip</button>
          </div>
          <div class="space-y-2">
            <button
              :for={m <- @opponents}
              phx-click="vote"
              phx-value-category="defender"
              phx-value-subject={m.player.id}
              class="w-full flex items-center justify-between border border-neutral rounded-lg px-3 py-2 text-left hover:bg-primary hover:text-primary-content transition"
            >
              <span class="text-body">{m.player.display_name}</span>
              <span class="flex items-center gap-2 text-meta">
                <span class="pos-pill">{Fu.Accounts.sub_label(m.player, m.declared_position)}</span>
                <span class="text-mono fu-ink-soft">{f1(m.player.rank)}</span>
              </span>
            </button>
          </div>
        </div>

        <div :if={"keeper" in @pending} class="fu-card p-4 space-y-3">
          <div class="flex items-start justify-between gap-3">
            <p class="fu-serif fu-ink-soft text-meta">{tagline("keeper")}</p>
            <button phx-click="skip" phx-value-category="keeper" class="pos-pill needs">Skip</button>
          </div>
          <div :if={@opp_keeper} class="space-y-3">
            <div class="text-meta fu-ink-soft">{@opp_keeper.player.display_name}</div>
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
              class="btn btn-primary w-full"
            >
              Submit {@keeper_score}/10
            </button>
          </div>
          <div :if={!@opp_keeper} class="text-meta fu-ink-soft">
            Opponent had no declared keeper.
          </div>
        </div>

        <p class="text-meta fu-ink-soft px-1">
          Skipping doesn't block you being voted on; skipping 2 matches in a row
          costs you −10 (spec §2.8).
        </p>
      </div>

      <!-- Tally (after voting closed or all done) -->
      <div :if={@tally} class="fu-card p-4 space-y-2">
        <div class="fu-divider">RESULTS</div>
        <div class="flex justify-between text-meta">
          <span class="fu-ink-soft">MVP</span>
          <span class="text-body">{name(@roster_map, @tally.mvp.winner_id)}</span>
        </div>
        <div class="flex justify-between text-meta">
          <span class="fu-ink-soft">Best defender</span>
          <span class="text-body">{name(@roster_map, @tally.defender.winner_id)}</span>
        </div>
        <div class="flex justify-between text-meta">
          <span class="fu-ink-soft">Keeper median</span>
          <span class="text-mono">
            A {f1(@tally.keeper["A"])} · B {f1(@tally.keeper["B"])}
          </span>
        </div>
      </div>

      <!-- FE10 — Rank-delta hero + breakdown (plan §9.4) -->
      <div class="fu-card p-6 text-center space-y-3">
        <div :if={@rank_event}>
          <div class="fu-divider">YOUR RANK</div>
          <div class={[
            "text-display leading-none mt-3",
            @rank_event.delta >= 0 && "text-primary",
            @rank_event.delta < 0 && "text-[var(--fu-danger)]"
          ]}>
            {signed(@rank_event.delta)}
          </div>
          <div class="text-mono fu-ink-soft mt-1">
            {f1(@rank_event.rank_before)} → {f1(@rank_event.rank_after)}
          </div>

          <button phx-click="toggle-breakdown" class="btn w-full mt-4">
            {if @show_breakdown, do: "Hide breakdown ▴", else: "See breakdown ▾"}
          </button>

          <div :if={@show_breakdown} class="mt-4 space-y-1 text-left">
            <div
              :for={{k, v} <- Enum.sort(@rank_event.breakdown)}
              class={[
                "flex justify-between text-meta",
                is_number(v) && v == 0 && "fu-ink-dim"
              ]}
            >
              <span class="fu-ink-soft">{humanize(k)}</span>
              <span class="text-mono">{signed(v)}</span>
            </div>
            <div class="fu-divider">TOTAL</div>
            <div class="flex justify-between text-meta font-bold">
              <span>Total</span>
              <span class="text-mono">{signed(@rank_event.delta)}</span>
            </div>
            <p class="text-caption fu-ink-dim pt-2">
              Every input is visible — this is the rank transparency commitment (spec §2.9).
            </p>
          </div>

          <button phx-click="dispute" class="fu-ink-soft text-meta mt-3">
            Dispute
          </button>
        </div>

        <div :if={!@rank_event} class="fu-serif fu-ink-soft">
          Rank updates once results are finalized.
        </div>
      </div>
    </Layouts.app>
    """
  end
end
