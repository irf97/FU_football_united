defmodule FuWeb.PageController do
  use FuWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
