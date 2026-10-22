defmodule FuWeb.AssistantLive do
  use FuWeb, :live_view
  alias Fu.{Assistant, Hobbies}
  alias Fu.Assistant.Rules

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    if connected?(socket) do
      Hobbies.subscribe(id)
      :timer.send_interval(1_000, :tick)
    end

    {:ok,
     socket
     |> assign(
       page_title: "Event assistant · FU",
       session_id: id,
       snapshot: nil,
       board_form: to_form(Assistant.change_board()),
       ticks: 0
     )
     |> reload()}
  end

  @impl true
  def handle_event("configure", %{"board" => attrs}, socket) do
    case Assistant.configure(socket.assigns.session_id, socket.assigns.current_player, attrs) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(
           :info,
           "Scorekeeper ready. Agree your rules with the participants before starting."
         )
         |> reload()}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, board_form: to_form(changeset))}

      {:error, error} ->
        {:noreply, socket |> put_flash(:error, error_message(error)) |> reload()}
    end
  end

  def handle_event("command", params, socket) do
    nested = Map.get(params, "command", %{})
    nested = if is_map(nested), do: nested, else: %{}

    attrs =
      params
      |> Map.take(~w(revision request_id side delta referee_id))
      |> Map.merge(nested)

    result =
      Assistant.command(
        socket.assigns.session_id,
        socket.assigns.current_player,
        params["action"],
        attrs
      )

    socket =
      case result do
        {:ok, _} -> socket
        {:error, error} -> put_flash(socket, :error, error_message(error))
      end

    {:noreply, reload(socket)}
  end

  def handle_event(_, _, socket), do: {:noreply, socket}

  @impl true
  def handle_info({:hobby_session_changed, _}, socket), do: {:noreply, reload(socket)}

  def handle_info(:tick, socket) do
    ticks = socket.assigns.ticks + 1
    socket = assign(socket, ticks: ticks)

    if rem(ticks, 30) == 0 do
      {:noreply, reload(socket)}
    else
      clock =
        if socket.assigns.snapshot && socket.assigns.snapshot.board,
          do:
            Rules.clock(
              socket.assigns.snapshot.board,
              DateTime.utc_now() |> DateTime.truncate(:second)
            ),
          else: nil

      {:noreply, assign(socket, clock: clock)}
    end
  end

  defp reload(socket) do
    snapshot = Assistant.snapshot(socket.assigns.session_id, socket.assigns.current_player)

    history =
      if snapshot,
        do: Assistant.history(snapshot.session.id, socket.assigns.current_player),
        else: []

    socket
    |> assign(
      snapshot: snapshot,
      clock: if(snapshot, do: snapshot.clock, else: nil),
      command_id: Ecto.UUID.generate()
    )
    |> stream(:assistant_events, history, reset: true)
  end

  defp duration(seconds),
    do:
      "#{div(seconds, 60) |> Integer.to_string() |> String.pad_leading(2, "0")}:#{rem(seconds, 60) |> Integer.to_string() |> String.pad_leading(2, "0")}"

  defp error_message(:stale_revision),
    do:
      "The scorekeeper changed on another screen. The latest state is loaded; check it before trying again."

  defp error_message(:idempotency_conflict),
    do: "That request was already used for a different change. Check the latest state."

  defp error_message(:not_active),
    do: "Start the event from its host controls before using the timer or scores."

  defp error_message(:forbidden),
    do: "Only the host or the currently assigned referee can make that change."

  defp error_message(:invalid_referee),
    do: "Choose the host or someone currently participating in this event."

  defp error_message(:reason_required), do: "Add a reason between 3 and 500 characters."
  defp error_message(:invalid_score), do: "Scores must stay between 0 and 99999."
  defp error_message(:elapsed), do: "Time has elapsed. Review the score and confirm the result."

  defp error_message(:finished),
    do: "The result is finalized. Use a recorded correction if a change is needed."

  defp error_message(:not_running), do: "Start the timer first."
  defp error_message(_), do: "The change could not be saved. Check the latest event state."

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_player={@current_player} active={:assistant}>
      <p class="text-caption">Organize · time · record</p>
      <h1 class="text-h1">Event assistant</h1>
      <%= if @snapshot do %>
        <div class="fu-card p-5 space-y-3">
          <h2 class="text-h2">{@snapshot.session.title}</h2>
          <p class="fu-ink-soft">{@snapshot.session.hobby} · {@snapshot.session.status}</p>
          <.link navigate={~p"/hobbies/#{@snapshot.session.id}"} class="btn btn-sm">
            Event and host controls
          </.link>
        </div>
        <section id="organizer-checks" class="fu-card p-5 space-y-4">
          <h2 class="text-h2">Before you begin</h2>
          <p :if={@snapshot.readiness.can_start?} id="assistant-ready" class="text-primary">
            Recorded checks are ready for the host to start the event.
          </p>
          <div
            :for={check <- @snapshot.readiness.checks}
            id={"check-#{check.key}"}
            data-status={check.status}
            class="border-t border-base-300 pt-3 space-y-1"
          >
            <div class="flex items-center justify-between gap-3">
              <h3 class="font-semibold">{check.label}</h3>
              <span class="text-caption">{String.replace(check.status, "_", " ")}</span>
            </div>
            <p class="text-sm fu-ink-soft">{check.detail}</p>
          </div>
          <.link navigate={~p"/equipment"} class="btn btn-sm">Manage your equipment</.link>
        </section>
        <section :if={@snapshot.assets != []} class="fu-card p-5 space-y-3" id="event-equipment">
          <h2 class="text-h2">Reserved equipment</h2>
          <p
            :for={asset <- @snapshot.assets}
            id={"shared-equipment-#{asset.id}"}
            data-source={asset.location.source || "unknown"}
          >
            {asset.name} · {asset.condition} · {asset.location.zone || "Location unknown"} · {asset.location.freshness}
          </p>
        </section>
        <%= if @snapshot.board do %>
          <section
            id="scoreboard"
            class="fu-card p-5 space-y-5"
            data-revision={@snapshot.board.revision}
          >
            <div class="flex justify-between gap-3">
              <h2 class="text-h2">Scorekeeper</h2>
              <span id="clock-status" class="text-caption">{@clock.status}</span>
            </div>
            <p class="text-sm fu-ink-soft">
              Human-reported {@snapshot.board.unit}. Referee: {if @snapshot.board.referee,
                do: @snapshot.board.referee.display_name,
                else: "Host"}. Agree your activity's rules together.
            </p>
            <div
              id="match-clock"
              role="timer"
              aria-label="Time remaining"
              class="text-center font-mono text-5xl py-3"
            >
              {duration(@clock.remaining_seconds)}
            </div>
            <p :if={@clock.status == "elapsed"} id="time-elapsed" role="status">
              Time has elapsed. The referee still needs to review and confirm the result.
            </p>
            <div class="grid grid-cols-2 gap-4 text-center">
              <div>
                <p>{@snapshot.board.team_a}</p>
                <p id="score-a" class="text-5xl font-bold mt-2">{@snapshot.board.score_a}</p>
              </div>
              <div>
                <p>{@snapshot.board.team_b}</p>
                <p id="score-b" class="text-5xl font-bold mt-2">{@snapshot.board.score_b}</p>
              </div>
            </div>
            <p
              :if={@snapshot.board.status == "finalized"}
              id="result-finalized"
              role="status"
              class="text-primary"
            >
              Result confirmed by a person. Corrections remain in the history.
            </p>
            <div :if={@snapshot.can_officiate?} id="referee-controls" class="space-y-4">
              <p :if={@snapshot.session.status == "scheduled"} class="fu-ink-soft">
                Start the event from host controls to enable timing and scoring.
              </p>
              <div
                :if={@snapshot.session.status == "active" && @snapshot.board.status != "finalized"}
                class="space-y-4"
              >
                <button
                  :if={@snapshot.board.status in ["idle", "paused"] && @clock.remaining_seconds > 0}
                  id="start-clock"
                  phx-click="command"
                  phx-value-action="start"
                  phx-value-revision={@snapshot.board.revision}
                  phx-value-request_id={@command_id <> "-start"}
                  phx-disable-with="Saving…"
                  class="btn btn-primary w-full"
                >
                  {if @snapshot.board.status == "paused", do: "Resume timer", else: "Start timer"}
                </button>
                <button
                  :if={@snapshot.board.status == "running"}
                  id="pause-clock"
                  phx-click="command"
                  phx-value-action="pause"
                  phx-value-revision={@snapshot.board.revision}
                  phx-value-request_id={@command_id <> "-pause"}
                  phx-disable-with="Saving…"
                  class="btn w-full"
                >
                  Pause timer
                </button>
                <div
                  :if={@snapshot.board.status in ["running", "paused"]}
                  class="grid grid-cols-2 gap-3"
                >
                  <button
                    :for={side <- ["a", "b"]}
                    id={"add-score-#{side}"}
                    phx-click="command"
                    phx-value-action="score"
                    phx-value-side={side}
                    phx-value-delta="1"
                    phx-value-revision={@snapshot.board.revision}
                    phx-value-request_id={@command_id <> "-" <> side}
                    phx-disable-with="Saving…"
                    class="btn btn-primary"
                    aria-label={"Add one for " <> if(side == "a", do: @snapshot.board.team_a, else: @snapshot.board.team_b)}
                  >
                    +1 {if side == "a", do: @snapshot.board.team_a, else: @snapshot.board.team_b}
                  </button>
                </div>
              </div>
              <details
                :if={@snapshot.session.status in ["active", "completed"]}
                class="border-t border-base-300 pt-3"
              >
                <summary class="font-semibold cursor-pointer">Correct a recorded score</summary>
                <.form
                  for={to_form(%{}, as: :command)}
                  id="correct-score-form"
                  phx-submit="command"
                  phx-value-action="correct"
                  phx-value-revision={@snapshot.board.revision}
                  phx-value-request_id={@command_id <> "-correct"}
                  class="space-y-3 mt-3"
                >
                  <div class="grid grid-cols-2 gap-3">
                    <.input
                      name="command[score_a]"
                      value={@snapshot.board.score_a}
                      type="number"
                      label={@snapshot.board.team_a}
                      min="0"
                      max="99999"
                      required
                    />
                    <.input
                      name="command[score_b]"
                      value={@snapshot.board.score_b}
                      type="number"
                      label={@snapshot.board.team_b}
                      min="0"
                      max="99999"
                      required
                    />
                  </div>
                  <.input
                    name="command[reason]"
                    value=""
                    label="Reason for correction"
                    required
                    minlength="3"
                    maxlength="500"
                  />
                  <button class="btn" phx-disable-with="Saving…">Record correction</button>
                </.form>
              </details>
              <.form
                :if={
                  @snapshot.session.status in ["active", "completed"] &&
                    @snapshot.board.status in ["running", "paused"]
                }
                for={to_form(%{}, as: :command)}
                id="finalize-score-form"
                phx-submit="command"
                phx-value-action="finalize"
                phx-value-revision={@snapshot.board.revision}
                phx-value-request_id={@command_id <> "-finalize"}
                class="space-y-3 border-t border-base-300 pt-3"
              >
                <.input
                  id="finalize-reason"
                  name="command[reason]"
                  value=""
                  label="Confirm the result after review"
                  placeholder="e.g. both sides reviewed the score"
                  required
                  minlength="3"
                  maxlength="500"
                />
                <button id="finalize-score" class="btn btn-primary" phx-disable-with="Saving…">
                  Confirm result and stop timer
                </button>
              </.form>
            </div>
            <details :if={@snapshot.host?} class="border-t border-base-300 pt-3">
              <summary class="font-semibold cursor-pointer">Assign a referee</summary>
              <.form
                for={to_form(%{}, as: :command)}
                id="assign-referee-form"
                phx-submit="command"
                phx-value-action="assign_referee"
                phx-value-revision={@snapshot.board.revision}
                phx-value-request_id={@command_id <> "-referee"}
                class="space-y-3 mt-3"
              >
                <.input
                  name="command[referee_id]"
                  value={@snapshot.board.referee_id}
                  type="select"
                  label="Host or current participant"
                  options={@snapshot.referee_options}
                />
                <button class="btn" phx-disable-with="Saving…">Save referee</button>
              </.form>
            </details>
          </section>
        <% else %>
          <details
            :if={@snapshot.host? && @snapshot.session.status in ["scheduled", "active"]}
            class="fu-card p-5"
          >
            <summary class="text-h2 cursor-pointer">Add a timer and scorekeeper</summary>
            <p class="text-sm fu-ink-soft mt-3">
              Optional for games or timed practice. People make the calls; FU records the timer, score and corrections.
            </p>
            <.form
              for={@board_form}
              id="configure-scorekeeper"
              phx-submit="configure"
              class="space-y-3 mt-3"
            >
              <.input field={@board_form[:team_a]} label="Side A" required maxlength="60" />
              <.input field={@board_form[:team_b]} label="Side B" required maxlength="60" />
              <.input
                field={@board_form[:unit]}
                type="select"
                label="Count"
                options={[{"Points", "points"}, {"Goals", "goals"}, {"Rounds", "rounds"}]}
              />
              <.input
                field={@board_form[:duration_seconds]}
                type="number"
                label="Timer length · seconds"
                min="1"
                max="14400"
                required
              />
              <.input
                field={@board_form[:referee_id]}
                value={@current_player.id}
                type="select"
                label="Referee"
                options={@snapshot.referee_options}
              />
              <button class="btn btn-primary" phx-disable-with="Saving…">Set up scorekeeper</button>
            </.form>
          </details>
        <% end %>
        <section class="fu-card p-5 space-y-3">
          <h2 class="text-h2">Scorekeeper history</h2>
          <div id="assistant-history" phx-update="stream" class="space-y-3">
            <p id="assistant-history-empty" class="hidden only:block text-sm fu-ink-soft">
              No scorekeeper changes recorded.
            </p>
            <article
              :for={{dom_id, event} <- @streams.assistant_events}
              id={dom_id}
              class="border-t border-base-300 pt-3 space-y-1"
            >
              <p>
                #{event.revision} · {String.replace(event.action, "_", " ")} · {if event.actor,
                  do: event.actor.display_name,
                  else: "Former participant"}
              </p>
              <p :if={event.payload["reason"]} class="text-sm">{event.payload["reason"]}</p>
              <p :if={Map.has_key?(event.payload, "score_a")} class="text-sm fu-ink-soft">
                Recorded score: {event.payload["score_a"]} – {event.payload["score_b"]}
              </p>
              <time datetime={DateTime.to_iso8601(event.inserted_at)} class="text-sm fu-ink-soft">
                {Calendar.strftime(event.inserted_at, "%d %b %H:%M:%S UTC")}
              </time>
            </article>
          </div>
        </section>
      <% else %>
        <p id="assistant-unavailable" class="fu-card p-5">
          Join this event to use its assistant, or return to Explore to find an event.
        </p>
        <.link navigate={~p"/explore"} class="btn">Explore events</.link>
      <% end %>
    </Layouts.app>
    """
  end
end
