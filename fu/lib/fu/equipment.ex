defmodule Fu.Equipment do
  @moduledoc """
  Owner-scoped inventory, interval reservations and source-labeled zone observations.
  Receiver credentials identify a collector, never verify physical presence. All writers
  lock the relevant asset; reservation checks and writes share one transaction.
  """
  import Ecto.Query
  alias Fu.{Repo, Hobbies}
  alias Fu.Accounts.Player
  alias Fu.Equipment.{Asset, Receiver, Observation, Reservation, Rules}
  alias Fu.Hobbies.{Session, Participant}

  def subscribe(%Player{id: id}), do: Phoenix.PubSub.subscribe(Fu.PubSub, "equipment:#{id}")

  def change_asset(attrs \\ %{}), do: Asset.changeset(%Asset{}, attrs)
  def change_receiver(attrs \\ %{}), do: Receiver.changeset(%Receiver{}, attrs)

  def create_asset(%Player{} = owner, attrs) do
    case Repo.insert(Asset.changeset(%Asset{owner_id: owner.id}, attrs)) do
      {:ok, asset} ->
        notify(asset)
        {:ok, asset}

      error ->
        error
    end
  end

  def list_assets(%Player{id: id}) do
    Repo.all(
      from a in Asset, where: a.owner_id == ^id, order_by: [asc: a.name, asc: a.id], limit: 100
    )
    |> decorate()
  end

  def list_receivers(%Player{id: id}) do
    Repo.all(
      from r in Receiver,
        where: r.owner_id == ^id,
        order_by: [desc: r.id],
        limit: 50,
        select: map(r, [:id, :name, :zone, :revoked_at])
    )
  end

  def create_receiver(%Player{} = owner, attrs) do
    token = "fu-eq-" <> Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)
    receiver = %Receiver{owner_id: owner.id, token_hash: hash(token)}

    case Repo.insert(Receiver.changeset(receiver, attrs)) do
      {:ok, receiver} ->
        Phoenix.PubSub.broadcast(Fu.PubSub, "equipment:#{owner.id}", :equipment_changed)
        {:ok, receiver, token}

      error ->
        error
    end
  end

  def revoke_receiver(id, %Player{} = owner) do
    result =
      Repo.transaction(fn ->
        receiver = locked!(Receiver, id)
        owner!(receiver, owner)
        Repo.update!(Ecto.Changeset.change(receiver, revoked_at: receiver.revoked_at || now()))
      end)

    if match?({:ok, _}, result),
      do: Phoenix.PubSub.broadcast(Fu.PubSub, "equipment:#{owner.id}", :equipment_changed)

    result
  end

  def report_location(id, %Player{} = owner, zone) do
    mutate_asset(id, owner, fn asset ->
      zone = if is_binary(zone), do: String.trim(zone), else: ""
      if byte_size(zone) not in 1..120, do: Repo.rollback(:invalid_zone)

      Repo.insert!(%Observation{
        asset_id: asset.id,
        source: "manual",
        zone: zone,
        observed_at: now()
      })
    end)
  end

  def set_condition(id, %Player{} = owner, condition) do
    mutate_asset(id, owner, fn asset ->
      case Repo.update(Asset.changeset(asset, %{condition: condition})) do
        {:ok, asset} -> asset
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
  end

  @doc "Attach your own gear to an event you host or have joined; this shares its current zone during the event."
  def reserve(asset_id, session_id, %Player{} = owner) do
    result =
      Repo.transaction(fn ->
        session = locked!(Session, session_id)
        unless can_view?(session, owner), do: Repo.rollback(:forbidden)

        if session.status not in ["scheduled", "active"] or
             DateTime.compare(session.ends_at, now()) != :gt,
           do: Repo.rollback(:closed)

        asset = locked!(Asset, asset_id)
        owner!(asset, owner)
        if asset.condition != "ready", do: Repo.rollback(:not_ready)
        existing = Repo.get_by(Reservation, asset_id: asset.id, session_id: session.id)

        if existing && existing.status == "reserved" do
          existing
        else
          conflict =
            from r in Reservation,
              join: s in Session,
              on: s.id == r.session_id,
              where:
                r.asset_id == ^asset.id and r.status == "reserved" and
                  s.status in ["scheduled", "active"] and s.ends_at > ^now() and
                  r.starts_at < ^session.ends_at and r.ends_at > ^session.starts_at

          if Repo.exists?(conflict), do: Repo.rollback(:conflict)
          reservation = existing || %Reservation{asset_id: asset.id, session_id: session.id}

          Repo.insert_or_update!(
            Ecto.Changeset.change(reservation,
              status: "reserved",
              starts_at: session.starts_at,
              ends_at: session.ends_at
            )
          )
        end
      end)

    after_reservation(result)
  end

  def release(id, %Player{} = owner) do
    result =
      Repo.transaction(fn ->
        reservation = Repo.get(Reservation, id!(id)) || Repo.rollback(:not_found)
        asset = locked!(Asset, reservation.asset_id)
        owner!(asset, owner)
        reservation = Repo.get!(Reservation, reservation.id)
        Repo.update!(Ecto.Changeset.change(reservation, status: "released"))
      end)

    after_reservation(result)
  end

  def session_assets(%Session{} = session, %Player{} = viewer) do
    session = Repo.get(Session, session.id)

    if session && can_view?(session, viewer) do
      reservations =
        Repo.all(
          from r in Reservation,
            where: r.session_id == ^session.id and r.status == "reserved",
            order_by: r.id,
            limit: 100
        )

      ids = Enum.map(reservations, & &1.asset_id)

      assets =
        Repo.all(from a in Asset, where: a.id in ^ids) |> decorate() |> Map.new(&{&1.id, &1})

      Enum.map(reservations, fn reservation ->
        asset = Map.fetch!(assets, reservation.asset_id)

        location =
          if session.status in ["scheduled", "active"] and
               DateTime.compare(session.ends_at, now()) == :gt,
             do: asset.location,
             else: Rules.location(nil, now())

        %{
          id: asset.id,
          reservation_id: reservation.id,
          name: asset.name,
          condition: asset.condition,
          location: location
        }
      end)
    else
      []
    end
  end

  def reservation_active?(reservation) do
    reservation.status == "reserved" and reservation.session.status in ["scheduled", "active"] and
      DateTime.compare(reservation.ends_at, now()) == :gt
  end

  @doc "Ingest a bounded, authenticated collector report. A report is not proof of physical location."
  def ingest(token, payload) when is_binary(token) and byte_size(token) in 20..160 do
    result =
      Repo.transaction(fn ->
        receiver =
          Repo.one(
            from r in Receiver,
              where: r.token_hash == ^hash(token) and is_nil(r.revoked_at),
              lock: "FOR UPDATE"
          ) || Repo.rollback(:unauthorized)

        value =
          case Rules.observation(payload, now()) do
            {:ok, value} -> value
            {:error, error} -> Repo.rollback(error)
          end

        asset =
          Repo.one(
            from a in Asset,
              where: a.owner_id == ^receiver.owner_id and a.beacon_id == ^value.beacon_id,
              lock: "FOR UPDATE"
          ) || Repo.rollback(:not_found)

        existing =
          Repo.get_by(Observation, receiver_id: receiver.id, message_id: value.message_id)

        cond do
          existing && existing.asset_id == asset.id && existing.observed_at == value.observed_at &&
              existing.rssi == value.rssi ->
            existing

          existing ->
            Repo.rollback(:idempotency_conflict)

          Repo.aggregate(
            from(o in Observation,
              where: o.receiver_id == ^receiver.id and o.inserted_at > ^DateTime.add(now(), -60)
            ),
            :count
          ) >= 120 ->
            Repo.rollback(:rate_limited)

          true ->
            Repo.insert!(%Observation{
              asset_id: asset.id,
              receiver_id: receiver.id,
              source: "receiver_report",
              zone: receiver.zone,
              observed_at: value.observed_at,
              message_id: value.message_id,
              rssi: value.rssi
            })
        end
      end)

    case result do
      {:ok, observation} ->
        notify(Repo.get!(Asset, observation.asset_id))
        result

      _ ->
        result
    end
  end

  def ingest(_, _), do: {:error, :unauthorized}

  defp decorate([]), do: []

  defp decorate(assets) do
    ids = Enum.map(assets, & &1.id)

    observations =
      Repo.all(
        from o in Observation,
          where: o.asset_id in ^ids,
          distinct: o.asset_id,
          order_by: [asc: o.asset_id, desc: o.observed_at, desc: o.id]
      )
      |> Map.new(&{&1.asset_id, &1})

    assets
    |> Repo.preload(
      reservations:
        from(r in Reservation,
          where: r.status == "reserved",
          order_by: r.starts_at,
          preload: [:session]
        )
    )
    |> Enum.map(&%{&1 | location: Rules.location(Map.get(observations, &1.id), now())})
  end

  defp can_view?(session, player) do
    session.host_id == player.id or
      Repo.exists?(
        from p in Participant,
          where:
            p.session_id == ^session.id and p.player_id == ^player.id and
              p.status in ["joined", "committed", "attended"]
      )
  end

  defp mutate_asset(id, owner, fun) do
    result =
      Repo.transaction(fn ->
        asset = locked!(Asset, id)
        owner!(asset, owner)
        fun.(asset)
      end)

    case result do
      {:ok, _} ->
        notify(Repo.get!(Asset, id!(id)))
        result

      _ ->
        result
    end
  end

  defp after_reservation({:ok, reservation} = result) do
    notify(Repo.get!(Asset, reservation.asset_id))
    Hobbies.broadcast_change(reservation.session_id)
    result
  end

  defp after_reservation(error), do: error

  defp notify(asset) do
    Phoenix.PubSub.broadcast(Fu.PubSub, "equipment:#{asset.owner_id}", :equipment_changed)

    ids =
      Repo.all(
        from r in Reservation,
          where: r.asset_id == ^asset.id and r.status == "reserved",
          select: r.session_id
      )

    Enum.each(ids, &Hobbies.broadcast_change/1)
  end

  defp owner!(%{owner_id: id}, %Player{id: id}), do: :ok
  defp owner!(_, _), do: Repo.rollback(:forbidden)

  defp locked!(schema, id),
    do:
      Repo.one(from row in schema, where: row.id == ^id!(id), lock: "FOR UPDATE") ||
        Repo.rollback(:not_found)

  defp id!(id) when is_integer(id) and id > 0 and id <= 9_223_372_036_854_775_807, do: id

  defp id!(id) when is_binary(id) and byte_size(id) <= 19 do
    case Integer.parse(id) do
      {value, ""} when value > 0 and value <= 9_223_372_036_854_775_807 -> value
      _ -> Repo.rollback(:not_found)
    end
  end

  defp id!(_), do: Repo.rollback(:not_found)
  defp hash(token), do: :crypto.hash(:sha256, token)
  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)
end
