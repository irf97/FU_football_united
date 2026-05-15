defmodule Fu.Fields do
  @moduledoc "Field operators and pitches (spec §2.3)."

  import Ecto.Query
  alias Fu.Repo
  alias Fu.Fields.Field

  def list_fields(region \\ nil) do
    Field
    |> then(fn q -> if region, do: where(q, [f], f.region == ^region), else: q end)
    |> order_by([f], asc: f.name)
    |> Repo.all()
  end

  def get_field!(id), do: Repo.get!(Field, id)

  def create_field(attrs) do
    %Field{} |> Field.changeset(attrs) |> Repo.insert()
  end
end
