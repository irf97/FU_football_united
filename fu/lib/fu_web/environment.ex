defmodule FuWeb.Environment do
  @moduledoc false
  import Plug.Conn
  def init(opts), do: opts

  def call(conn, _opts) do
    environment = Application.get_env(:fu, :environment, :production)
    put_resp_header(conn, "x-fu-environment", Atom.to_string(environment))
  end
end
