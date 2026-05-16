# Football United

Amateur-football matchmaking MVP — a player opens the app, queues for a match
they didn't know existed, and plays it the same week. Built to the
`fumvpspec` (v1.2).

**Stack:** Elixir 1.19 / Phoenix 1.8 (LiveView) / PostgreSQL 17 — the exact
substrate the spec names.

## Run it

```sh
# toolchain dirs are sourced per-shell (PATH persistence is sandbox-blocked)
cd "fu" && source ../devenv.sh

mix deps.get
mix ecto.create && mix ecto.migrate
mix run priv/repo/seeds.exs      # 3 Enschede fields, 16 players, queues,
                                 # a confirmed lobby + a finalized match
mix phx.server                   # http://localhost:4000
```

Sign in with any seeded phone, e.g. **`+31610000001`**. There is no SMS
gateway in v1 — the OTP code is printed to the server log and shown on the
login screen (`Fu.SMS` stub, per spec §5).

## The loop (spec §1)

`Browse → Queue → Lobby → Match → Post-match → Profile`, six surfaces:

| Route | Surface | Spec |
|---|---|---|
| `/login` | Phone-OTP sign-in | §2.13 S1 |
| `/` | Home — player card, auto-match suggestions, friends/group | §2.13 S2 |
| `/browse` | Multi-field position-aware queue browser, join/leave | §2.1, §2.4 |
| `/lobby/:id` | Rosters, captain claim, chat, position swap | §2.5, §2.7 |
| `/postmatch/:id` | Voting (4 cats, skip) + rank delta derivation | §2.8, §2.9 |
| `/profile` | Identity, position prefs, availability | §2.6 |

## Architecture

Phoenix contexts, one per bounded concern:

- `Fu.Accounts` — players, phone-OTP, position prefs, availability
- `Fu.Fields` / `Fu.Queues` — fields, queues, position-quota fill,
  join/leave, lock period, partial-fill `Resolver`
- `Fu.Positions` — formation→quota engine (multi-format table, §2.11)
- `Fu.Matching` — auto-match top-3 from availability + position
- `Fu.Friends` / `Fu.Groups` — symmetric friends, split-tolerant group queue
- `Fu.Booking` — adaptive field renting (speculative→provisional→confirmed)
- `Fu.Balance` — deterministic snake-draft team assignment (§2.7)
- `Fu.Matches` / `Fu.Voting` — outcome capture, peer voting + tally
- `Fu.Ranking` — the §2.9 rank engine (append-only ledger), decay,
  no-show/suspension, disputes

Background workers (supervision tree): `Fu.Queues.Resolver` (T-3h
partial-fill), `Fu.Ranking.DecayWorker` (idle-rank decay).

## Build provenance

`SLICES.md` tracks the 60-slice decomposition (spec §6 build order).
Phases 0–4 complete; Phases 2–4 were built with parallel sub-agents on
file-disjoint slices against fixed API contracts, integrated and
compiled centrally (zero warnings). Smoke scripts under
`fu/priv/repo/phase*_smoke.exs`.

Not in v1 (spec §3): public leaderboards, persistent clubs, tournaments,
vision-model rank inputs, in-app payments, streaming, spectators.
