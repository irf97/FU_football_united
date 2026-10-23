defmodule Fu.Experiences do
  @moduledoc "Curated presentation themes; hobbies stay open-ended and authority is unchanged."

  @experiences [
    %{
      key: "spontaan",
      label: "Spontaan",
      headline: "Find your next thing.",
      invitation: "Follow the feeling. Make something happen."
    },
    %{
      key: "football",
      label: "Football United",
      headline: "Find your side.",
      invitation: "The pitch, the people, the next good game."
    },
    %{
      key: "court",
      label: "Courtside",
      headline: "One more game?",
      invitation: "Good rallies. New people. Your kind of pace."
    },
    %{
      key: "music",
      label: "After Hours",
      headline: "Find your rhythm.",
      invitation: "Bring an instrument, a voice, or just yourself."
    },
    %{
      key: "outdoors",
      label: "Open Air",
      headline: "Take the long way.",
      invitation: "A little fresh air. A shared direction."
    },
    %{
      key: "making",
      label: "Maker Space",
      headline: "Make a little room.",
      invitation: "For an idea, a new skill, or something made together."
    }
  ]

  @hobbies %{
    "football" => "football",
    "futsal" => "football",
    "soccer" => "football",
    "table tennis" => "court",
    "tennis" => "court",
    "padel" => "court",
    "basketball" => "court",
    "volleyball" => "court",
    "badminton" => "court",
    "guitar" => "music",
    "drums" => "music",
    "singing" => "music",
    "music" => "music",
    "walking" => "outdoors",
    "hiking" => "outdoors",
    "cycling" => "outdoors",
    "gardening" => "outdoors",
    "making" => "making",
    "woodworking" => "making",
    "electronics" => "making",
    "baking" => "making",
    "cooking" => "making",
    "art" => "making"
  }

  def keys, do: Enum.map(@experiences, & &1.key)
  def options, do: [{"Match my hobby", "auto"} | Enum.map(@experiences, &{&1.label, &1.key})]

  def for_player(nil), do: hd(@experiences)

  def for_player(player) do
    key =
      case Map.get(player, :experience_theme, "auto") do
        "auto" -> Map.get(@hobbies, Map.get(player, :main_hobby) || "", "spontaan")
        key -> key
      end

    Enum.find(@experiences, hd(@experiences), &(&1.key == key))
  end
end
