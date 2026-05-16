defmodule FuWeb.Avatars do
  @moduledoc """
  Mini-footballer avatars — head + jersey body, no legs. Composed from a
  legendary player (sets head: skin + hair), a nation kit OR a custom
  jersey colour, and the player's jersey number. Used in profile, the
  queue chatroom roster, and the home card.
  """
  use Phoenix.Component

  # legend => {skin, hair} — keeps heads visually distinct
  @legends %{
    "Pelé" => {"#7a4a26", "#1a1208"},
    "Maradona" => {"#c98a5e", "#241a12"},
    "Cruyff" => {"#e8c4a0", "#3a2a18"},
    "Zidane" => {"#d8a878", "#dcdcdc"},
    "Ronaldo R9" => {"#caa078", "#181818"},
    "Ronaldinho" => {"#6e4326", "#120c06"},
    "Messi" => {"#e3bd97", "#2a1c0e"},
    "Cristiano Ronaldo" => {"#d8aa80", "#1c140a"},
    "Beckenbauer" => {"#eccdab", "#5a4326"},
    "George Best" => {"#e6c6a4", "#241408"},
    "Eusébio" => {"#5e3a20", "#0e0a06"},
    "Roberto Baggio" => {"#dcb389", "#241608"},
    "Van Basten" => {"#eccdab", "#caa24e"},
    "Maldini" => {"#d3a578", "#1f160c"},
    "Thierry Henry" => {"#6b4327", "#0c0804"}
  }

  # nation => {jersey, sleeves/accent}
  @kits %{
    "Brazil" => {"#f7d716", "#1e9e54"},
    "Argentina" => {"#7cb8e8", "#ffffff"},
    "Netherlands" => {"#ff6a13", "#1a1a1a"},
    "France" => {"#1f3c88", "#ffffff"},
    "Germany" => {"#f4f4f4", "#1a1a1a"},
    "Italy" => {"#1d6fb8", "#ffffff"},
    "England" => {"#f4f4f4", "#d4112a"},
    "Portugal" => {"#c8102e", "#1e6b3a"},
    "Spain" => {"#c8102e", "#f7d716"},
    "Belgium" => {"#c8102e", "#1a1a1a"},
    "Custom" => nil
  }

  def legends, do: Map.keys(@legends)
  def kits, do: Map.keys(@kits)

  defp head_for(legend), do: Map.get(@legends, legend, {"#d8a878", "#222"})

  defp jersey_for(kit, custom) do
    case Map.get(@kits, kit) do
      nil -> {custom || "#67e8f9", shade(custom || "#67e8f9")}
      pair -> pair
    end
  end

  # crude darken for the custom-colour accent/sleeves
  defp shade("#" <> hex) when byte_size(hex) == 6 do
    [r, g, b] = for <<p::binary-2 <- hex>>, do: String.to_integer(p, 16)
    "#" <> (for c <- [r, g, b], into: "", do: c |> div(2) |> Integer.to_string(16) |> String.pad_leading(2, "0"))
  end

  defp shade(_), do: "#1a1a1a"

  attr :player, :map, required: true, doc: "needs avatar_legend, avatar_kit, avatar_color, jersey_number"
  attr :size, :integer, default: 48
  attr :class, :string, default: nil

  def avatar(assigns) do
    {skin, hair} = head_for(assigns.player.avatar_legend)
    {jersey, accent} = jersey_for(assigns.player.avatar_kit, assigns.player.avatar_color)

    assigns =
      assign(assigns,
        skin: skin,
        hair: hair,
        jersey: jersey,
        accent: accent,
        num: assigns.player.jersey_number || ""
      )

    ~H"""
    <svg
      viewBox="0 0 64 72"
      width={@size}
      height={@size}
      class={@class}
      role="img"
      aria-label={"#{@player.avatar_legend} kit #{@player.avatar_kit}"}
    >
      <!-- jersey body (shoulders + torso, no legs) -->
      <path
        d="M14 72 V44 Q14 36 22 33 L25 31 Q32 36 39 31 L42 33 Q50 36 50 44 V72 Z"
        fill={@jersey}
      />
      <!-- sleeves / kit accent -->
      <path d="M14 44 Q10 47 12 56 L18 54 V44 Z" fill={@accent} />
      <path d="M50 44 Q54 47 52 56 L46 54 V44 Z" fill={@accent} />
      <!-- collar -->
      <path d="M25 31 Q32 38 39 31 L36 30 Q32 33 28 30 Z" fill={@accent} />
      <!-- jersey number -->
      <text
        x="32"
        y="56"
        text-anchor="middle"
        font-family="ui-monospace, monospace"
        font-size="13"
        font-weight="700"
        fill={@accent}
      >{@num}</text>
      <!-- neck -->
      <rect x="28" y="26" width="8" height="8" fill={@skin} />
      <!-- head -->
      <circle cx="32" cy="18" r="13" fill={@skin} />
      <!-- hair cap -->
      <path d="M19 17 Q20 5 32 5 Q44 5 45 17 Q40 11 32 11 Q24 11 19 17 Z" fill={@hair} />
    </svg>
    """
  end
end
