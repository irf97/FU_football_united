# Seed: Enschede launch region (spec §6 — "1 field, 16 players in Enschede").
# Run with: mix run priv/repo/seeds.exs   (clears core tables first)

import Ecto.Query
alias Fu.Repo
alias Fu.{Fields, Queues, Accounts}
alias Fu.Accounts.Player

# Order matters (FKs). Idempotent: full reset of seedable data.
for schema <- [
      Fu.Groups.GroupMembership,
      Fu.Groups.Group,
      Fu.Friends.Friendship,
      Fu.Queues.QueueMembership,
      Fu.Queues.QueueSlot,
      Fu.Queues.Queue,
      Fu.Accounts.AvailabilityWindow,
      Fu.Accounts.OtpCode,
      Fu.Accounts.Player,
      Fu.Fields.Field
    ] do
  Repo.delete_all(schema)
end

# --- Fields (3 partner pitches, spec §6 day 29) ---
{:ok, f1} =
  Fields.create_field(%{
    name: "Diekman Sportpark",
    operator_name: "SV Enschede",
    address: "Diekmanweg 1, Enschede",
    lat: 52.2089,
    lng: 6.8632,
    region: "Enschede",
    formats: ["5v5", "7v7", "8v8", "11v11"]
  })

{:ok, f2} =
  Fields.create_field(%{
    name: "UT Sports Centre",
    operator_name: "Univ. Twente",
    address: "De Hems 2, Enschede",
    lat: 52.2390,
    lng: 6.8520,
    region: "Enschede",
    formats: ["5v5", "6v6", "8v8"]
  })

{:ok, f3} =
  Fields.create_field(%{
    name: "Wesselerbrink Veld",
    operator_name: "Buurtsport",
    address: "Wesselerbrinklaan, Enschede",
    lat: 52.1865,
    lng: 6.8901,
    region: "Enschede",
    formats: ["5v5", "8v8", "9v9"]
  })

# --- Players (16, for the §6 first real test) ---
positions = ~w(GK DEF MID FWD)
styles = ~w(Aggressive Possession Counter Defensive Box-to-box Playmaker Finisher)
names = ~w(Sven Lars Mees Daan Bram Finn Tijn Cas Jort Roan Luuk Stijn Joep Teun Gijs Niek)

players =
  for i <- 1..16 do
    phone = "+3161000000#{String.pad_leading("#{i}", 2, "0")}"
    {:ok, p} = %Player{} |> Player.registration_changeset(%{phone: phone}) |> Repo.insert()

    {:ok, p} =
      Accounts.update_profile(p, %{
        display_name: Enum.at(names, i - 1),
        primary_position: Enum.at(positions, rem(i, 4)),
        secondary_position: Enum.at(positions, rem(i + 1, 4)),
        playstyle: Enum.random(styles),
        home_lat: 52.2215 + (:rand.uniform() - 0.5) * 0.06,
        home_lng: 6.8937 + (:rand.uniform() - 0.5) * 0.06,
        home_label: "Enschede",
        jersey_number: i
      })

    rank = 42.0 + :rand.uniform() * 30
    Repo.update_all(from(x in Player, where: x.id == ^p.id), set: [rank: rank])
    %{p | rank: rank}
  end

# --- Queues across formats (spec §2.11) ---
now = DateTime.utc_now() |> DateTime.truncate(:second)

queue_specs = [
  {f1, "8v8", "1-3-3-1", 2, 11},
  {f2, "8v8", "1-3-3-1", 26, 5},
  {f1, "5v5", "1-2-1-1", 5, 6},
  {f3, "8v8", "1-3-3-1", 49, 9},
  {f2, "6v6", "1-2-2-1", 30, 3}
]

for {field, fmt, formation, hours, fill_n} <- queue_specs do
  {:ok, q} =
    Queues.create_queue(%{
      field_id: field.id,
      format: fmt,
      formation: formation,
      scheduled_at: DateTime.add(now, hours * 3600, :second),
      region: "Enschede"
    })

  players
  |> Enum.take(fill_n)
  |> Enum.each(fn p ->
    %Fu.Queues.QueueMembership{}
    |> Fu.Queues.QueueMembership.changeset(%{
      queue_id: q.id,
      player_id: p.id,
      declared_position: p.primary_position,
      status: "queued"
    })
    |> Repo.insert()
  end)
end

# --- The §6 "first real test": 1 confirmed full 8v8, 16 players, teams + booking ---
{:ok, full} =
  Queues.create_queue(%{
    field_id: f1.id,
    format: "8v8",
    formation: "1-3-3-1",
    scheduled_at: DateTime.add(now, 6 * 3600, :second),
    region: "Enschede"
  })

# 8v8 1-3-3-1 → quotas GK2 DEF6 MID6 FWD2 = 16. Fill exactly.
slots = List.duplicate("GK", 2) ++ List.duplicate("DEF", 6) ++ List.duplicate("MID", 6) ++ List.duplicate("FWD", 2)

players
|> Enum.zip(slots)
|> Enum.each(fn {p, pos} ->
  %Fu.Queues.QueueMembership{}
  |> Fu.Queues.QueueMembership.changeset(%{
    queue_id: full.id,
    player_id: p.id,
    declared_position: pos,
    status: "queued"
  })
  |> Repo.insert!()
end)

full |> Fu.Queues.Queue.changeset(%{state: "confirmed"}) |> Repo.update!()
{:ok, _} = Fu.Balance.assign_teams(full.id)
{:ok, _} = Fu.Booking.ensure_booking(Fu.Queues.get_queue!(full.id))
Fu.Booking.reconcile(Fu.Queues.get_queue!(full.id))

# --- E2E: a fully-played, finalized 8v8 for the post-match demo (spec §2.8/§2.9) ---
{:ok, played} =
  Queues.create_queue(%{
    field_id: f1.id,
    format: "8v8",
    formation: "1-3-3-1",
    scheduled_at: DateTime.add(now, -2 * 3600, :second),
    region: "Enschede"
  })

players
|> Enum.zip(slots)
|> Enum.each(fn {p, pos} ->
  %Fu.Queues.QueueMembership{}
  |> Fu.Queues.QueueMembership.changeset(%{queue_id: played.id, player_id: p.id, declared_position: pos, status: "queued"})
  |> Repo.insert!()
end)

played |> Fu.Queues.Queue.changeset(%{state: "confirmed"}) |> Repo.update!()
{:ok, _} = Fu.Balance.assign_teams(played.id)
ros = Fu.Balance.rosters(played.id)
team_a = ros["A"]
team_b = ros["B"]

Fu.Matches.get_or_create_result(played.id)
Fu.Matches.record_score(played.id, 3, 2)
# A few goals/assists from team A
[s1, s2 | _] = team_a
Fu.Matches.record_goal(played.id, s1.player_id, s2.player_id)
Fu.Matches.record_goal(played.id, s1.player_id, nil)
Fu.Matches.record_goal(played.id, s2.player_id, s1.player_id)

# Opponents vote: every B player votes A's top scorer MVP; A players vote B's keeper
Enum.each(team_b, fn v ->
  Fu.Voting.cast(played.id, v.player_id, "mvp", s1.player_id, own_team: false)
  Fu.Voting.cast(played.id, v.player_id, "defender", List.last(team_a).player_id, own_team: false)
  gkB = Enum.find(team_b, &(&1.declared_position == "GK"))
  if gkB, do: Fu.Voting.cast(played.id, v.player_id, "keeper", gkB.player_id, own_team: false, score: 7)
end)

Fu.Matches.complete_match(played.id)
{:ok, _events} = Fu.Ranking.finalize_match(played.id)

IO.puts("Seeded: 3 fields, 16 players, #{length(queue_specs) + 2} queues.")
IO.puts("Confirmed full 8v8 lobby at /lobby/#{full.id} (teams balanced, field booked).")
IO.puts("Played+finalized 8v8 post-match at /postmatch/#{played.id} (3-2, ranks updated).")
IO.puts("Login with any phone like +31610000001 (OTP printed to server log).")
