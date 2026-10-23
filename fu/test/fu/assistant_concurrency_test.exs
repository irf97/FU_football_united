defmodule Fu.AssistantConcurrencyTest do
  use ExUnit.Case, async: false
  import Fu.Fixtures
  import Ecto.Query
  alias Fu.{Assistant, Hobbies, Repo}

  @moduletag :postgres_concurrency
  defp unboxed(fun), do: Ecto.Adapters.SQL.Sandbox.unboxed_run(Repo, fun)

  test "one score change wins a revision race and repeated delivery records it once" do
    {host, session, board} =
      unboxed(fn ->
        host = player_fixture()
        at = DateTime.utc_now() |> DateTime.add(3600) |> DateTime.truncate(:second)

        {:ok, session} =
          Hobbies.create_session(host, %{
            title: "Concurrent score",
            hobby: "game",
            place: "Test room",
            starts_at: at,
            ends_at: DateTime.add(at, 3600),
            capacity: 4,
            min_participants: 1
          })

        {:ok, _} = Hobbies.join(session.id, host)
        {:ok, _} = Hobbies.confirm_access(session.id, host, "Test permission")
        Repo.update!(Ecto.Changeset.change(session, starts_at: DateTime.add(at, -3610)))
        {:ok, _} = Hobbies.start(session.id, host)

        {:ok, board} =
          Assistant.configure(session.id, host, %{team_a: "A", team_b: "B", duration_seconds: 600})

        {:ok, board} =
          Assistant.command(session.id, host, "start", %{
            "revision" => board.revision,
            "request_id" => "start"
          })

        {host, session, board}
      end)

    on_exit(fn ->
      unboxed(fn ->
        Repo.delete_all(from s in Fu.Hobbies.Session, where: s.id == ^session.id)
        Repo.delete!(host)
      end)
    end)

    results =
      1..8
      |> Task.async_stream(
        fn n ->
          attrs = %{
            "revision" => board.revision,
            "request_id" => "point-#{n}",
            "side" => "a",
            "delta" => 1
          }

          {attrs, unboxed(fn -> Assistant.command(session.id, host, "score", attrs) end)}
        end,
        max_concurrency: 8,
        timeout: 30_000
      )
      |> Enum.map(fn {:ok, result} -> result end)

    assert Enum.count(results, fn {_, result} -> match?({:ok, _}, result) end) == 1
    assert Enum.count(results, fn {_, result} -> result == {:error, :stale_revision} end) == 7
    {winning, _} = Enum.find(results, fn {_, result} -> match?({:ok, _}, result) end)

    1..8
    |> Task.async_stream(
      fn _ -> unboxed(fn -> Assistant.command(session.id, host, "score", winning) end) end,
      max_concurrency: 8,
      timeout: 30_000
    )
    |> Enum.each(fn {:ok, {:ok, value}} -> assert value.score_a == 1 end)

    unboxed(fn ->
      assert Repo.aggregate(
               from(e in Fu.Assistant.Event,
                 where: e.session_id == ^session.id and e.action == "score"
               ),
               :count
             ) == 1
    end)
  end
end
