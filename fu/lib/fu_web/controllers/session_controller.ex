defmodule FuWeb.SessionController do
  use FuWeb, :controller

  alias FuWeb.PlayerAuth

  @doc "LiveView login hands off here with a signed token to set the session cookie."
  def create(conn, %{"token" => token}) do
    case PlayerAuth.verify_token(token) do
      {:ok, player_id} ->
        conn
        |> PlayerAuth.log_in(player_id)
        |> put_flash(:info, "Welcome to Football United.")
        |> redirect(to: "/")

      {:error, _} ->
        conn
        |> put_flash(:error, "Login link expired. Try again.")
        |> redirect(to: "/login")
    end
  end

  def delete(conn, _params) do
    conn
    |> put_flash(:info, "Signed out.")
    |> PlayerAuth.log_out()
  end
end
