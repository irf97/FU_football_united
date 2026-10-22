defmodule Fu.Equipment.Rules do
  @moduledoc "Bounded receiver observations and explicit location freshness."

  def observation(payload, now) when is_map(payload) do
    with beacon when is_binary(beacon) <- payload["beacon_id"],
         true <- byte_size(beacon) in 1..120 and String.trim(beacon) == beacon,
         message when is_binary(message) <- payload["message_id"],
         true <- byte_size(message) in 1..120 and String.trim(message) == message,
         timestamp when is_binary(timestamp) <- payload["observed_at"],
         {:ok, observed_at, 0} <- DateTime.from_iso8601(timestamp),
         age = DateTime.diff(now, observed_at, :second),
         true <- age >= -5 and age <= 600,
         rssi <- payload["rssi"],
         true <- is_nil(rssi) or (is_integer(rssi) and rssi in -127..20) do
      {:ok,
       %{
         beacon_id: beacon,
         message_id: message,
         observed_at: DateTime.truncate(observed_at, :second),
         rssi: rssi
       }}
    else
      _ -> {:error, :invalid_observation}
    end
  end

  def observation(_, _), do: {:error, :invalid_observation}

  def location(nil, _),
    do: %{freshness: "unknown", zone: nil, source: nil, observed_at: nil}

  def location(observation, now) do
    %{
      zone: observation.zone,
      source: observation.source,
      observed_at: observation.observed_at,
      freshness:
        if(DateTime.diff(now, observation.observed_at, :second) <= 120,
          do: "fresh",
          else: "stale"
        )
    }
  end
end
