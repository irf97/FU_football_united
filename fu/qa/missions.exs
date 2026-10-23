defmodule Fu.QA.Missions do
  @moduledoc false
  alias Fu.{Accounts, Hobbies, Repo}
  import Ecto.Query

  def guard! do
    %{rows: [[database]]} = Ecto.Adapters.SQL.query!(Repo, "SELECT current_database()", [])

    unless Application.get_env(:fu, :environment) == :rehearsal and database == "fu_pilot_qa",
      do: raise("missions only support the disposable rehearsal database")
  end

  defp call(fun) do
    {elapsed, result} = :timer.tc(fun)
    Process.put(:latencies, [elapsed / 1_000 | Process.get(:latencies, [])])
    result
  end

  def run(envelope) do
    guard!()
    Process.put(:latencies, [])

    players =
      for n <- 1..envelope["synthetic_participants"] do
        phone = "+3168100" <> String.pad_leading(to_string(n), 4, "0")
        {:ok, code} = call(fn -> Accounts.request_otp(phone) end)
        {:ok, player} = call(fn -> Accounts.verify_otp(phone, code) end)
        {:error, :invalid_code} = Accounts.verify_otp(phone, code)
        player
      end

    ids = Enum.map(players, & &1.id)
    before_players = Repo.all(from p in Accounts.Player, where: p.id in ^ids, order_by: p.id)
    starts_at = DateTime.utc_now() |> DateTime.add(20, :second) |> DateTime.truncate(:second)

    missions =
      for mode <- envelope["modes"], n <- 1..envelope["sessions_per_mode"] do
        host = Enum.at(players, rem(n, length(players)))

        guests =
          for offset <- 1..envelope["session_capacity"],
              do: Enum.at(players, rem(n + offset, length(players)))

        {:ok, session} =
          call(fn ->
            Hobbies.create_session(host, %{
              title: "Rehearsal #{mode} #{n}",
              hobby: mode <> " hobby",
              mode: mode,
              place: "Synthetic room",
              starts_at: starts_at,
              ends_at: DateTime.add(starts_at, 3600, :second),
              capacity: envelope["session_capacity"],
              min_participants: 2
            })
          end)

        for guest <- guests do
          {:ok, _} = call(fn -> Hobbies.join(session.id, guest) end)
          if mode == "committed", do: {:ok, _} = call(fn -> Hobbies.commit(session.id, guest) end)
        end

        guest = hd(guests)

        if mode == "committed" do
          {:error, :reason_required} = call(fn -> Hobbies.leave(session.id, guest) end)
        end

        {:ok, _} = call(fn -> Hobbies.leave(session.id, guest, "Synthetic schedule conflict") end)
        {:ok, member} = call(fn -> Hobbies.join(session.id, guest) end)
        true = is_nil(member.committed_at)
        if mode == "committed", do: {:ok, _} = call(fn -> Hobbies.commit(session.id, guest) end)
        event_count = length(Hobbies.history(session.id))

        {:error, :forbidden} =
          call(fn -> Hobbies.confirm_access(session.id, guest, "unauthorized") end)

        {:error, :forbidden} = call(fn -> Hobbies.start(session.id, guest) end)
        ^event_count = length(Hobbies.history(session.id))

        {:ok, _} =
          call(fn -> Hobbies.confirm_access(session.id, host, "Synthetic host declaration") end)

        {session.id, host, guests, rem(n, 4) == 0}
      end

    # Real wall-clock waiting; no time provider, timestamps or DB records are rewritten.
    wait = max(0, DateTime.diff(starts_at, DateTime.utc_now(), :millisecond) + 10)
    Process.sleep(wait)

    for {id, host, guests, cancel?} <- missions do
      if cancel? do
        {:ok, _} = call(fn -> Hobbies.cancel(id, host, "Synthetic room closure") end)
        "cancelled" = Hobbies.get_session(id).status
        true = Enum.all?(Hobbies.get_session(id).participants, &(&1.status == "cancelled"))
      else
        {:ok, _} = call(fn -> Hobbies.start(id, host) end)

        for guest <- Enum.take(guests, 2) do
          {:ok, _} = call(fn -> Hobbies.attend(id, guest) end)
        end

        {:ok, _} = call(fn -> Hobbies.finish(id, host) end)
        "completed" = Hobbies.get_session(id).status

        true =
          Enum.all?(
            Enum.filter(Hobbies.history(id), &(&1.action == "attended")),
            &(&1.payload["source"] == "self_check_in")
          )
      end
    end

    ^before_players = Repo.all(from p in Accounts.Player, where: p.id in ^ids, order_by: p.id)
    host = hd(players)
    race = fixture(host, "Capacity contention", envelope["session_capacity"])

    outcomes =
      concurrent(Enum.take(players, envelope["seat_contenders"]), fn p ->
        Hobbies.join(race.id, p)
      end)

    capacity = envelope["session_capacity"]
    ^capacity = Enum.count(outcomes, &match?({:ok, _}, &1))
    ^capacity = Hobbies.occupied(Hobbies.get_session(race.id))
    true = Enum.all?(outcomes, fn r -> match?({:ok, _}, r) or r == {:error, :full} end)
    duplicate = fixture(host, "Duplicate submission", capacity)

    duplicates =
      concurrent(List.duplicate(List.last(players), envelope["duplicate_join_requests"]), fn p ->
        Hobbies.join(duplicate.id, p)
      end)

    true = Enum.all?(duplicates, &match?({:ok, _}, &1))
    1 = Hobbies.occupied(Hobbies.get_session(duplicate.id))
    1 = Enum.count(Hobbies.history(duplicate.id), &(&1.action == "joined"))
    atomic = fixture(host, "Interrupted transaction", capacity)

    report = %{
      status: "passed",
      participants: length(players),
      sessions: length(missions),
      modes: envelope["modes"],
      completed: Enum.count(missions, fn {_, _, _, c} -> not c end),
      cancelled: Enum.count(missions, fn {_, _, _, c} -> c end),
      capacity_contenders: length(outcomes),
      duplicate_requests: envelope["duplicate_join_requests"],
      unauthorized_mutations: "rejected",
      player_profiles: "unchanged",
      attendance: "self_check_in",
      atomic_session_id: atomic.id,
      atomic_player_id: List.last(players).id,
      context_latencies_ms: Enum.reverse(Process.get(:latencies))
    }

    File.write!("/tmp/fu-missions.json", Jason.encode!(report))
    :ok
  end

  defp concurrent(players, fun) do
    players
    |> Task.async_stream(fn p -> :timer.tc(fn -> fun.(p) end) end,
      max_concurrency: 24,
      timeout: 20_000
    )
    |> Enum.map(fn {:ok, {elapsed, result}} ->
      Process.put(:latencies, [elapsed / 1_000 | Process.get(:latencies)])
      result
    end)
  end

  defp fixture(host, title, capacity) do
    start = DateTime.utc_now() |> DateTime.add(600, :second) |> DateTime.truncate(:second)

    {:ok, session} =
      call(fn ->
        Hobbies.create_session(host, %{
          title: title,
          hobby: "rehearsal",
          mode: "open",
          place: "Synthetic room",
          starts_at: start,
          ends_at: DateTime.add(start, 3600, :second),
          capacity: capacity,
          min_participants: 1
        })
      end)

    session
  end

  def reads(envelope) do
    guard!()
    deadline = System.monotonic_time(:millisecond) + envelope["soak_seconds"] * 1000

    samples =
      1..envelope["readers"]
      |> Task.async_stream(fn _ -> read_until(deadline, envelope["read_pacing_ms"], []) end,
        max_concurrency: envelope["readers"],
        timeout: 120_000
      )
      |> Enum.flat_map(fn {:ok, values} -> values end)

    File.write!("/tmp/fu-reads.json", Jason.encode!(%{status: "passed", latencies_ms: samples}))
    :ok
  end

  defp read_until(deadline, pacing, samples) do
    if System.monotonic_time(:millisecond) >= deadline do
      samples
    else
      {elapsed, sessions} = :timer.tc(fn -> Hobbies.list_sessions(%{include_closed: true}) end)
      true = length(sessions) >= 36
      Process.sleep(pacing)
      read_until(deadline, pacing, [elapsed / 1000 | samples])
    end
  end
end
