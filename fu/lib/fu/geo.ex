defmodule Fu.Geo do
  @moduledoc "Great-circle distance for queue distance filtering (spec §2.1)."

  @earth_km 6371.0

  @doc """
  Haversine distance in km between two lat/lng points. Returns `nil` if any
  coordinate is missing.
  """
  def distance_km(lat1, lng1, lat2, lng2)
      when is_number(lat1) and is_number(lng1) and is_number(lat2) and is_number(lng2) do
    dlat = radians(lat2 - lat1)
    dlng = radians(lng2 - lng1)

    a =
      :math.sin(dlat / 2) ** 2 +
        :math.cos(radians(lat1)) * :math.cos(radians(lat2)) * :math.sin(dlng / 2) ** 2

    @earth_km * 2 * :math.atan2(:math.sqrt(a), :math.sqrt(1 - a))
  end

  def distance_km(_, _, _, _), do: nil

  defp radians(deg), do: deg * :math.pi() / 180.0
end
