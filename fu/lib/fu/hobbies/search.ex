defmodule Fu.Hobbies.Search do
  @moduledoc """
  Explainable lexical retrieval over public activity metadata.

  English/Dutch activity aliases bridge vocabulary differences. Every remaining
  term must match; explicit discovery filters still constrain the SQL query.
  This is a deterministic search aid, not a parser for dates, distance,
  exclusions, equipment availability or authorization.
  """
  import Ecto.Query

  @aliases [
    ["table tennis", "table-tennis", "ping pong", "ping-pong", "tafeltennis"],
    ["guitar", "gitaar"],
    ["basketball", "basketbal"],
    ["football", "soccer", "voetbal"],
    ["futsal", "zaalvoetbal"],
    ["drums", "drummen"],
    ["walking", "wandelen"],
    ["running", "hardlopen"],
    ["cycling", "fietsen"],
    ["chess", "schaken"],
    ["bouldering", "boulderen"],
    ["woodworking", "houtbewerking"]
  ]
  @stopwords ~w(i want would like to a an the at in on for play try please and ik wil graag een de het bij op te spelen proberen en)
  @fields [{:hobby, "hobby"}, {:title, "activity title"}, {:place, "place"}]
  @phrases (for variants <- @aliases, phrase <- variants do
              {String.split(phrase, ~r/[^\p{L}\p{N}]+/u, trim: true),
               %{label: hd(variants), variants: variants}}
            end)
           |> Enum.sort_by(fn {words, _} -> -length(words) end)

  def terms(text) when is_binary(text) do
    text = text |> String.trim() |> String.slice(0, 120) |> String.downcase()
    words = String.split(text, ~r/[^\p{L}\p{N}]+/u, trim: true)
    terms = words |> collect([]) |> Enum.uniq_by(& &1.label)

    if terms == [] and text != "", do: [%{label: text, variants: [text]}], else: terms
  end

  def terms(_), do: []

  def labels(text), do: Enum.map(terms(text), & &1.label)

  def apply(query, text) do
    terms = terms(text)

    {query, rank} =
      Enum.reduce(terms, {query, dynamic([], 0)}, fn term, {query, rank} ->
        hobby = matches(:hobby, term.variants)
        title = matches(:title, term.variants)
        place = matches(:place, term.variants)
        match = dynamic([s], ^hobby or ^title or ^place)

        rank =
          dynamic(
            [s],
            ^rank + fragment("CASE WHEN ? THEN 5 WHEN ? THEN 3 ELSE 1 END", ^hobby, ^title)
          )

        {where(query, ^match), rank}
      end)

    if terms == [], do: query, else: prepend_order_by(query, ^[desc: rank])
  end

  def reasons(session, text) do
    Enum.flat_map(terms(text), fn term ->
      Enum.find_value(@fields, [], fn {field, label} ->
        value = session |> Map.fetch!(field) |> String.downcase()

        if Enum.any?(term.variants, &String.contains?(value, &1)),
          do: [term.label <> " · " <> label]
      end)
    end)
  end

  defp matches(field, variants) do
    Enum.reduce(variants, dynamic([], false), fn term, found ->
      dynamic([s], ^found or fragment("strpos(lower(?), ?) > 0", field(s, ^field), ^term))
    end)
  end

  defp collect([], terms), do: Enum.reverse(terms)

  defp collect(words, terms) do
    case Enum.find(@phrases, fn {phrase, _} -> Enum.take(words, length(phrase)) == phrase end) do
      {phrase, term} ->
        collect(Enum.drop(words, length(phrase)), [term | terms])

      nil ->
        [word | rest] = words

        if word in @stopwords,
          do: collect(rest, terms),
          else: collect(rest, [%{label: word, variants: [word]} | terms])
    end
  end
end
