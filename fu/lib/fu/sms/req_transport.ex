defmodule Fu.SMS.ReqTransport do
  @moduledoc "Bounded HTTP transport. POST retries and redirects are disabled to avoid duplicate SMS and credential forwarding."
  @behaviour Fu.SMS.Transport

  @impl true
  def request(req) do
    case Req.request(
           method: req.method,
           url: req.url,
           headers: req.headers,
           body: req.body,
           retry: false,
           redirect: false,
           decode_body: false,
           finch: [
             receive_timeout: 2_000,
             pool_timeout: 1_000,
             conn_opts: [transport_opts: [timeout: 1_000]]
           ]
         ) do
      {:ok, response} -> {:ok, %{status: response.status, body: response.body}}
      {:error, _} -> {:error, :unavailable}
    end
  end
end
