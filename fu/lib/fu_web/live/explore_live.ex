defmodule FuWeb.ExploreLive do
  use FuWeb, :live_view
  alias Fu.Hobbies
  alias Fu.Hobbies.Discovery

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Hobbies.subscribe()

    {:ok,
     socket
     |> assign(
       page_title: "Explore · FU",
       filters: Discovery.normalize(%{}),
       more?: false,
       shown: 0,
       categories: Discovery.categories(),
       kinds: Discovery.kinds()
     )
     |> stream(:events, [], dom_id: &"explore-event-#{&1.id}")
     |> stream(:hobbies, [],
       dom_id: &"explore-hobby-#{Base.url_encode64(&1.name, padding: false)}"
     )}
  end

  @impl true
  def handle_params(params, _uri, socket),
    do: {:noreply, reload(socket, Discovery.normalize(params))}

  @impl true
  def handle_event("filter", %{"filter" => params}, socket) do
    params = params |> Map.put("page", "1") |> Discovery.normalize() |> Discovery.params()
    {:noreply, push_patch(socket, to: ~p"/explore?#{params}")}
  end

  @impl true
  def handle_info({:hobby_session_changed, _id}, socket),
    do: {:noreply, reload(socket, socket.assigns.filters)}

  defp reload(socket, filters) do
    result = Hobbies.discover(filters, socket.assigns.current_player)

    socket
    |> assign(
      filters: filters,
      filter_form: to_form(Discovery.params(filters), as: :filter),
      more?: result.more?,
      shown: length(result.entries)
    )
    |> stream(:events, result.entries, reset: true)
    |> stream(:hobbies, Hobbies.hobby_catalog(), reset: true)
  end

  defp params(filters, overrides), do: filters |> Map.merge(overrides) |> Discovery.params()

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_player={@current_player} active={:explore}>
      <div class="flex items-start justify-between gap-4">
        <div>
          <p class="text-caption">Follow an interest</p>
          <h1 class="text-h1">Find your next thing.</h1>
        </div>
        <.link
          navigate={~p"/hobbies/new"}
          id="explore-create"
          class="rounded-full bg-primary px-4 py-3 text-sm font-semibold text-primary-content"
        >
          Create
        </.link>
      </div>
      <p class="fu-ink-soft">A game, a workshop, a music night. Find people and a place to do it.</p>
      <div class="flex gap-2" aria-label="Event scope">
        <.link
          patch={~p"/explore?#{params(@filters, %{scope: "all", page: 1})}"}
          id="explore-all"
          class={[
            "rounded-full border px-4 py-2 text-sm",
            @filters.scope == "all" && "border-primary text-primary",
            @filters.scope != "all" && "border-white/15"
          ]}
        >
          Explore
        </.link>
        <.link
          patch={~p"/explore?#{params(@filters, %{scope: "mine", page: 1})}"}
          id="explore-mine"
          class={[
            "rounded-full border px-4 py-2 text-sm",
            @filters.scope == "mine" && "border-primary text-primary",
            @filters.scope != "mine" && "border-white/15"
          ]}
        >
          My events
        </.link>
      </div>
      <.form for={@filter_form} id="explore-filter" phx-change="filter" class="fu-card p-4 space-y-3">
        <.input
          field={@filter_form[:q]}
          label="What do you feel like doing?"
          placeholder="Guitar, a workshop, a game…"
          phx-debounce="300"
        />
        <div class="grid grid-cols-2 gap-3">
          <.input
            field={@filter_form[:category]}
            type="select"
            label="Interest"
            options={[{"All interests", ""} | @categories]}
          />
          <.input
            field={@filter_form[:kind]}
            type="select"
            label="Format"
            options={[{"All formats", ""} | @kinds]}
          />
          <.input
            field={@filter_form[:mode]}
            type="select"
            label="Participation"
            options={[
              {"Any style", ""},
              {"Come and go", "open"},
              {"Practice", "practice"},
              {"Commit together", "committed"}
            ]}
          />
          <.input
            field={@filter_form[:place]}
            label="Place"
            placeholder="Campus, park, room…"
            phx-debounce="300"
          />
        </div>
        <.input field={@filter_form[:space]} type="checkbox" label="Show events with space" />
        <.input field={@filter_form[:hobby]} type="hidden" />
        <.input field={@filter_form[:scope]} type="hidden" />
        <.link
          :if={@filters.hobby != ""}
          patch={~p"/explore?#{params(@filters, %{hobby: "", page: 1})}"}
          id="explore-clear-hobby"
          class="text-sm text-primary"
        >
          Clear hobby: {@filters.hobby}
        </.link>
      </.form>
      <div class="flex items-center justify-between">
        <h2 class="text-h2">
          {if @filters.scope == "mine", do: "Your activity", else: "On the horizon"}
        </h2>
        <span class="text-sm fu-ink-soft">{@shown} shown</span>
      </div>
      <div id="explore-events" phx-update="stream" class="space-y-3">
        <div id="explore-empty" class="hidden only:block fu-card p-6 space-y-3">
          <p>No events match these filters yet.</p>
          <.link
            navigate={
              ~p"/hobbies/new?#{%{hobby: @filters.hobby, category: @filters.category, kind: @filters.kind}}"
            }
            class="text-primary"
          >
            Create the first one
          </.link>
        </div>
        <article :for={{dom_id, event} <- @streams.events} id={dom_id} class="fu-card p-5 space-y-3">
          <div class="flex flex-wrap gap-2 text-xs">
            <span class="rounded-full border border-white/15 px-2 py-1">
              {Discovery.category_label(event.category)}
            </span><span class="rounded-full border border-white/15 px-2 py-1">{Discovery.kind_label(event.kind)}</span><span class="px-2 py-1 text-primary">{event.status}</span>
          </div>
          <h3 class="text-h2"><.link navigate={~p"/hobbies/#{event.id}"}>{event.title}</.link></h3>
          <p>{event.hobby} · {event.place}</p>
          <time datetime={DateTime.to_iso8601(event.starts_at)} class="text-sm fu-ink-soft">
            {Calendar.strftime(event.starts_at, "%a %d %b · %H:%M UTC")}
          </time>
          <div class="flex justify-between gap-3 text-sm">
            <span>{Hobbies.occupied(event)} / {event.capacity} joined</span><span>{if event.access_status == "host_confirmed", do: "Access confirmed by host", else: "Access pending"}</span>
          </div>
        </article>
      </div>
      <div class="flex justify-between gap-3">
        <.link
          :if={@filters.page > 1}
          patch={~p"/explore?#{params(@filters, %{page: @filters.page - 1})}"}
          id="explore-previous"
          class="text-primary"
        >
          Previous
        </.link>
        <.link
          :if={@more?}
          patch={~p"/explore?#{params(@filters, %{page: @filters.page + 1})}"}
          id="explore-next"
          class="text-primary"
        >
          More events
        </.link>
      </div>
      <div class="pt-4">
        <h2 class="text-h2">Hobbies happening here</h2>
        <p class="text-sm fu-ink-soft">Any hobby can have an event. These have upcoming activity.</p>
      </div>
      <div id="explore-hobbies" phx-update="stream" class="flex flex-wrap gap-2">
        <p id="explore-no-hobbies" class="hidden only:block text-sm fu-ink-soft">
          Your next interest can be the first.
        </p>
        <.link
          :for={{dom_id, hobby} <- @streams.hobbies}
          id={dom_id}
          patch={~p"/explore?#{params(Discovery.normalize(%{}), %{hobby: hobby.name})}"}
          class="rounded-full border border-white/15 px-3 py-2 text-sm"
        >
          {hobby.name} · {hobby.count}
        </.link>
      </div>
    </Layouts.app>
    """
  end
end
