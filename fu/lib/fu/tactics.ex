defmodule Fu.Tactics do
  @moduledoc """
  Per-team match tactics (formation / style / instructions). The captain of
  a team is the only one who may edit it; everyone else previews. Pure
  display/coordination — never touches the matchmaking engine.
  """

  import Ecto.Query
  alias Fu.Repo
  alias Fu.Tactics.Tactics
  alias Fu.Queues.QueueMembership

  @formations ~w(4-3-3 4-4-2 4-2-3-1 3-5-2 3-4-3 5-3-2 4-5-1)
  @styles ~w(Balanced Defensive Possession Counter High-press Direct)

  @doc "Selectable formations."
  def formations, do: @formations

  @doc "Selectable team styles."
  def styles, do: @styles

  @doc """
  The team's tactics, or a sensible unsaved default (`4-3-3` / `Balanced`)
  so the UI always has something to render/preview.
  """
  def get(queue_id, team) do
    Repo.get_by(Tactics, queue_id: queue_id, team: team) ||
      %Tactics{queue_id: queue_id, team: team, formation: "4-3-3", style: "Balanced", notes: ""}
  end

  @doc "How many tactics rows exist for `(queue, team)` (test/introspection)."
  def count(queue_id, team) do
    Repo.aggregate(
      from(t in Tactics, where: t.queue_id == ^queue_id and t.team == ^team),
      :count,
      :id
    )
  end

  @doc """
  Upserts `team`'s tactics — **only if `editor` is that team's captain in
  this queue**. Returns `{:ok, tactics}`, `{:error, :not_captain}`, or
  `{:error, changeset}` on invalid formation/style.
  """
  def set(queue_id, team, attrs, editor) do
    if captain_of?(queue_id, team, editor.id) do
      existing = Repo.get_by(Tactics, queue_id: queue_id, team: team) || %Tactics{}

      existing
      |> Tactics.changeset(Map.merge(attrs, %{"queue_id" => queue_id, "team" => team}))
      |> Repo.insert_or_update()
    else
      {:error, :not_captain}
    end
  end

  defp captain_of?(queue_id, team, player_id) do
    Repo.exists?(
      from m in QueueMembership,
        where:
          m.queue_id == ^queue_id and m.player_id == ^player_id and
            m.team == ^team and m.is_captain == true and m.status == "queued"
    )
  end
end
