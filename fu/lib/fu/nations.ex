defmodule Fu.Nations do
  @moduledoc """
  A curated list of footballing nations for the player's identity / flag.
  Stored on `Player.nation` as the plain name; `flag/1` maps it to an emoji.
  """

  # name => flag emoji. Kept aligned with the avatar nation kits where they
  # overlap, plus the common amateur-league nationalities here.
  @nations [
    {"Netherlands", "🇳🇱"},
    {"Belgium", "🇧🇪"},
    {"Germany", "🇩🇪"},
    {"France", "🇫🇷"},
    {"England", "🏴󠁧󠁢󠁥󠁮󠁧󠁿"},
    {"Spain", "🇪🇸"},
    {"Portugal", "🇵🇹"},
    {"Italy", "🇮🇹"},
    {"Brazil", "🇧🇷"},
    {"Argentina", "🇦🇷"},
    {"Morocco", "🇲🇦"},
    {"Turkey", "🇹🇷"},
    {"Poland", "🇵🇱"},
    {"Croatia", "🇭🇷"},
    {"Nigeria", "🇳🇬"},
    {"Ghana", "🇬🇭"},
    {"Japan", "🇯🇵"},
    {"USA", "🇺🇸"},
    {"Mexico", "🇲🇽"},
    {"Other", "🏳️"}
  ]

  @doc "All nation names (selectable order)."
  def names, do: Enum.map(@nations, &elem(&1, 0))

  @doc "Flag emoji for a nation name, or a neutral flag if unknown/blank."
  def flag(name), do: Map.get(Map.new(@nations), name, "🏳️")
end
