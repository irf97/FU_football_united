defmodule Fu.EquipmentRulesTest do
  use ExUnit.Case, async: true
  alias Fu.Equipment.Rules
  @now ~U[2026-10-22 12:00:00Z]

  test "receiver observations are bounded and cannot set authority or availability" do
    payload = %{
      "beacon_id" => "ball-tag",
      "message_id" => "message-1",
      "observed_at" => "2026-10-22T12:00:00Z",
      "rssi" => -55,
      "owner_id" => 99,
      "zone" => "Forged",
      "source" => "verified",
      "condition" => "ready"
    }

    assert {:ok, value} = Rules.observation(payload, @now)
    assert value.beacon_id == "ball-tag"
    assert value.message_id == "message-1"
    refute Map.has_key?(value, :owner_id)
    refute Map.has_key?(value, :zone)
    refute Map.has_key?(value, :condition)

    for extra <- [
          %{"observed_at" => "2026-10-22T12:05:00Z"},
          %{"observed_at" => "2026-10-22T11:00:00Z"},
          %{"rssi" => "strong"},
          %{"message_id" => ""},
          %{"beacon_id" => []}
        ] do
      assert {:error, :invalid_observation} = Rules.observation(Map.merge(payload, extra), @now)
    end
  end

  test "location is a source-labeled observation, becomes stale and never implies readiness" do
    assert Rules.location(nil, @now) == %{
             freshness: "unknown",
             zone: nil,
             source: nil,
             observed_at: nil
           }

    fresh = Rules.location(%{zone: "Room A", source: "receiver_report", observed_at: @now}, @now)
    assert fresh.freshness == "fresh"
    assert fresh.source == "receiver_report"
    refute Map.has_key?(fresh, :available)
    refute Map.has_key?(fresh, :distance)

    assert Rules.location(
             %{zone: "Room A", source: "manual", observed_at: @now},
             DateTime.add(@now, 121)
           ).freshness == "stale"
  end
end
