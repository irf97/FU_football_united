defmodule Fu.SMS do
  @moduledoc """
  SMS delivery — a pluggable adapter (spec §5: "API stubs").

  The default adapter (`Fu.SMS.LogAdapter`) logs the message instead of
  sending it. A real provider (Twilio / MessageBird) is dropped in via
  config without touching call sites:

      config :fu, Fu.SMS, adapter: MyApp.TwilioAdapter
  """

  @doc "Routes the message to the configured adapter. Returns `:ok`."
  def deliver(phone, body), do: adapter().deliver(phone, body)

  defp adapter do
    :fu
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(:adapter, Fu.SMS.LogAdapter)
  end
end

defmodule Fu.SMS.Adapter do
  @moduledoc "Behaviour every SMS delivery backend implements."
  @callback deliver(phone :: String.t(), body :: String.t()) :: :ok
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
