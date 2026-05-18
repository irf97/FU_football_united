defmodule Fu.Positions do
  @moduledoc """
  Formation -> position quota engine (spec §2.2, §2.11).

  A formation is a `"GK-DEF-MID-FWD"` string describing one team. Quotas are
  doubled to cover both teams in a match. 8v8 and 7v7 are rated
  (spec §2.11 + user decision 2026-05-17); see `rated?/1`.
  """

  @positions ~w(GK DEF MID FWD)

  @default_formations %{
    "5v5" => "1-2-1-1",
    "6v6" => "1-2-2-1",
    "7v7" => "1-2-3-1",
    "8v8" => "1-3-3-1",
    "9v9" => "1-3-3-2",
    "11v11" => "1-4-4-2"
  }

  # Per-position sub-positions — DISPLAY/PREFERENCE METADATA ONLY.
  # Stored as the standard football abbreviation; intentionally NOT
  # referenced by quotas/fill/balance/matching (see PositionDetailTest).
  @subs %{
    "GK" => [{"GK", "Goalkeeper"}],
    "DEF" => [
      {"LB", "Left Back"},
      {"CB", "Centre Back"},
      {"RB", "Right Back"},
      {"LWB", "Left Wing-Back"},
      {"RWB", "Right Wing-Back"},
      {"SW", "Sweeper"}
    ],
    "MID" => [
      {"CDM", "Defensive Mid"},
      {"CM", "Central Mid"},
      {"CAM", "Attacking Mid"},
      {"LM", "Left Mid"},
      {"RM", "Right Mid"}
    ],
    "FWD" => [
      {"LW", "Left Wing"},
      {"RW", "Right Wing"},
      {"SS", "Second Striker"},
      {"CF", "Centre Forward"},
      {"ST", "Striker"}
    ]
  }

  @group_labels %{
    "GK" => "Goalkeeper",
    "DEF" => "Defenders",
    "MID" => "Midfielders",
    "FWD" => "Forwards"
  }

  @doc "All valid positions (the matchmaking vocabulary)."
  def positions, do: @positions

  @doc "Full sub-position map: main position => `[{abbr, name}]`."
  def subs, do: @subs

  @doc "Sub-positions `[{abbr, name}]` valid for a main position (non-matchmaking)."
  def subs_for(position), do: Map.get(@subs, position, [])

  @doc "Just the sub-position abbreviations valid for a main position."
  def sub_abbrs(position), do: subs_for(position) |> Enum.map(&elem(&1, 0))

  @doc "Every sub-position abbreviation (for changeset validation)."
  def all_subs do
    @subs |> Map.values() |> List.flatten() |> Enum.map(&elem(&1, 0)) |> Enum.uniq()
  end

  @doc "Optgroup label for a main position."
  def group_label(position), do: Map.get(@group_labels, position, position)

  @sub_to_main (for {main, subs} <- @subs, {abbr, _name} <- subs, into: %{}, do: {abbr, main})

  @doc """
  The main matchmaking position (GK/DEF/MID/FWD) a sub-position belongs to,
  or `nil`. This is how the engine still only ever sees the main 4 — it's
  derived from the player's sub choice, never typed in.
  """
  def main_of(sub) when sub in [nil, ""], do: nil
  def main_of(sub), do: Map.get(@sub_to_main, sub)

  @doc "All supported match formats."
  def formats, do: Map.keys(@default_formations)

  @doc "Default formation string for a format."
  def default_formation(format), do: Map.get(@default_formations, format, "1-3-3-1")

  @rated_formats ~w(8v8 7v7)

  @doc """
  Rated formats contribute to the official rating: 8v8 (spec §2.11) and 7v7
  (user decision 2026-05-17 — both are competitive enough to rate).
  """
  def rated?(format), do: format in @rated_formats

  @doc """
  Per-position capacity across BOTH teams for a formation, e.g.
  `quotas("1-3-3-1") => %{"GK" => 2, "DEF" => 6, "MID" => 6, "FWD" => 2}`.
  """
  def quotas(formation) do
    [gk, def_, mid, fwd] = parse(formation)

    %{"GK" => gk * 2, "DEF" => def_ * 2, "MID" => mid * 2, "FWD" => fwd * 2}
  end

  @doc "Total players a formation requires across both teams."
  def total(formation), do: formation |> quotas() |> Map.values() |> Enum.sum()

  @doc "Players per team for a position (used by auto-balance)."
  def per_team(formation) do
    [gk, def_, mid, fwd] = parse(formation)
    %{"GK" => gk, "DEF" => def_, "MID" => mid, "FWD" => fwd}
  end

  defp parse(formation) do
    formation
    |> String.split("-", trim: true)
    |> Enum.map(&String.to_integer/1)
    |> case do
      [_g, _d, _m, _f] = parts -> parts
      _ -> [1, 3, 3, 1]
    end
  end
end
