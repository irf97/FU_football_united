defmodule Fu.SMS.ReqTransportTest do
  use ExUnit.Case, async: false
  alias Fu.SMS.ReqTransport

  defmodule Provider do
    import Plug.Conn
    def init(opts), do: opts

    def call(%{request_path: "/slow"} = conn, _) do
      Process.sleep(2_500)
      send_resp(conn, 503, "late response")
    end

    def call(conn, _), do: send_resp(conn, 201, "accepted")
  end

  test "a timed-out HTTP connection cannot contaminate the next provider request" do
    server = start_supervised!({Bandit, plug: Provider, port: 0, ip: {127, 0, 0, 1}})
    {:ok, {_, port}} = ThousandIsland.listener_info(server)

    request = fn path ->
      %{method: :post, url: "http://127.0.0.1:#{port}/#{path}", headers: [], body: "synthetic"}
    end

    assert ReqTransport.request(request.("slow")) == {:error, :unavailable}
    assert ReqTransport.request(request.("accepted")) == {:ok, %{status: 201, body: "accepted"}}
  end
end
