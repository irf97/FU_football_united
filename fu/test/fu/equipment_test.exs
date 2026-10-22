defmodule Fu.EquipmentTest do
  use Fu.DataCase, async: true
  alias Fu.{Equipment, Hobbies}

  defp event(host, offset \\ 3600) do
    at = DateTime.utc_now() |> DateTime.add(offset) |> DateTime.truncate(:second)

    {:ok, session} =
      Hobbies.create_session(host, %{
        title: "Gear session",
        hobby: "futsal",
        place: "Campus",
        mode: "open",
        starts_at: at,
        ends_at: DateTime.add(at, 3600),
        capacity: 8,
        min_participants: 1
      })

    session
  end

  test "inventory ownership is server-set and private" do
    owner = player_fixture()
    stranger = player_fixture()

    assert {:ok, asset} =
             Equipment.create_asset(owner, %{
               name: "Ball",
               home_zone: "Shelf A",
               beacon_id: "ball-1",
               owner_id: stranger.id
             })

    assert asset.owner_id == owner.id
    assert [%{id: id}] = Equipment.list_assets(owner)
    assert id == asset.id
    assert Equipment.list_assets(stranger) == []
    assert {:error, :forbidden} = Equipment.report_location(asset.id, stranger, "Room B")

    assert {:error, %Ecto.Changeset{}} =
             Equipment.create_asset(owner, %{name: "Duplicate", beacon_id: "ball-1"})
  end

  test "reservations serialize ownership, interval conflicts and idempotency" do
    owner = player_fixture()
    stranger = player_fixture()
    {:ok, asset} = Equipment.create_asset(owner, %{name: "Table tennis set"})
    a = event(owner)
    overlapping = event(owner, 5400)
    adjacent = event(owner, 7200)
    assert {:error, :forbidden} = Equipment.reserve(asset.id, a.id, stranger)
    assert {:ok, reservation} = Equipment.reserve(asset.id, a.id, owner)
    assert {:ok, same} = Equipment.reserve(asset.id, a.id, owner)
    assert same.id == reservation.id
    assert {:error, :conflict} = Equipment.reserve(asset.id, overlapping.id, owner)
    assert {:ok, next} = Equipment.reserve(asset.id, adjacent.id, owner)
    assert {:ok, _} = Equipment.release(reservation.id, owner)
    assert {:ok, _} = Equipment.release(next.id, owner)
    assert {:ok, _} = Equipment.reserve(asset.id, overlapping.id, owner)
  end

  test "maintenance and closed sessions block allocation; location does not change condition" do
    owner = player_fixture()
    {:ok, asset} = Equipment.create_asset(owner, %{name: "Guitar", condition: "maintenance"})
    session = event(owner)
    assert {:error, :not_ready} = Equipment.reserve(asset.id, session.id, owner)
    {:ok, _} = Equipment.report_location(asset.id, owner, "Practice room")

    assert [%{condition: "maintenance", location: %{source: "manual"}}] =
             Equipment.list_assets(owner)

    {:ok, _} = Equipment.set_condition(asset.id, owner, "ready")
    {:ok, _} = Hobbies.cancel(session.id, owner, "Room unavailable")
    assert {:error, :closed} = Equipment.reserve(asset.id, session.id, owner)
  end

  test "receiver tokens are scoped, revocable and deduplicate actual observations" do
    owner = player_fixture()
    other = player_fixture()
    {:ok, asset} = Equipment.create_asset(owner, %{name: "Ball", beacon_id: "ball-tag"})

    {:ok, receiver, token} =
      Equipment.create_receiver(owner, %{name: "Room receiver", zone: "Court A"})

    assert receiver.token_hash != token

    payload = %{
      "beacon_id" => "ball-tag",
      "message_id" => "sample-1",
      "observed_at" => DateTime.to_iso8601(DateTime.utc_now() |> DateTime.truncate(:second)),
      "rssi" => -60
    }

    assert {:error, :unauthorized} = Equipment.ingest("invalid", payload)
    assert {:ok, first} = Equipment.ingest(token, payload)
    assert first.asset_id == asset.id
    assert first.source == "receiver_report"
    assert first.zone == "Court A"
    assert {:ok, same} = Equipment.ingest(token, payload)
    assert same.id == first.id

    assert {:error, :idempotency_conflict} =
             Equipment.ingest(token, Map.put(payload, "rssi", -80))

    {:ok, _, foreign} = Equipment.create_receiver(other, %{name: "Other", zone: "Elsewhere"})
    assert {:error, :not_found} = Equipment.ingest(foreign, payload)
    assert {:error, :forbidden} = Equipment.revoke_receiver(receiver.id, other)
    assert {:ok, _} = Equipment.revoke_receiver(receiver.id, owner)

    assert {:error, :unauthorized} =
             Equipment.ingest(token, Map.put(payload, "message_id", "sample-2"))
  end

  test "out of order reports cannot move current location backwards" do
    owner = player_fixture()
    {:ok, _} = Equipment.create_asset(owner, %{name: "Ball", beacon_id: "ball-tag"})
    {:ok, _, token} = Equipment.create_receiver(owner, %{name: "Station", zone: "Court"})
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    payload = %{
      "beacon_id" => "ball-tag",
      "message_id" => "new",
      "observed_at" => DateTime.to_iso8601(now),
      "rssi" => -60
    }

    {:ok, _} = Equipment.ingest(token, payload)

    {:ok, older} =
      Equipment.ingest(
        token,
        Map.merge(payload, %{
          "message_id" => "old",
          "observed_at" => DateTime.to_iso8601(DateTime.add(now, -300))
        })
      )

    [asset] = Equipment.list_assets(owner)
    assert DateTime.compare(asset.location.observed_at, older.observed_at) == :gt
    assert asset.location.freshness == "fresh"
  end
end
