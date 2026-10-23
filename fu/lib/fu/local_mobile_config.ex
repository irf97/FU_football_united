defmodule Fu.LocalMobileConfig do
  @moduledoc "Validated settings for the separate, development-only local mobile build."

  def load!(env) do
    host = required!(env, "FU_LOCAL_HOST")

    unless private_host?(host),
      do: raise(ArgumentError, "FU_LOCAL_HOST must be a private IPv4 address or loopback host")

    port =
      case Integer.parse(required!(env, "FU_LOCAL_PUBLIC_PORT")) do
        {port, ""} when port >= 1024 and port <= 65535 -> port
        _ -> raise ArgumentError, "FU_LOCAL_PUBLIC_PORT must be between 1024 and 65535"
      end

    database_url = required!(env, "DATABASE_URL")
    database = URI.parse(database_url)

    unless database.scheme in ["postgres", "postgresql", "ecto"] and
             database.host in ["db", "localhost", "127.0.0.1"] and
             database.path == "/spontaan_simulation" and is_nil(database.query) and
             is_nil(database.fragment),
           do:
             raise(
               ArgumentError,
               "local mobile requires the isolated spontaan_simulation database"
             )

    secret = required!(env, "SECRET_KEY_BASE")

    unless byte_size(secret) >= 64,
      do:
        raise(
          ArgumentError,
          "local mobile requires a generated cookie secret of at least 64 bytes"
        )

    %{
      host: host,
      port: port,
      database_url: database_url,
      secret_key_base: secret,
      origins: Enum.uniq(for h <- [host, "localhost", "127.0.0.1"], do: "http://#{h}:#{port}")
    }
  end

  def private_host?(host) when host in ["localhost", "127.0.0.1"], do: true

  def private_host?(host) when is_binary(host) do
    if Regex.match?(~r/\A(?:0|[1-9][0-9]{0,2})(?:\.(?:0|[1-9][0-9]{0,2})){3}\z/, host) do
      case :inet.parse_address(String.to_charlist(host)) do
        {:ok, {10, _, _, _}} -> true
        {:ok, {172, second, _, _}} when second in 16..31 -> true
        {:ok, {192, 168, _, _}} -> true
        _ -> false
      end
    else
      false
    end
  end

  def private_host?(_), do: false

  defp required!(env, key) do
    case env[key] do
      value when is_binary(value) and value != "" -> value
      _ -> raise ArgumentError, "#{key} is required for local mobile"
    end
  end
end
