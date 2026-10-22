defmodule FuWeb.EquipmentObservationController do
  use FuWeb, :controller

  def create(conn, params) do
    token =
      case get_req_header(conn, "authorization") do
        ["Bearer " <> token] -> token
        _ -> nil
      end

    conn = put_resp_header(conn, "cache-control", "no-store")

    case Fu.Equipment.ingest(token, params) do
      {:ok, observation} ->
        json(conn, %{
          id: observation.id,
          source: observation.source,
          zone: observation.zone,
          observed_at: observation.observed_at
        })

      {:error, error} ->
        status =
          case error do
            :unauthorized -> 401
            :not_found -> 404
            :idempotency_conflict -> 409
            :rate_limited -> 429
            _ -> 422
          end

        conn |> put_status(status) |> json(%{error: error})
    end
  end
end
