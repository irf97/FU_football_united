defmodule Fu.Hobbies.Discovery do
  @moduledoc "Bounded discovery filters. Hobbies remain free text; categories and event formats are metadata."
  @categories [
    {"Sport & movement", "sport"},
    {"Music", "music"},
    {"Art & creativity", "arts"},
    {"Games", "games"},
    {"Outdoors", "outdoors"},
    {"Making & cooking", "making"},
    {"Learning", "learning"},
    {"Social", "social"},
    {"Something else", "other"}
  ]
  @kinds [
    {"Session", "session"},
    {"Event", "event"},
    {"Class / workshop", "class"},
    {"Meetup", "meetup"}
  ]
  @keys [:q, :hobby, :place, :category, :kind, :mode, :scope, :space, :page]

  def categories, do: @categories
  def kinds, do: @kinds
  def category_codes, do: Enum.map(@categories, &elem(&1, 1))
  def kind_codes, do: Enum.map(@kinds, &elem(&1, 1))
  def category_label(code), do: label(@categories, code)
  def kind_label(code), do: label(@kinds, code)

  def normalize(params) when is_map(params) do
    %{
      q: text(value(params, :q), 120),
      hobby: value(params, :hobby) |> text(60) |> String.downcase(),
      place: text(value(params, :place), 120),
      category: choice(value(params, :category), category_codes(), ""),
      kind: choice(value(params, :kind), kind_codes(), ""),
      mode: choice(value(params, :mode), ["open", "practice", "committed"], ""),
      scope: choice(value(params, :scope), ["all", "mine"], "all"),
      space: value(params, :space) in [true, "true"],
      page: page(value(params, :page))
    }
  end

  def normalize(_), do: normalize(%{})

  def params(filters) do
    filters = normalize(filters)
    Map.new(@keys, fn key -> {Atom.to_string(key), to_string(Map.fetch!(filters, key))} end)
  end

  defp value(params, key), do: Map.get(params, key, Map.get(params, Atom.to_string(key)))
  defp text(value, max) when is_binary(value), do: value |> String.trim() |> String.slice(0, max)
  defp text(_, _), do: ""
  defp choice(value, allowed, fallback), do: if(value in allowed, do: value, else: fallback)
  defp page(value) when is_integer(value), do: min(max(value, 1), 1000)

  defp page(value) when is_binary(value) do
    case Integer.parse(value) do
      {number, ""} -> page(number)
      _ -> 1
    end
  end

  defp page(_), do: 1

  defp label(options, code),
    do: Enum.find_value(options, code, fn {label, key} -> if key == code, do: label end)
end
