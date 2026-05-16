defmodule Fu.Events do
  @moduledoc """
  Append-only semantic event log (IrfTek paper §3 EVENT LAYER / §6
  "AI-readable runtime"). The runtime already broadcasts domain events
  over `Phoenix.PubSub`; this persists them so an AI/agent can read the
  runtime's history in the paper's §6.3 JSONL shape without touching Ecto.

  `record/3` is side-effect-only: a logging failure must never break the
  domain action that produced the event.
  """

  import Ecto.Query
  require Logger
  alias Fu.Repo
  alias Fu.Events.SemanticEvent

  @doc """
  Appends a semantic event. `payload` keys are coerced to strings.
  Returns `:ok` always (errors are logged, never raised).
  """
  def record(type, payload \\ %{}, opts \\ []) do
    attrs = %{
      type: type,
      domain: Keyword.get(opts, :domain, "football"),
      payload: stringify(payload),
      ts: DateTime.utc_now()
    }

    case %SemanticEvent{} |> SemanticEvent.changeset(attrs) |> Repo.insert() do
      {:ok, _} -> :ok
      {:error, cs} -> Logger.warning("[events] dropped #{type}: #{inspect(cs.errors)}"); :ok
    end
  rescue
    e -> Logger.warning("[events] dropped #{type}: #{inspect(e)}"); :ok
  end

  @doc "Most recent events, newest first."
  def recent(limit \\ 100) do
    from(e in SemanticEvent, order_by: [desc: e.ts, desc: e.id], limit: ^limit)
    |> Repo.all()
  end

  @doc """
  Renders events as the paper's §6.3 JSONL — one machine-readable line
  per event: `{"t":…,"type":…,"domain":…,<payload>}`. Oldest-first.
  """
  def to_jsonl(events) do
    events
    |> Enum.sort_by(& &1.id)
    |> Enum.map_join("\n", fn e ->
      %{"t" => DateTime.to_iso8601(e.ts), "type" => e.type, "domain" => e.domain}
      |> Map.merge(e.payload)
      |> Jason.encode!()
    end)
  end

  defp stringify(map) do
    Map.new(map, fn {k, v} -> {to_string(k), v} end)
  end
end
