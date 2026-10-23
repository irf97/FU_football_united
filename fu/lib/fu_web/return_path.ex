defmodule FuWeb.ReturnPath do
  @moduledoc "Explicit same-app destinations for post-login navigation."

  @default "/explore"
  @pages ~w(/explore /hobbies /hobbies/new /equipment /profile /admin /browse /queue /lab)
  @event ~r"\A/hobbies/[1-9][0-9]{0,18}(?:/assistant)?\z"
  @football ~r"\A/(?:(?:lobby|match|postmatch)/[1-9][0-9]{0,18}|queue/[1-9][0-9]{0,18}/chat)\z"

  def safe(value) when is_binary(value) and byte_size(value) <= 2048 do
    if String.valid?(value) and not Regex.match?(~r/[\x00-\x20\x7f\\]/, value) do
      case URI.parse(value) do
        %URI{scheme: nil, host: nil, userinfo: nil, fragment: nil, path: path}
        when is_binary(path) ->
          if path in @pages or Regex.match?(@event, path) or Regex.match?(@football, path),
            do: value,
            else: @default

        _ ->
          @default
      end
    else
      @default
    end
  rescue
    ArgumentError -> @default
  end

  def safe(_), do: @default
end
