defmodule Fu.SMS.MessageBirdProvider do
  @moduledoc "Optional MessageBird SMS protocol strategy. An acceptance receipt is not a handset delivery receipt."
  @behaviour Fu.SMS.Provider
  @endpoint "https://rest.messagebird.com/messages"

  @impl true
  def build(phone, body, config) do
    %{
      method: :post,
      url: Keyword.get(config, :endpoint, @endpoint),
      headers: [
        {"authorization", "AccessKey #{Keyword.fetch!(config, :api_key)}"},
        {"content-type", "application/x-www-form-urlencoded"}
      ],
      body:
        URI.encode_query(%{
          originator: Keyword.fetch!(config, :originator),
          recipients: phone,
          body: body
        })
    }
  end

  @impl true
  def handle(status, body) when status in 200..299 do
    case Jason.decode(body) do
      {:ok, %{"id" => id, "recipients" => %{"totalCount" => count}}}
      when is_binary(id) and byte_size(id) > 0 and is_integer(count) and count > 0 ->
        :ok

      _ ->
        {:error, :invalid_response}
    end
  end

  def handle(429, _), do: {:error, :rate_limited}
  def handle(status, _) when status in [401, 403], do: {:error, :unauthorized}
  def handle(_, _), do: {:error, :provider_unavailable}
end
