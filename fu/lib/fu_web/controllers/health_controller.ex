defmodule FuWeb.HealthController do
  use FuWeb, :controller

  def show(conn, _params) do
    status = if ready?(), do: :ok, else: :service_unavailable
    body = if status == :ok, do: "ok", else: "unavailable"

    conn
    |> put_resp_header("cache-control", "no-store")
    |> put_status(status)
    |> json(%{status: body})
  end

  defp ready? do
    match?({:ok, _}, Ecto.Adapters.SQL.query(Fu.Repo, "SELECT 1", [], timeout: 1_000))
  rescue
    _ -> false
  catch
    :exit, _ -> false
  end
end
