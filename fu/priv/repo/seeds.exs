# Seed: Enschede launch region (spec §6 — "1 field, 16 players in Enschede").
# Run with: mix run priv/repo/seeds.exs   (clears core tables first)

import Ecto.Query
alias Fu.Repo
alias Fu.{Fields, Queues, Accounts}
alias Fu.Accounts.Player

Repo.delete_all(Fu.Queues.QueueMembership)
Repo.delete_all(Fu.Queues.QueueSlot)
Repo.delete_all(Fu.Queues.Queue)
Repo.delete_all(Fu.Fields.Field)

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

IO.puts("Seeded: 3 fields, 16 players, #{length(queue_specs)} queues.")
IO.puts("Login with any phone like +31610000001 (OTP printed to server log).")
