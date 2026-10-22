defmodule FuWeb.HobbiesLive do
  use FuWeb, :live_view
  alias Fu.Hobbies

  @impl true
  def mount(params, _session, socket) do
    socket =
      assign(socket,
        page_title: "FU Hobbies",
        filter: "",
        session: nil,
        member: nil,
        session_form:
          to_form(
            Hobbies.change_session(
              params
              |> Map.take(["hobby", "category", "kind"])
              |> Map.reject(fn {_, value} -> value == "" end)
            )
          ),
        leave_form: to_form(%{"reason" => ""}, as: :leave),
        access_form: to_form(%{"note" => ""}, as: :access),
        cancel_form: to_form(%{"reason" => ""}, as: :cancel)
      )

    if connected?(socket) do
      case socket.assigns.live_action do
        :index -> Hobbies.subscribe()
        :show -> Hobbies.subscribe(params["id"])
        _ -> :ok
      end
    end

    {:ok, reload(socket, params)}
  end

  @impl true
  def handle_event("filter", %{"filter" => %{"hobby" => hobby}}, socket) do
    {:noreply, socket |> assign(filter: hobby) |> reload(%{})}
  end

  def handle_event("create", %{"session" => params}, socket) do
    case Hobbies.create_session(socket.assigns.current_player, params) do
      {:ok, session} -> {:noreply, push_navigate(socket, to: ~p"/hobbies/#{session.id}")}
      {:error, changeset} -> {:noreply, assign(socket, session_form: to_form(changeset))}
    end
  end

  def handle_event(action, params, %{assigns: %{session: session}} = socket)
      when action in [
             "join",
             "commit",
             "leave",
             "confirm-access",
             "start",
             "attend",
             "finish",
             "cancel"
           ] and not is_nil(session) do
    player = socket.assigns.current_player

    result =
      case action do
        "join" ->
          Hobbies.join(session.id, player)

        "commit" ->
          Hobbies.commit(session.id, player)

        "leave" ->
          Hobbies.leave(session.id, player, get_in(params, ["leave", "reason"]) || "")

        "confirm-access" ->
          Hobbies.confirm_access(session.id, player, get_in(params, ["access", "note"]) || "")

        "start" ->
          Hobbies.start(session.id, player)

        "attend" ->
          Hobbies.attend(session.id, player)

        "finish" ->
          Hobbies.finish(session.id, player)

        "cancel" ->
          Hobbies.cancel(session.id, player, get_in(params, ["cancel", "reason"]) || "")
      end

    socket =
      case result do
        {:ok, _} -> put_flash(socket, :info, success(action))
        {:error, reason} -> put_flash(socket, :error, error_message(reason))
      end

    {:noreply, reload(socket, %{"id" => session.id})}
  end

  def handle_event(_, _, socket), do: {:noreply, socket}

  @impl true
  def handle_info({:hobby_session_changed, _}, socket) do
    params = if socket.assigns.session, do: %{"id" => socket.assigns.session.id}, else: %{}
    {:noreply, reload(socket, params)}
  end

  defp reload(%{assigns: %{live_action: :index}} = socket, _) do
    stream(socket, :sessions, Hobbies.list_sessions(%{hobby: socket.assigns.filter}),
      reset: true,
      dom_id: &"hobby-session-#{&1.id}"
    )
  end

  defp reload(%{assigns: %{live_action: :show}} = socket, %{"id" => id}) do
    session = Hobbies.get_session(id)
    member = if session, do: Hobbies.membership(session, socket.assigns.current_player)

    events =
      if session && (session.host_id == socket.assigns.current_player.id || member),
        do: Hobbies.history(id),
        else: []

    socket
    |> assign(session: session, member: member)
    |> stream(:participants, if(session, do: session.participants, else: []), reset: true)
    |> stream(:events, events, reset: true)
  end

  defp reload(socket, _), do: socket

  defp present?(nil), do: false
  defp present?(member), do: member.status in ["joined", "committed", "attended"]
  defp closed?(session), do: session.status in ["cancelled", "completed"]
  defp fmt_time(date), do: Calendar.strftime(date, "%a %d %b · %H:%M UTC")
  defp label("open"), do: "Open presence"
  defp label("practice"), do: "Practice"
  defp label("committed"), do: "Committed session"

  defp success("join"), do: "You're on the list."
  defp success("commit"), do: "Your commitment is recorded."
  defp success("leave"), do: "You've left the session."
  defp success("confirm-access"), do: "Your access confirmation is recorded."
  defp success("start"), do: "The session is active."
  defp success("attend"), do: "You've checked in."
  defp success("finish"), do: "Session completed."
  defp success("cancel"), do: "Session cancelled; the update is available to all participants."

  defp error_message(:full), do: "This session is full. Try again if a place opens."
  defp error_message(:closed), do: "This session has ended or been cancelled."
  defp error_message(:expired), do: "The session's end time has passed."
  defp error_message(:forbidden), do: "Only the host can do that."
  defp error_message(:not_found), do: "This session could not be found."
  defp error_message(:reason_required), do: "Add a reason or confirmation note before continuing."
  defp error_message(:reason_too_long), do: "Keep your note under 500 characters."
  defp error_message(:not_ready), do: "The required number of participants has not committed yet."
  defp error_message(:not_started), do: "The scheduled start time has not arrived yet."
  defp error_message(:access_unconfirmed), do: "Confirm access to the place before starting."
  defp error_message(:not_active), do: "The host must start the session first."
  defp error_message(:not_joined), do: "Join the session first."
  defp error_message(:commit_first), do: "Commit before checking in to this session."

  defp error_message(:not_required),
    do: "This activity allows participation without a commitment."

  defp error_message(_), do: "That change couldn't be saved. Refresh and try again."

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_player={@current_player} active={:hobbies}>
      <div class="flex items-center justify-between gap-3">
        <div>
          <p class="text-caption">FU · time to do something</p>
          <h1 class="text-h1">Hobbies, together.</h1>
        </div>
        <.link :if={@live_action == :index} navigate={~p"/hobbies/new"} class="btn btn-primary">
          Host a session
        </.link>
        <.link :if={@live_action != :index} navigate={~p"/hobbies"} class="text-caption">
          All sessions
        </.link>
      </div>

      <%= if @live_action == :index do %>
        <p class="fu-ink-soft">Find a game, practice a skill, or simply enjoy being there.</p>
        <.form for={to_form(%{"hobby" => @filter}, as: :filter)} id="hobby-filter" phx-change="filter">
          <.input
            name="filter[hobby]"
            value={@filter}
            label="Filter by hobby"
            placeholder="e.g. futsal or guitar"
            phx-debounce="250"
          />
        </.form>
        <div id="hobby-sessions" phx-update="stream" class="space-y-3">
          <p id="no-hobby-sessions" class="hidden only:block fu-card p-6">
            No upcoming sessions here yet. Host the first one.
          </p>
          <article
            :for={{dom_id, session} <- @streams.sessions}
            id={dom_id}
            class="fu-card p-5 space-y-2"
          >
            <p class="text-caption">{session.hobby} · {label(session.mode)}</p>
            <h2 class="text-h2">
              <.link navigate={~p"/hobbies/#{session.id}"}>{session.title}</.link>
            </h2>
            <p>{session.place}</p>
            <time datetime={DateTime.to_iso8601(session.starts_at)}>
              {fmt_time(session.starts_at)}
            </time>
            <div class="flex justify-between gap-3 text-sm fu-ink-soft">
              <span>{Hobbies.occupied(session)} / {session.capacity} joined</span>
              <span>
                {if session.access_status == "host_confirmed",
                  do: "Access confirmed by host",
                  else: "Access pending"}
              </span>
            </div>
          </article>
        </div>
      <% end %>

      <%= if @live_action == :new do %>
        <p class="fu-ink-soft">Choose the activity and the commitment it actually needs.</p>
        <.form
          for={@session_form}
          id="hobby-session-form"
          phx-submit="create"
          class="fu-card p-5 space-y-3"
        >
          <.input field={@session_form[:title]} label="Session name" required maxlength="120" />
          <.input
            field={@session_form[:hobby]}
            label="Hobby"
            placeholder="Futsal, guitar, table tennis…"
            required
            maxlength="60"
          />
          <.input
            field={@session_form[:mode]}
            type="select"
            label="How people participate"
            options={[
              {"Open presence · come and go", "open"},
              {"Practice · learn together", "practice"},
              {"Committed · people rely on you", "committed"}
            ]}
          />
          <div class="grid grid-cols-2 gap-3">
            <.input
              field={@session_form[:category]}
              type="select"
              label="Interest"
              options={Fu.Hobbies.Discovery.categories()}
            />
            <.input
              field={@session_form[:kind]}
              type="select"
              label="Format"
              options={Fu.Hobbies.Discovery.kinds()}
            />
          </div>
          <.input field={@session_form[:place]} label="Where" required maxlength="200" />
          <p class="text-sm fu-ink-soft">
            Creating a session does not reserve a venue. Confirm access with its operator before starting.
          </p>
          <.input
            field={@session_form[:starts_at]}
            type="text"
            label="Starts · include timezone (+02:00 or Z)"
            placeholder="2026-10-23T19:00:00+02:00"
            required
          />
          <.input
            field={@session_form[:ends_at]}
            type="text"
            label="Ends · include timezone (+02:00 or Z)"
            placeholder="2026-10-23T20:00:00+02:00"
            required
          />
          <div class="grid grid-cols-2 gap-3">
            <.input
              field={@session_form[:capacity]}
              type="number"
              label="Places"
              min="1"
              max="1000"
              required
            />
            <.input
              field={@session_form[:min_participants]}
              type="number"
              label="Minimum participants"
              min="1"
              required
            />
          </div>
          <button id="create-session" class="btn btn-primary w-full" phx-disable-with="Saving…">
            Create session
          </button>
        </.form>
      <% end %>

      <%= if @live_action == :show do %>
        <%= if @session do %>
          <article id="session-detail" class="fu-card p-5 space-y-3">
            <.link
              :if={@session.host_id == @current_player.id || present?(@member)}
              navigate={~p"/hobbies/#{@session.id}/assistant"}
              class="btn btn-sm"
              id="open-assistant"
            >
              Open event assistant
            </.link>
            <p class="text-caption">{@session.hobby} · {label(@session.mode)} · {@session.status}</p>
            <h2 class="text-h1">{@session.title}</h2>
            <p>{@session.place}</p>
            <p>
              <time datetime={DateTime.to_iso8601(@session.starts_at)}>
                {fmt_time(@session.starts_at)}
              </time>
              → {fmt_time(@session.ends_at)}
            </p>
            <p>
              Hosted by {@session.host.display_name} · {Hobbies.occupied(@session)} / {@session.capacity} joined
            </p>
            <p :if={@session.mode == "committed"} class="fu-ink-soft">
              Joining expresses interest. Commit separately when others can rely on you. Explain a withdrawal after committing.
            </p>
            <p :if={@session.mode != "committed"} class="fu-ink-soft">
              Join, listen, practice or simply stay. You can leave freely.
            </p>
            <p
              :if={@session.access_status == "pending"}
              id="access-pending"
              class="text-[var(--fu-warning)]"
            >
              Access pending · the host still needs to confirm the place.
            </p>
            <div :if={@session.access_status == "host_confirmed"} id="access-confirmed">
              <p>Access confirmed by host</p>
              <p class="text-sm fu-ink-soft">{@session.access_note}</p>
            </div>
            <p :if={@session.status == "cancelled"} id="session-cancelled" role="status">
              Cancelled: {@session.cancellation_reason}
            </p>
            <p :if={@session.status == "completed"} id="session-completed" role="status">
              Session completed. Participation history is retained.
            </p>
          </article>

          <div :if={!closed?(@session)} class="fu-card p-5 space-y-3">
            <button
              :if={!present?(@member)}
              id="join-session"
              phx-click="join"
              class="btn btn-primary"
              phx-disable-with="Joining…"
            >
              Join session
            </button>
            <button
              :if={@member && @member.status == "joined" && @session.mode == "committed"}
              id="commit-session"
              phx-click="commit"
              class="btn btn-primary"
              phx-disable-with="Saving…"
            >
              Commit to attend
            </button>
            <button
              :if={present?(@member) && @session.status == "active" && @member.status != "attended"}
              id="attend-session"
              phx-click="attend"
              class="btn btn-primary"
            >
              I'm here
            </button>
            <p :if={@member && @member.status == "attended"} id="attendance-recorded">
              Your check-in is recorded.
            </p>
            <.form
              :if={present?(@member)}
              for={@leave_form}
              id="leave-session-form"
              phx-submit="leave"
              class="space-y-2"
            >
              <.input
                field={@leave_form[:reason]}
                label={if @member.committed_at, do: "Reason for withdrawing", else: "Optional note"}
                maxlength="500"
                required={@member.committed_at != nil}
              />
              <button class="btn" phx-disable-with="Saving…">Leave session</button>
            </.form>
          </div>

          <section
            :if={@session.host_id == @current_player.id && !closed?(@session)}
            id="host-controls"
            class="fu-card p-5 space-y-4"
          >
            <h3 class="text-h3">Host controls</h3>
            <.form
              :if={@session.access_status == "pending"}
              for={@access_form}
              id="confirm-access-form"
              phx-submit="confirm-access"
            >
              <.input
                field={@access_form[:note]}
                label="How did you confirm access?"
                placeholder="e.g. operator confirmed the room and time"
                required
                maxlength="500"
              />
              <button class="btn" phx-disable-with="Saving…">Confirm access</button>
            </.form>
            <button
              :if={@session.status == "scheduled"}
              id="start-session"
              phx-click="start"
              class="btn btn-primary"
            >
              Start session
            </button>
            <button
              :if={@session.status == "active"}
              id="finish-session"
              phx-click="finish"
              class="btn btn-primary"
            >
              Finish session
            </button>
            <.form for={@cancel_form} id="cancel-session-form" phx-submit="cancel">
              <.input
                field={@cancel_form[:reason]}
                label="Reason for cancellation"
                required
                maxlength="500"
              />
              <button
                class="btn"
                phx-disable-with="Cancelling…"
                data-confirm="Cancel this session for all participants?"
              >
                Cancel session
              </button>
            </.form>
          </section>

          <section class="fu-card p-5 space-y-3">
            <h3 class="text-h3">Participants</h3>
            <div id="hobby-participants" phx-update="stream" class="space-y-2">
              <p id="no-hobby-participants" class="hidden only:block fu-ink-soft">
                No participants yet.
              </p>
              <div
                :for={{dom_id, member} <- @streams.participants}
                id={dom_id}
                class="flex justify-between gap-3"
              >
                <span>{member.player.display_name}</span><span class="fu-ink-soft">{member.status}</span>
              </div>
            </div>
          </section>
          <section
            :if={@session.host_id == @current_player.id || @member}
            class="fu-card p-5 space-y-3"
          >
            <h3 class="text-h3">Session history</h3>
            <div id="hobby-history" phx-update="stream" class="space-y-2">
              <div :for={{dom_id, event} <- @streams.events} id={dom_id} class="text-sm fu-ink-soft">
                {event.actor.display_name} · {String.replace(event.action, "_", " ")} · {fmt_time(
                  event.inserted_at
                )}
              </div>
            </div>
          </section>
        <% else %>
          <div id="session-not-found" class="fu-card p-6">
            This session could not be found. <.link navigate={~p"/hobbies"}>Browse sessions</.link>
          </div>
        <% end %>
      <% end %>
    </Layouts.app>
    """
  end
end
