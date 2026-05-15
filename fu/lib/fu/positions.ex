defmodule Fu.Positions do
  @moduledoc """
  Formation -> position quota engine (spec §2.2, §2.11).

  A formation is a `"GK-DEF-MID-FWD"` string describing one team. Quotas are
  doubled to cover both teams in a match. Only 8v8 is rated (spec §2.11).
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

  @doc "All valid positions."
  def positions, do: @positions

  @doc "All supported match formats."
  def formats, do: Map.keys(@default_formations)

  @doc "Default formation string for a format."
  def default_formation(format), do: Map.get(@default_formations, format, "1-3-3-1")

  @doc "Only 8v8 contributes to the official rating (spec §2.11)."
  def rated?(format), do: format == "8v8"

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
