defmodule Fu.SimulationTest do
  use Fu.DataCase, async: false
  alias Fu.{Repo, Hobbies, Equipment}

  setup do
    original = Application.fetch_env(:fu, :environment)

    on_exit(fn ->
      case original do
        {:ok, value} -> Application.put_env(:fu, :environment, value)
        :error -> Application.delete_env(:fu, :environment)
      end
    end)
  end

  test "the fictional setting is additive, idempotent and uses real application contexts" do
    Application.put_env(:fu, :environment, :rehearsal)
    unrelated = player_fixture()
    first = apply(Fu.Simulation, :seed!, [])
    second = apply(Fu.Simulation, :seed!, [])
    assert first == second
    assert length(first.players) == 12
    assert length(first.sessions) == 6
    assert Repo.get(Fu.Accounts.Player, unrelated.id)
    host = Repo.get!(Fu.Accounts.Player, hd(first.players))
    assert Enum.all?(Hobbies.list_sessions(), &(not String.contains?(&1.place, "Twente")))
    assert Enum.any?(Hobbies.list_sessions(), &(&1.hobby == "guitar"))
    assert Enum.any?(Hobbies.list_sessions(), &(&1.hobby == "futsal"))
    assert length(Equipment.list_assets(host)) == 6
    assert Enum.all?(Equipment.list_assets(host), &(&1.location.source == "receiver_report"))
    snapshot = Fu.Assistant.snapshot(hd(first.sessions), host)
    assert snapshot.board.team_a == "Commons"
    assert snapshot.board.unit == "goals"
    refute host.is_admin
  end

  test "production refuses simulation creation before writes" do
    Application.put_env(:fu, :environment, :production)
    before = Repo.aggregate(Fu.Accounts.Player, :count)
    assert_raise RuntimeError, ~r/isolated simulation/, fn -> apply(Fu.Simulation, :seed!, []) end
    assert Repo.aggregate(Fu.Accounts.Player, :count) == before
  end
end
