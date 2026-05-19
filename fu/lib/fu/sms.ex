defmodule Fu.SMS do
  @moduledoc """
  SMS delivery — a pluggable, release-grade boundary.

  The default adapter (`Fu.SMS.LogAdapter`) logs instead of sending. A
  real provider is dropped in via config **without touching call sites**
  and **without this app taking an HTTP dependency**:

      config :fu, Fu.SMS,
        adapter:   Fu.SMS.HTTPAdapter,
        provider:  MyApp.SMS.AcmeProvider,    # implements Fu.SMS.Provider
        transport: MyApp.SMS.FinchTransport,  # implements Fu.SMS.Transport
        config:    [api_key: System.get_env("SMS_API_KEY")]

  Architecture (ports & adapters): the **vendor** is a small, IO-free
  `Fu.SMS.Provider` strategy; the **HTTP client** is a `Fu.SMS.Transport`
  chosen at release; `Fu.SMS.HTTPAdapter` is the generic engine that
  composes them. No vendor or HTTP client is shipped here on purpose —
  adding one is a localized, well-typed change with zero call-site or
  test churn.

  `deliver/2` is resilient: an adapter that raises is converted to
  `{:error, _}` and never reaches the OTP caller.
  """
  require Logger

  @doc "Routes to the configured adapter. Never raises into the caller."
  @spec deliver(String.t(), String.t()) :: :ok | {:error, term()}
  def deliver(phone, body) do
    adapter().deliver(phone, body)
  rescue
    e ->
      Logger.warning("SMS adapter #{inspect(adapter())} crashed: #{Exception.message(e)}")
      {:error, {:exception, e.__struct__}}
  end

  defp adapter do
    :fu
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(:adapter, Fu.SMS.LogAdapter)
  end
end

defmodule Fu.SMS.Adapter do
  @moduledoc "Behaviour every SMS delivery backend implements."
  @callback deliver(phone :: String.t(), body :: String.t()) :: :ok | {:error, term()}
end

defmodule Fu.SMS.Provider do
  @moduledoc """
  Vendor strategy — a pure, IO-free mapping. `build/3` turns a message +
  credentials into a transport request; `handle/2` interprets the
  response. Being IO-free, a concrete provider is ~20 lines and trivially
  unit-testable without network.
  """
  @callback build(phone :: String.t(), body :: String.t(), config :: keyword()) :: map()
  @callback handle(status :: non_neg_integer(), body :: binary()) :: :ok | {:error, term()}
end

defmodule Fu.SMS.Transport do
  @moduledoc """
  The injected HTTP seam. Implemented by whatever HTTP client is chosen
  at release (Finch / Req / …). Kept abstract so this app carries no HTTP
  dependency and providers stay unit-testable against a stub.
  """
  @callback request(req :: map()) ::
              {:ok, %{status: non_neg_integer(), body: binary()}} | {:error, term()}
end

defmodule Fu.SMS.HTTPAdapter do
  @moduledoc """
  Generic engine: `provider.build → transport.request → provider.handle`.
  **Fail-closed:** unconfigured ⇒ `{:error, :not_configured}` (never a
  silent no-op like the log stub — a release build must not quietly drop
  OTPs).
  """
  @behaviour Fu.SMS.Adapter

  @impl true
  def deliver(phone, body) do
    cfg = Application.get_env(:fu, Fu.SMS, [])
    provider = Keyword.get(cfg, :provider)
    transport = Keyword.get(cfg, :transport)

    cond do
      is_nil(provider) or is_nil(transport) ->
        {:error, :not_configured}

      true ->
        req = provider.build(phone, body, Keyword.get(cfg, :config, []))

        case transport.request(req) do
          {:ok, %{status: status, body: resp}} -> provider.handle(status, resp)
          {:error, reason} -> {:error, {:transport, reason}}
        end
    end
  end
end

defmodule Fu.SMS.LogAdapter do
  @moduledoc "Default adapter (v1): logs instead of texting."
  @behaviour Fu.SMS.Adapter
  require Logger

  @impl true
  def deliver(phone, body) do
    Logger.info("[SMS→#{phone}] #{body}")
    :ok
  end
end
