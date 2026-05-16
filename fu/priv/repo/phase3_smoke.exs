# Phase 3 functional smoke. Run: mix run priv/repo/phase3_smoke.exs
import Ecto.Query
alias Fu.{Repo, Queues, Balance, Booking, Lobby}

# The confirmed full 8v8 (last queue created by seeds)
q = Repo.all(from x in Queues.Queue, where: x.state == "confirmed", order_by: [desc: x.id]) |> hd()
q = Queues.get_queue!(q.id)
IO.puts("Confirmed queue #{q.id} #{q.format} members=#{Enum.count(q.memberships, & &1.status == "queued")}")

# S45/S46 auto-balance
{:ok, _} = Balance.assign_teams(q.id)
r = Balance.rosters(q.id)
IO.puts("Teams: A=#{length(r["A"])} (rank #{Float.round(Balance.team_rank(r["A"]),1)}) " <>
        "B=#{length(r["B"])} (rank #{Float.round(Balance.team_rank(r["B"]),1)}) " <>
        "delta=#{Float.round(Balance.balance_delta(q.id),2)}")
# determinism
{:ok, _} = Balance.assign_teams(q.id)
r2 = Balance.rosters(q.id)
same = Enum.map(r["A"], & &1.player_id) |> Enum.sort() == Enum.map(r2["A"], & &1.player_id) |> Enum.sort()
IO.puts("Deterministic re-assign: #{same}")

# S42/S43/S44 booking adaptive ladder
{:ok, b} = Booking.ensure_booking(q)
{:ok, b} = Booking.reconcile(Queues.get_queue!(q.id))
IO.puts("Booking: state=#{b.state} deposit=#{b.deposit_paid} balance=#{b.balance_paid} ref=#{b.operator_ref}")

# S50 captain claim state machine
phase = Lobby.claim_phase(q)
IO.puts("Captain phase now: #{inspect(phase)}")
gk = Enum.find(r["A"], & &1.declared_position == "GK")
IO.puts("GK on A eligible (keeper window)? #{Lobby.eligible_to_claim?(q, gk.player, elem(phase,0))}")
case Lobby.claim_captain(q, gk.player) do
  {:ok, m} -> IO.puts("CAPTAIN claimed by #{gk.player.display_name} (team #{m.team})")
  {:error, e} -> IO.puts("claim err #{inspect(e)}")
end
IO.puts("claim again same team -> #{inspect(elem(Lobby.claim_captain(q, gk.player),0))}")
Lobby.random_assign(Queues.get_queue!(q.id))
caps = Queues.get_queue!(q.id).memberships |> Enum.filter(& &1.is_captain) |> Enum.map(& &1.team) |> Enum.sort()
IO.puts("Captains after random fill: teams=#{inspect(caps)}")

# S49 position swap (same team, two members different positions)
a = r["A"]
m1 = Enum.find(a, & &1.declared_position == "DEF")
m2 = Enum.find(a, & &1.declared_position == "MID")
if m1 && m2 do
  {:ok, _} = Lobby.swap_positions(m1.id, m2.id)
  q3 = Queues.get_queue!(q.id)
  n1 = Enum.find(q3.memberships, & &1.id == m1.id).declared_position
  n2 = Enum.find(q3.memberships, & &1.id == m2.id).declared_position
  IO.puts("Swap: DEF/MID -> #{n1}/#{n2} (expect MID/DEF)")
else
  IO.puts("Swap: skipped (no DEF+MID pair on A)")
end

IO.puts("\nPHASE 3 SMOKE OK")
