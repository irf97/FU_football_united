defmodule Fu.EquipmentConcurrencyTest do
  use ExUnit.Case, async: false
  import Fu.Fixtures
  import Ecto.Query
  alias Fu.{Equipment, Hobbies, Repo}

  @moduletag :postgres_concurrency
  defp unboxed(fun), do: Ecto.Adapters.SQL.Sandbox.unboxed_run(Repo, fun)

  test "independent database connections cannot reserve one asset for overlapping events" do
    {owner, asset, sessions} =
      unboxed(fn ->
        owner = player_fixture()
        {:ok, asset} = Equipment.create_asset(owner, %{name: "Shared ball"})
        at = DateTime.utc_now() |> DateTime.add(3600) |> DateTime.truncate(:second)

        sessions =
          for n <- 1..8 do
            {:ok, session} =
              Hobbies.create_session(owner, %{
                title: "Concurrent #{n}",
                hobby: "futsal",
                place: "Test court",
                starts_at: at,
                ends_at: DateTime.add(at, 3600),
                capacity: 4,
                min_participants: 1
              })

            session
          end

        {owner, asset, sessions}
      end)

    on_exit(fn ->
      unboxed(fn ->
        Repo.delete_all(from s in Fu.Hobbies.Session, where: s.id in ^Enum.map(sessions, & &1.id))
        Repo.delete_all(from a in Fu.Equipment.Asset, where: a.id == ^asset.id)
        Repo.delete!(owner)
      end)
    end)

    results =
      sessions
      |> Task.async_stream(
        fn session ->
          unboxed(fn -> Equipment.reserve(asset.id, session.id, owner) end)
        end,
        max_concurrency: 8,
        timeout: 30_000
      )
      |> Enum.map(fn {:ok, result} -> result end)

    assert Enum.count(results, &match?({:ok, _}, &1)) == 1
    assert Enum.count(results, &(&1 == {:error, :conflict})) == 7

    unboxed(fn ->
      assert Repo.aggregate(
               from(r in Fu.Equipment.Reservation,
                 where: r.asset_id == ^asset.id and r.status == "reserved"
               ),
               :count
             ) == 1
    end)
  end
end
