defmodule Fu.RuntimeConfig do
  @moduledoc "Runtime boundary selection; rehearsal and live use the same release image."
  @endpoint "https://rest.messagebird.com/messages"

  def load(env) do
    mode = Map.get(env, "FU_MODE", "production")

    environment =
      case mode do
        "production" -> :production
        "rehearsal" -> :rehearsal
        _ -> raise ArgumentError, "FU_MODE must be production or rehearsal"
      end

    if environment == :production && present?(env["FU_SMS_ENDPOINT"]) do
      raise ArgumentError, "production does not accept a simulator endpoint"
    end

    provider = Map.get(env, "FU_SMS_PROVIDER", "disabled")

    sms =
      case {environment, provider} do
        {:production, "disabled"} ->
          [adapter: Fu.SMS.HTTPAdapter]

        {_, "messagebird"} ->
          key = required!(env, "FU_SMS_API_KEY")
          originator = required!(env, "FU_SMS_ORIGINATOR")
          endpoint = endpoint!(environment, key, env)

          [
            adapter: Fu.SMS.HTTPAdapter,
            provider: Fu.SMS.MessageBirdProvider,
            transport: Fu.SMS.ReqTransport,
            config: [api_key: key, originator: originator, endpoint: endpoint]
          ]

        _ ->
          raise ArgumentError, "select a supported FU_SMS_PROVIDER"
      end

    %{environment: environment, sms: sms}
  end

  defp endpoint!(:production, key, _env) do
    if String.starts_with?(key, "fu-sim-"),
      do: raise(ArgumentError, "production refuses simulation credentials")

    @endpoint
  end

  defp endpoint!(:rehearsal, key, env) do
    unless env["PHX_HOST"] in ["localhost", "127.0.0.1"] &&
             String.starts_with?(key, "fu-sim-") do
      raise ArgumentError, "rehearsal requires a loopback host and simulation credentials"
    end

    endpoint = required!(env, "FU_SMS_ENDPOINT")
    uri = URI.parse(endpoint)

    unless uri.scheme == "http" && uri.host in ["sms", "localhost", "127.0.0.1"] &&
             uri.path == "/messages" && is_nil(uri.userinfo) && is_nil(uri.query) &&
             is_nil(uri.fragment) do
      raise ArgumentError, "rehearsal SMS endpoint must be the local provider emulator"
    end

    endpoint
  end

  defp required!(env, key) do
    value = env[key]
    if present?(value), do: value, else: raise(ArgumentError, "#{key} is required")
  end

  defp present?(value), do: is_binary(value) && String.trim(value) != ""
end
