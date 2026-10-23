defmodule FuWeb.SessionController do
  use FuWeb, :controller

  alias FuWeb.{PlayerAuth, ReturnPath}

  @doc "LiveView login hands off here with a signed token to set the session cookie."
  def create(conn, %{"token" => token} = params) do
    case PlayerAuth.verify_token(token) do
      {:ok, %{player_id: player_id, return_to: to}}
      when is_integer(player_id) and player_id > 0 ->
        establish_session(conn, player_id, to)

      # Accept the previous short-lived token shape during a release transition.
      {:ok, player_id} when is_integer(player_id) and player_id > 0 ->
        to = params["to"] || get_session(conn, :player_return_to)
        establish_session(conn, player_id, to)

      _ ->
        conn
        |> put_flash(:error, "Login link expired. Try again.")
        |> redirect(to: "/login")
    end
  end

  defp establish_session(conn, player_id, to) do
    conn
    |> PlayerAuth.log_in(player_id)
    |> put_flash(:info, "Welcome to FU.")
    |> redirect(to: ReturnPath.safe(to))
  end

  def delete(conn, _params) do
    conn
    |> put_flash(:info, "Signed out.")
    |> PlayerAuth.log_out()
  end
end
