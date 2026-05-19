defmodule Fu.SMSSeamTest do
  @moduledoc """
  Release-grade SMS boundary: a provider *strategy* + an *injected*
  transport, fail-closed when unconfigured, and resilient (an exploding
  adapter never reaches the OTP caller). No vendor, no HTTP dependency —
  a concrete provider is a small strategy module + a transport impl.
  """
  use ExUnit.Case, async: false
  alias Fu.SMS

  defmodule FakeProvider do
    @behaviour Fu.SMS.Provider
    @impl true
    def build(phone, body, config),
      do: %{to: phone, text: body, key: Keyword.get(config, :api_key)}

    @impl true
    def handle(200, _body), do: :ok
    def handle(status, body), do: {:error, {:provider, status, body}}
  end

  defmodule OkTransport do
    @behaviour Fu.SMS.Transport
    @impl true
    def request(req) do
      send(Application.fetch_env!(:fu, :sms_seam_pid), {:sent, req})
      {:ok, %{status: 200, body: "OK"}}
    end
  end

  defmodule BadStatusTransport do
    @behaviour Fu.SMS.Transport
    @impl true
    def request(_), do: {:ok, %{status: 401, body: "unauthorized"}}
  end

  defmodule DownTransport do
    @behaviour Fu.SMS.Transport
    @impl true
    def request(_), do: {:error, :timeout}
  end

  defmodule BoomAdapter do
    @behaviour Fu.SMS.Adapter
    @impl true
    def deliver(_p, _b), do: raise("provider exploded")
  end

  setup do
    on_exit(fn ->
      Application.delete_env(:fu, Fu.SMS)
      Application.delete_env(:fu, :sms_seam_pid)
    end)

    :ok
  end

  defp configure(transport) do
    Application.put_env(:fu, :sms_seam_pid, self())

    Application.put_env(:fu, Fu.SMS,
      adapter: Fu.SMS.HTTPAdapter,
      provider: FakeProvider,
      transport: transport,
      config: [api_key: "k_test"]
    )
  end

  test "builds via provider, sends via injected transport, maps 2xx → :ok" do
    configure(OkTransport)
    assert SMS.deliver("+31611112222", "code 123456") == :ok
    assert_receive {:sent, %{to: "+31611112222", text: "code 123456", key: "k_test"}}
  end

  test "non-2xx maps through the provider to an error" do
    configure(BadStatusTransport)
    assert {:error, {:provider, 401, "unauthorized"}} = SMS.deliver("+316", "x")
  end

  test "transport failure surfaces as a tagged transport error" do
    configure(DownTransport)
    assert {:error, {:transport, :timeout}} = SMS.deliver("+316", "x")
  end

  test "HTTPAdapter is FAIL-CLOSED when unconfigured (no silent no-op)" do
    Application.put_env(:fu, Fu.SMS, adapter: Fu.SMS.HTTPAdapter)
    assert {:error, :not_configured} = SMS.deliver("+316", "x")
  end

  test "deliver/2 never lets an adapter crash reach the caller" do
    Application.put_env(:fu, Fu.SMS, adapter: BoomAdapter)
    assert {:error, {:exception, RuntimeError}} = SMS.deliver("+316", "x")
  end
end
