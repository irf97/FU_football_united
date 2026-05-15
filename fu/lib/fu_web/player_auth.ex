defmodule FuWeb.PlayerAuth do
  @moduledoc "Session-based auth for phone-OTP players (spec §2.13 Surface 1)."

  import Plug.Conn
  import Phoenix.Controller

  alias Fu.Accounts

  @salt "fu player auth"

  @doc "Mints a short-lived token used to hand a LiveView login off to the session controller."
  def login_token(player_id),
    do: Phoenix.Token.sign(FuWeb.Endpoint, @salt, player_id)

  def verify_token(token),
    do: Phoenix.Token.verify(FuWeb.Endpoint, @salt, token, max_age: 300)

  @doc "Stores the player id in the session (called by SessionController)."
  def log_in(conn, player_id) do
    conn
    |> renew_session()
    |> put_session(:player_id, player_id)
    |> put_session(:live_socket_id, "players_socket:#{player_id}")
  end

  def log_out(conn) do
    conn |> renew_session() |> redirect(to: "/login")
  end

  defp renew_session(conn) do
    conn |> configure_session(renew: true) |> clear_session()
  end

  ## Plug: load current player from session

  def fetch_current_player(conn, _opts) do
    player =
      case get_session(conn, :player_id) do
        nil -> nil
        id -> Accounts.get_player(id)
      end

    assign(conn, :current_player, player)
  end

  def require_authenticated(conn, _opts) do
    if conn.assigns[:current_player] do
      conn
    else
      conn
      |> put_flash(:error, "Sign in to continue.")
      |> redirect(to: "/login")
      |> halt()
    end
  end

  def redirect_if_authenticated(conn, _opts) do
    if conn.assigns[:current_player] do
      conn |> redirect(to: "/") |> halt()
    else
      conn
    end
  end

  ## LiveView on_mount

  def on_mount(:require_authenticated, _params, session, socket) do
    player = session["player_id"] && Accounts.get_player(session["player_id"])

    if player do
      {:cont, Phoenix.Component.assign(socket, :current_player, player)}
    else
      {:halt, Phoenix.LiveView.redirect(socket, to: "/login")}
    end
  end
end
