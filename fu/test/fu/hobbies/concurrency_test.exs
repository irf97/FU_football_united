defmodule Fu.Hobbies.ConcurrencyTest do
  use ExUnit.Case, async: false
  import Ecto.Query
  import Fu.Fixtures
  alias Fu.{Hobbies, Repo}
  alias Fu.Hobbies.{Session, Participant, Event}

  @moduletag :postgres_concurrency

  defp unboxed(fun), do: Ecto.Adapters.SQL.Sandbox.unboxed_run(Repo, fun)

  setup do
    {host, people, session} =
      unboxed(fn ->
        host = player_fixture()
        people = for _ <- 1..12, do: player_fixture()
        at = DateTime.utc_now() |> DateTime.add(3600) |> DateTime.truncate(:second)

        {:ok, session} =
          Hobbies.create_session(host, %{
            title: "Concurrency validation",
            hobby: "futsal",
            mode: "committed",
            place: "Synthetic test venue",
            starts_at: at,
            ends_at: DateTime.add(at, 3600),
            capacity: 3,
            min_participants: 1
          })

        {host, people, session}
      end)

    on_exit(fn ->
      unboxed(fn ->
        Repo.delete_all(from s in Session, where: s.id == ^session.id)
        ids = Enum.map([host | people], & &1.id)
        Repo.delete_all(from p in Fu.Accounts.Player, where: p.id in ^ids)
      end)
    end)

    {:ok, host: host, people: people, session: session}
  end

  test "simultaneous joins cannot oversubscribe the final seats", %{
    people: people,
    session: session
  } do
    results =
      people
      |> Task.async_stream(fn player -> unboxed(fn -> Hobbies.join(session.id, player) end) end,
        max_concurrency: 12,
        timeout: 30_000,
        ordered: false
      )
      |> Enum.map(fn {:ok, result} -> result end)

    assert Enum.count(results, &match?({:ok, _}, &1)) == 3
    assert Enum.count(results, &(&1 == {:error, :full})) == 9

    unboxed(fn ->
      assert Repo.aggregate(
               from(p in Participant, where: p.session_id == ^session.id and p.status == "joined"),
               :count
             ) == 3

      assert Repo.aggregate(
               from(e in Event, where: e.session_id == ^session.id and e.action == "joined"),
               :count
             ) == 3
    end)
  end

  test "simultaneous retries by one participant create one seat and one join event", %{
    people: [player | _],
    session: session
  } do
    results =
      1..12
      |> Task.async_stream(fn _ -> unboxed(fn -> Hobbies.join(session.id, player) end) end,
        max_concurrency: 12,
        timeout: 30_000
      )
      |> Enum.map(fn {:ok, {:ok, member}} -> member.id end)

    assert length(Enum.uniq(results)) == 1

    unboxed(fn ->
      assert Repo.aggregate(from(p in Participant, where: p.session_id == ^session.id), :count) ==
               1

      assert Repo.aggregate(
               from(e in Event, where: e.session_id == ^session.id and e.action == "joined"),
               :count
             ) == 1
    end)
  end
end
