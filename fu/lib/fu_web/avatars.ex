defmodule FuWeb.Avatars do
  @moduledoc """
  Mini-footballer avatars — head + jersey bust, no legs. Composed from a
  legend (skin tone + hair style), a nation/club kit (colours + jersey
  *pattern*) and the jersey number.

  Pure inline SVG: a kit-tinted spotlight, side-shaded torso, patterned
  jersey, collar/sleeve accents, and a hair style that varies per legend.
  No JS, no animation — identical at 28px or 120px.
  """
  use Phoenix.Component

  # legend => {skin, hair, hair_style}
  # styles: :short :mid :buzz :bald :curly :long :mohawk
  @legends %{
    "Pelé" => {"#7a4a26", "#1a1208", :short},
    "Maradona" => {"#c98a5e", "#241a12", :curly},
    "Cruyff" => {"#e8c4a0", "#3a2a18", :mid},
    "Zidane" => {"#d8a878", "#8a8a8a", :bald},
    "Ronaldo R9" => {"#caa078", "#181818", :buzz},
    "Ronaldinho" => {"#6e4326", "#120c06", :long},
    "Messi" => {"#e3bd97", "#2a1c0e", :short},
    "Cristiano Ronaldo" => {"#d8aa80", "#1c140a", :buzz},
    "Beckenbauer" => {"#eccdab", "#5a4326", :mid},
    "George Best" => {"#e6c6a4", "#241408", :mid},
    "Eusébio" => {"#5e3a20", "#0e0a06", :buzz},
    "Roberto Baggio" => {"#dcb389", "#241608", :long},
    "Van Basten" => {"#eccdab", "#caa24e", :short},
    "Maldini" => {"#d3a578", "#1f160c", :short},
    "Thierry Henry" => {"#6b4327", "#0c0804", :buzz},
    "Garrincha" => {"#74482a", "#150f08", :short},
    "Lev Yashin" => {"#e3c2a0", "#1a1a1a", :short},
    "Bobby Charlton" => {"#eccdab", "#caa24e", :bald},
    "Gerd Müller" => {"#e6c6a4", "#3a2a18", :curly},
    "Romário" => {"#9c6a40", "#100c06", :short},
    "Rivaldo" => {"#7a4a26", "#0e0a06", :bald},
    "Kaká" => {"#caa078", "#241608", :mid},
    "Iniesta" => {"#e3bd97", "#241a12", :bald},
    "Xavi" => {"#d8a878", "#1c140a", :buzz},
    "Pirlo" => {"#dcb389", "#241608", :mid},
    "Modrić" => {"#e8c4a0", "#caa24e", :mid},
    "Ibrahimović" => {"#d3a578", "#0e0a06", :long},
    "Drogba" => {"#5a3820", "#0c0804", :buzz},
    "Ruud Gullit" => {"#6e4326", "#1a1208", :long},
    "Cantona" => {"#e6c6a4", "#241408", :short},
    "Totti" => {"#d8aa80", "#1c140a", :short},
    "Roberto Carlos" => {"#6b4327", "#0c0804", :buzz},
    "Cafu" => {"#7a4a26", "#100c06", :short},
    "Carles Puyol" => {"#caa078", "#1a1208", :long},
    "Neymar" => {"#b07a4e", "#241608", :mohawk},
    "Mbappé" => {"#5e3a20", "#0e0a06", :buzz},
    "Haaland" => {"#eccdab", "#caa24e", :mid},
    "De Bruyne" => {"#e8c4a0", "#caa24e", :short},
    "Salah" => {"#9c6a40", "#100c06", :curly}
  }

  # nation/club => {jersey, accent, pattern}
  # patterns: :solid :stripes :sash :checker :hoops
  @kits %{
    "Brazil" => {"#f7d716", "#1e9e54", :solid},
    "Argentina" => {"#79b9e7", "#ffffff", :stripes},
    "Netherlands" => {"#ff6a13", "#1a1a1a", :solid},
    "France" => {"#1f3c88", "#ffffff", :sash},
    "Germany" => {"#f4f4f4", "#1a1a1a", :solid},
    "Italy" => {"#1d6fb8", "#ffffff", :solid},
    "England" => {"#f4f4f4", "#d4112a", :solid},
    "Portugal" => {"#c8102e", "#1e6b3a", :sash},
    "Spain" => {"#c8102e", "#f7d716", :solid},
    "Belgium" => {"#111111", "#f7d716", :solid},
    "Uruguay" => {"#5ba3d0", "#111111", :solid},
    "Croatia" => {"#e0112b", "#ffffff", :checker},
    "Mexico" => {"#0f7a3d", "#ffffff", :solid},
    "USA" => {"#ffffff", "#1f3c88", :sash},
    "Colombia" => {"#fcd116", "#003893", :solid},
    "Nigeria" => {"#1a8a4b", "#ffffff", :stripes},
    "Morocco" => {"#c1272d", "#0a5c36", :solid},
    "Senegal" => {"#1f9e4a", "#e0112b", :solid},
    "Japan" => {"#1d2f6f", "#ffffff", :solid},
    "Sweden" => {"#f7d716", "#1f4fa3", :solid},
    "Hoops Green" => {"#1e9e54", "#ffffff", :hoops},
    "Stripes Red" => {"#d4112a", "#111111", :stripes},
    "Sash Gold" => {"#111111", "#f7d716", :sash},
    "Custom" => {nil, nil, :solid}
  }

  def legends, do: Map.keys(@legends)
  def kits, do: Map.keys(@kits)

  @doc "Skin colour for a legend (picker swatch)."
  def legend_skin(name), do: @legends |> Map.get(name, {"#d8a878", "#222", :short}) |> elem(0)

  @doc "`{jersey, accent}` for a kit (+ custom fallback) — picker swatch."
  def kit_colors(name, custom \\ "#67e8f9"), do: base_colors(name, custom)

  defp head_for(legend), do: Map.get(@legends, legend, {"#d8a878", "#222", :short})

  defp base_colors(kit, custom) do
    case Map.get(@kits, kit) do
      {nil, nil, _} -> {custom || "#67e8f9", shade(custom || "#67e8f9")}
      {j, a, _} -> {j, a}
      _ -> {custom || "#67e8f9", shade(custom || "#67e8f9")}
    end
  end

  defp pattern_for(kit), do: @kits |> Map.get(kit, {nil, nil, :solid}) |> elem(2)

  defp shade("#" <> hex) when byte_size(hex) == 6 do
    [r, g, b] = for <<p::binary-2 <- hex>>, do: String.to_integer(p, 16)

    "#" <>
      for c <- [r, g, b], into: "" do
        c |> div(2) |> Integer.to_string(16) |> String.pad_leading(2, "0")
      end
  end

  defp shade(_), do: "#1a1a1a"

  attr :player, :map, required: true
  attr :size, :integer, default: 48
  attr :class, :string, default: nil
  attr :backdrop, :boolean, default: true

  def avatar(assigns) do
    {skin, hair, hair_style} = head_for(assigns.player.avatar_legend)
    {jersey, accent} = base_colors(assigns.player.avatar_kit, assigns.player.avatar_color)

    assigns =
      assign(assigns,
        skin: skin,
        hair: hair,
        hair_style: hair_style,
        jersey: jersey,
        accent: accent,
        pattern: pattern_for(assigns.player.avatar_kit),
        uid: System.unique_integer([:positive]),
        num: assigns.player.jersey_number || ""
      )

    ~H"""
    <svg
      viewBox="0 0 64 72"
      width={@size}
      height={@size}
      class={@class}
      role="img"
      aria-label={"#{@player.avatar_legend} in #{@player.avatar_kit} kit"}
    >
      <defs>
        <radialGradient id={"bg#{@uid}"} cx="50%" cy="38%" r="62%">
          <stop offset="0%" stop-color={@jersey} stop-opacity="0.30" />
          <stop offset="100%" stop-color={@jersey} stop-opacity="0" />
        </radialGradient>
        <linearGradient id={"sh#{@uid}"} x1="0" y1="0" x2="1" y2="0">
          <stop offset="0%" stop-color="#000" stop-opacity="0.18" />
          <stop offset="42%" stop-color="#000" stop-opacity="0" />
          <stop offset="100%" stop-color="#000" stop-opacity="0.22" />
        </linearGradient>
        <clipPath id={"jc#{@uid}"}>
          <path d="M14 72 V44 Q14 35 22 32 L25 30 Q32 36 39 30 L42 32 Q50 35 50 44 V72 Z" />
        </clipPath>
      </defs>

      <circle :if={@backdrop} cx="32" cy="30" r="34" fill={"url(#bg#{@uid})"} />
      <ellipse cx="32" cy="69" rx="20" ry="3.4" fill="#000" opacity="0.22" />

      <path d="M14 72 V44 Q14 35 22 32 L25 30 Q32 36 39 30 L42 32 Q50 35 50 44 V72 Z" fill={@jersey} />

      <g clip-path={"url(#jc#{@uid})"}>
        <%= case @pattern do %>
          <% :stripes -> %>
            <g fill={@accent} opacity="0.92">
              <rect x="20" y="28" width="3.4" height="46" />
              <rect x="29" y="28" width="3.4" height="46" />
              <rect x="38" y="28" width="3.4" height="46" />
            </g>
          <% :sash -> %>
            <path d="M14 38 L50 60 L50 66 L14 44 Z" fill={@accent} opacity="0.9" />
          <% :hoops -> %>
            <g fill={@accent} opacity="0.9">
              <rect x="12" y="38" width="40" height="5" />
              <rect x="12" y="50" width="40" height="5" />
              <rect x="12" y="62" width="40" height="5" />
            </g>
          <% :checker -> %>
            <g fill={@accent} opacity="0.85">
              <rect x="14" y="30" width="6" height="6" /><rect x="26" y="30" width="6" height="6" />
              <rect x="38" y="30" width="6" height="6" /><rect x="20" y="36" width="6" height="6" />
              <rect x="32" y="36" width="6" height="6" /><rect x="44" y="36" width="6" height="6" />
              <rect x="14" y="42" width="6" height="6" /><rect x="26" y="42" width="6" height="6" />
              <rect x="38" y="42" width="6" height="6" />
            </g>
          <% _ -> %>
        <% end %>
      </g>

      <path d="M14 72 V44 Q14 35 22 32 L25 30 Q32 36 39 30 L42 32 Q50 35 50 44 V72 Z" fill={"url(#sh#{@uid})"} />

      <path d="M14 44 Q9 47 11 57 L18 55 V43 Z" fill={@accent} />
      <path d="M50 44 Q55 47 53 57 L46 55 V43 Z" fill={@accent} />
      <path d="M25 30 Q32 37 39 30 L36 29 Q32 33 28 29 Z" fill={@accent} />

      <text
        x="32"
        y="55"
        text-anchor="middle"
        font-family="ui-monospace, monospace"
        font-size="12"
        font-weight="700"
        fill={@accent}
        opacity="0.85"
      >{@num}</text>

      <rect x="28" y="25" width="8" height="9" fill={@skin} />
      <path d="M26 31 Q32 35 38 31 L38 33 Q32 37 26 33 Z" fill="#000" opacity="0.15" />

      <circle cx="32" cy="17" r="13" fill={@skin} />
      <ellipse cx="37" cy="18" rx="6" ry="11" fill="#000" opacity="0.10" />

      <%= case @hair_style do %>
        <% :bald -> %>
          <path d="M20 13 Q22 7 32 6.5 Q42 7 44 13 Q40 10 32 10 Q24 10 20 13 Z" fill={@hair} opacity="0.55" />
        <% :buzz -> %>
          <path d="M20 16 Q21 6 32 5.5 Q43 6 44 16 Q39 12 32 12 Q25 12 20 16 Z" fill={@hair} opacity="0.85" />
        <% :mid -> %>
          <path d="M18 19 Q18 4 32 4 Q46 4 46 19 Q44 12 32 12 Q20 12 18 19 Z" fill={@hair} />
          <path d="M18 19 Q17 25 19 28 L22 27 Q20 22 21 17 Z" fill={@hair} />
          <path d="M46 19 Q47 25 45 28 L42 27 Q44 22 43 17 Z" fill={@hair} />
        <% :mohawk -> %>
          <path d="M29 4 Q32 2 35 4 L35 15 Q32 13 29 15 Z" fill={@hair} />
          <path d="M21 16 Q22 13 26 13 L26 16 Z" fill={@hair} opacity="0.6" />
          <path d="M43 16 Q42 13 38 13 L38 16 Z" fill={@hair} opacity="0.6" />
        <% :curly -> %>
          <g fill={@hair}>
            <circle cx="22" cy="11" r="5" /><circle cx="28" cy="7.5" r="5.4" />
            <circle cx="34" cy="7" r="5.4" /><circle cx="40" cy="10" r="5" />
            <circle cx="44" cy="15" r="4" /><circle cx="19" cy="16" r="4" />
          </g>
        <% :long -> %>
          <path d="M18 30 Q15 16 20 9 L24 12 Q21 22 24 31 Z" fill={@hair} />
          <path d="M46 30 Q49 16 44 9 L40 12 Q43 22 40 31 Z" fill={@hair} />
          <path d="M19 16 Q20 4 32 4 Q44 4 45 16 Q39 10 32 10 Q25 10 19 16 Z" fill={@hair} />
        <% _ -> %>
          <path d="M19 16 Q20 5 32 5 Q44 5 45 16 Q40 11 32 11 Q24 11 19 16 Z" fill={@hair} />
      <% end %>
    </svg>
    """
  end

  @doc """
  Compact swatch picker — a dense flex-wrap of colour chips backed by
  radio inputs (the surrounding `phx-change="preview"` form needs no extra
  handlers). The selected option's name shows as a caption beneath.
  """
  attr :name, :string, required: true
  attr :label, :string, required: true
  attr :options, :list, required: true
  attr :selected, :string, default: nil
  slot :swatch, required: true

  def picker(assigns) do
    ~H"""
    <div class="space-y-2">
      <div class="flex flex-wrap gap-1.5">
        <label :for={opt <- @options} class="cursor-pointer" title={opt}>
          <input
            type="radio"
            name={@name}
            value={opt}
            checked={opt == @selected}
            class="peer sr-only"
          />
          <span class="block size-8 rounded-lg overflow-hidden ring-1 ring-[var(--fu-line)] transition-transform peer-checked:ring-2 peer-checked:ring-[var(--fu-accent)] peer-checked:scale-110">
            {render_slot(@swatch, opt)}
          </span>
        </label>
      </div>
      <div class="text-caption fu-ink-soft">
        {@label}: <span class="text-base-content">{@selected || "—"}</span>
      </div>
    </div>
    """
  end
end
