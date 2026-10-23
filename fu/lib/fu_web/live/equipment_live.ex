defmodule FuWeb.EquipmentLive do
  use FuWeb, :live_view
  alias Fu.{Equipment, Hobbies}

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Equipment.subscribe(socket.assigns.current_player)
      Hobbies.subscribe()
      :timer.send_interval(30_000, :refresh_locations)
    end

    {:ok,
     socket
     |> assign(
       page_title: "Equipment",
       asset_form: to_form(Equipment.change_asset()),
       receiver_form: to_form(Equipment.change_receiver()),
       receiver_token: nil
     )
     |> reload()}
  end

  @impl true
  def handle_event("create-asset", %{"asset" => attrs}, socket) do
    case Equipment.create_asset(socket.assigns.current_player, attrs) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(asset_form: to_form(Equipment.change_asset()))
         |> put_flash(:info, "Equipment added to your inventory.")
         |> reload()}

      {:error, changeset} ->
        {:noreply, assign(socket, asset_form: to_form(changeset))}
    end
  end

  def handle_event("create-receiver", %{"receiver" => attrs}, socket) do
    case Equipment.create_receiver(socket.assigns.current_player, attrs) do
      {:ok, _, token} ->
        {:noreply,
         socket
         |> assign(receiver_form: to_form(Equipment.change_receiver()), receiver_token: token)
         |> reload()}

      {:error, changeset} ->
        {:noreply, assign(socket, receiver_form: to_form(changeset))}
    end
  end

  def handle_event("hide-token", _, socket), do: {:noreply, assign(socket, receiver_token: nil)}

  def handle_event(action, params, socket)
      when action in ["locate", "condition", "reserve", "release", "revoke"] do
    player = socket.assigns.current_player

    result =
      case action do
        "locate" ->
          Equipment.report_location(params["id"], player, get_in(params, ["location", "zone"]))

        "condition" ->
          Equipment.set_condition(params["id"], player, get_in(params, ["asset", "condition"]))

        "reserve" ->
          Equipment.reserve(params["id"], get_in(params, ["allocation", "session_id"]), player)

        "release" ->
          Equipment.release(params["id"], player)

        "revoke" ->
          Equipment.revoke_receiver(params["id"], player)
      end

    socket =
      case result do
        {:ok, _} -> put_flash(socket, :info, "Equipment update recorded.")
        {:error, error} -> put_flash(socket, :error, error_message(error))
      end

    {:noreply, reload(socket)}
  end

  def handle_event(_, _, socket), do: {:noreply, socket}

  @impl true
  def handle_info(message, socket) when message in [:equipment_changed, :refresh_locations],
    do: {:noreply, reload(socket)}

  def handle_info({:hobby_session_changed, _}, socket), do: {:noreply, reload(socket)}

  defp reload(socket) do
    assets = Equipment.list_assets(socket.assigns.current_player)
    sessions = Hobbies.discover(%{"scope" => "mine"}, socket.assigns.current_player).entries

    options =
      sessions
      |> Enum.filter(
        &(&1.status in ["scheduled", "active"] and
            DateTime.compare(&1.ends_at, DateTime.utc_now()) == :gt)
      )
      |> Enum.map(&{&1.title, &1.id})

    socket
    |> assign(
      zones:
        Enum.group_by(assets, &(&1.location.zone || "No observation"))
        |> Enum.sort_by(&elem(&1, 0)),
      receivers: Equipment.list_receivers(socket.assigns.current_player),
      event_options: options
    )
    |> stream(:assets, assets, reset: true, dom_id: &"equipment-#{&1.id}")
  end

  defp error_message(:conflict),
    do:
      "This item is reserved for an overlapping event. Release that reservation or choose another item."

  defp error_message(:not_ready), do: "Mark the item's condition ready before reserving it."
  defp error_message(:closed), do: "Choose an upcoming or active event."
  defp error_message(:invalid_zone), do: "Enter a zone between 1 and 120 characters."

  defp error_message(:forbidden),
    do:
      "Only the owner can change gear, and reservations require an event you host or have joined."

  defp error_message(_), do: "That update could not be saved. Refresh and check your selection."
  defp source("manual"), do: "Manual report"
  defp source("receiver_report"), do: "Receiver report"
  defp source(_), do: "No location report"

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_player={@current_player} active={:equipment}>
      <div class="flex items-start justify-between gap-4">
        <div>
          <p class="text-caption">Your inventory</p>
          <h1 class="text-h1">Equipment</h1>
        </div>
        <.link navigate={~p"/explore"} class="btn btn-sm">Explore events</.link>
      </div>
      <p class="fu-ink-soft">
        Keep track of gear, reserve it for an event and see the last reported zone.
      </p>
      <section id="zone-map" class="fu-card p-5 space-y-3" aria-label="Equipment zone map">
        <h2 class="text-h2">Zone map</h2>
        <p class="text-sm fu-ink-soft">
          Reports show a collector's zone or your manual entry. Fresh means reported within two minutes. Check the item before use.
        </p>
        <p :if={@zones == []}>Add your first item to start mapping your gear.</p>
        <div :for={{zone, assets} <- @zones} class="border border-base-300 rounded-xl p-3 space-y-2">
          <h3 class="font-semibold">{zone}</h3>
          <div class="flex flex-wrap gap-2">
            <span :for={asset <- assets} class="badge badge-outline h-auto py-2">
              {asset.name} · {asset.location.freshness}
            </span>
          </div>
        </div>
      </section>
      <details class="fu-card p-5" open>
        <summary class="text-h2 cursor-pointer">Add equipment</summary>
        <.form for={@asset_form} id="equipment-form" phx-submit="create-asset" class="space-y-3 mt-4">
          <.input field={@asset_form[:name]} label="Item name" required maxlength="120" />
          <.input field={@asset_form[:hobby]} label="Hobby · optional" maxlength="60" />
          <.input field={@asset_form[:home_zone]} label="Usual storage zone" maxlength="120" required />
          <.input field={@asset_form[:beacon_id]} label="Tag identifier · optional" maxlength="120" />
          <p class="text-sm fu-ink-soft">
            Use the exact identifier supplied by your collector. Your inventory stays private until you reserve an item for an event.
          </p>
          <button class="btn btn-primary" phx-disable-with="Saving…">Add item</button>
        </.form>
      </details>
      <div id="equipment-list" phx-update="stream" class="space-y-4">
        <p id="equipment-empty" class="hidden only:block fu-card p-5">Your inventory is empty.</p>
        <article :for={{dom_id, asset} <- @streams.assets} id={dom_id} class="fu-card p-5 space-y-4">
          <div>
            <h2 class="text-h2">{asset.name}</h2>
            <p class="text-sm fu-ink-soft">
              Usual zone: {asset.home_zone} · Condition: {asset.condition}
            </p>
          </div>
          <div
            data-source={asset.location.source || "unknown"}
            data-freshness={asset.location.freshness}
            class="space-y-1"
          >
            <p>
              {asset.location.zone || "Location unknown"} · {source(asset.location.source)} · {asset.location.freshness}
            </p>
            <time
              :if={asset.location.observed_at}
              datetime={DateTime.to_iso8601(asset.location.observed_at)}
              class="text-sm fu-ink-soft"
            >
              {Calendar.strftime(asset.location.observed_at, "%d %b %H:%M:%S UTC")}
            </time>
          </div>
          <.form
            for={to_form(%{"zone" => ""}, as: :location)}
            id={"locate-#{asset.id}"}
            phx-submit="locate"
            phx-value-id={asset.id}
            class="space-y-2"
          >
            <.input
              id={"location-zone-#{asset.id}"}
              name="location[zone]"
              value=""
              label="Report a zone manually"
              required
              maxlength="120"
            />
            <button class="btn btn-sm" phx-disable-with="Saving…">Save manual location</button>
          </.form>
          <.form
            for={to_form(%{"condition" => asset.condition}, as: :asset)}
            id={"condition-#{asset.id}"}
            phx-submit="condition"
            phx-value-id={asset.id}
            class="space-y-2"
          >
            <.input
              id={"condition-select-#{asset.id}"}
              name="asset[condition]"
              value={asset.condition}
              type="select"
              label="Owner-declared condition"
              options={[{"Ready", "ready"}, {"Maintenance", "maintenance"}, {"Retired", "retired"}]}
            />
            <button class="btn btn-sm" phx-disable-with="Saving…">Save condition</button>
          </.form>
          <div
            :for={reservation <- Enum.filter(asset.reservations, &Equipment.reservation_active?/1)}
            id={"reservation-#{reservation.id}"}
            class="border-t border-base-300 pt-3 flex items-center justify-between gap-2"
          >
            <.link navigate={~p"/hobbies/#{reservation.session_id}"}>
              {reservation.session.title}
            </.link>
            <button class="btn btn-sm" phx-click="release" phx-value-id={reservation.id}>
              Release
            </button>
          </div>
          <.form
            :if={@event_options != [] && asset.condition == "ready"}
            for={to_form(%{"session_id" => ""}, as: :allocation)}
            id={"reserve-#{asset.id}"}
            phx-submit="reserve"
            phx-value-id={asset.id}
            class="space-y-2"
          >
            <.input
              id={"allocation-session-#{asset.id}"}
              name="allocation[session_id]"
              value=""
              type="select"
              label="Reserve for your event"
              prompt="Choose an event"
              options={@event_options}
              required
            />
            <p class="text-sm fu-ink-soft">
              The host and current participants can see this item's name, condition and reported zone until the event closes.
            </p>
            <button class="btn btn-sm" phx-disable-with="Reserving…">Reserve and share</button>
          </.form>
        </article>
      </div>
      <details id="receiver-settings" open={@receiver_token != nil} class="fu-card p-5 space-y-3">
        <summary class="text-h2 cursor-pointer">Connect a zone receiver</summary>
        <p class="mt-3 text-sm fu-ink-soft">
          Give your receiver a home zone. Tagged equipment appears here with its last reported place and time.
        </p>
        <.form for={@receiver_form} id="receiver-form" phx-submit="create-receiver" class="space-y-3">
          <.input field={@receiver_form[:name]} label="Receiver name" required maxlength="120" />
          <.input field={@receiver_form[:zone]} label="Receiver zone" required maxlength="120" />
          <button class="btn" phx-disable-with="Creating…">Create receiver credential</button>
        </.form>
        <div
          :if={@receiver_token}
          id="receiver-token"
          class="border border-primary rounded-xl p-3 space-y-3"
        >
          <p>
            Copy this credential into your collector. It is shown once and allows reports for your tagged gear. Keep it private.
          </p>
          <code class="block break-all select-all">{@receiver_token}</code>
          <button class="btn btn-sm" phx-click="hide-token">I saved it · hide</button>
        </div>
        <div
          :for={receiver <- @receivers}
          id={"receiver-#{receiver.id}"}
          class="flex flex-wrap items-center justify-between gap-3 border-t border-base-300 pt-3"
        >
          <span>
            {receiver.name} · {receiver.zone} · {if receiver.revoked_at, do: "revoked", else: "active"}
          </span>
          <button
            :if={!receiver.revoked_at}
            phx-click="revoke"
            phx-value-id={receiver.id}
            class="btn btn-sm"
          >
            Revoke credential
          </button>
        </div>
      </details>
    </Layouts.app>
    """
  end
end
