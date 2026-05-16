# Football United — Build Slices

Decomposition of the MVP (`fumvpspec`) into ~60 executable slices, grouped by the
spec §6 build order. Stack: **Elixir/Phoenix + Postgres** (per spec).

Legend: `[ ]` todo · `[~]` in progress · `[x]` done · `‖` = parallelizable group
(independent files, safe for concurrent agents). The orchestrator owns shared
files (router, mix.exs, supervision tree, migration ordering).

---

## Phase 0 — Toolchain & Scaffold (blocking)

- [x] S00 Install Erlang/OTP (winget) — OTP 28.5
- [x] S01 Install Elixir (1.19.5 otp-28, precompiled zip)
- [x] S02 Install PostgreSQL 17 (postgres/postgres @127.0.0.1:5432)
- [x] S03 Install Hex + Phoenix archive (phx_new 1.8.7)
- [x] S04 Scaffold `fu` Phoenix app (1.8, LiveView, Postgres)
- [x] S05 `mix ecto.create` + server boot verified (HTTP 200)
- [x] S06 Base dark theme/layout from spec design tokens

## Phase 1 — Days 1–14 · Profile + Queue browser (no auto-match) ✅ VERIFIED

Schemas/migrations (orchestrator-owned, sequential):
- [x] S07 `players` (phone, name, avatar, jersey, home lat/lng, rank=50, playstyle)
- [x] S08 Position prefs on player (primary, secondary, fill_mode)
- [x] S09 `availability_windows` (recurring weekly + one-off)
- [x] S10 `fields` (operator, name, location, formats supported)
- [x] S11 `queues` (field, format, formation, scheduled_at, state, region)
- [x] S12 `queue_slots` (per-position quota from formation)
- [x] S13 `queue_memberships` (player, queue, declared position, status)

Auth ‖ Contexts ‖ UI:
- [x] S14 Phone-OTP request endpoint + SMS stub (`Fu.SMS`)
- [x] S15 Phone-OTP verify + session/token + auth plug (`PlayerAuth`)
- [x] S16 Accounts context: profile get/update
- [x] S17 Position preferences API
- [x] S18 Availability windows CRUD API
- [x] S19 Operator queue-creation API (manual, used by seeds)
- [x] S20 Formation→quota engine (multi-format table §2.11)
- [x] S21 Queue listing API + filters (time/dist/pos/rank/format/rated)
- [x] S22 Haversine distance from player home
- [x] S23 Login screen UI (phone → OTP)
- [x] S24 Home page UI (player card, queue btn, pos quick-edit, friends, recent)
- [x] S25 Queue browser LiveView (list + cards)
- [x] S26 Queue card component (field/time/fill/avg-rank/countdown)
- [x] S27 Filter chips UI
- [x] S28 Profile screen UI (identity, availability, prefs)
- [x] S29 Seed: 3 Enschede fields, 16 players, 5 queues

> Verified: login→session→`/`,`/browse`,`/profile` all HTTP 200 with live
> seeded data (fill pills, distances, lock countdown, rated badges).

## Phase 2 — Days 15–28 · Join/leave + Auto-match ✅ VERIFIED

- [x] S30 Join queue API (atomic, quota-enforced, pref-aware)
- [x] S31 Leave queue API (open period only; locked → error)
- [x] S32 Real-time fill via PubSub (`subscribe_all` + handle_info)
- [x] S33 Queue state machine open→lock(T-3h)→confirmed/cancelled
- [x] S34 Lock-period enforcement (no-leave, joined_in_lock flag)
- [x] S35 Partial-fill `Resolver` GenServer (confirm/30m-ext/cancel)
- [x] S36 `Fu.Matching` auto-match top-3 (availability+pos scored) [agent]
- [x] S37 `Fu.Friends` friendships + symmetric auto-accept [agent]
- [x] S38 Invite link + phone-contact-match stub [agent]
- [x] S39 `Fu.Groups` group + leader + atomic group join [agent]
- [x] S40 Group fit simulation (competing-slot aware) [agent]
- [x] S41 Group UI on Home + join/leave + suggestions

> Verified: `phase2_smoke.exs` exercises join/leave/lock, matching,
> friends (request→auto-accept→list→invite→by-phone), group
> create/add/fit/queue, resolver confirm/cancel — all per §2.4/§2.12.
> Built via 3 parallel agents (Matching ‖ Friends ‖ Groups), zero
> integration warnings.

## Phase 3 — Days 29–42 · Lobby + Field booking ✅ (verifying)

- [x] S42 `Fu.Booking` schema + state machine (spec/prov/conf/released) [agent]
- [x] S43 Booking transitions tied to fill% + kickoff (`reconcile/1`) [agent]
- [x] S44 `OperatorStub` hold/deposit/balance/release (spec §5) [agent]
- [x] S45 `Fu.Balance` snake-draft + position-feasibility swap [agent]
- [x] S46 Team persistence + deterministic re-derive + balance_delta [agent]
- [x] S47 `LobbyLive` rosters/avatars/ranks/numbers/details [agent]
- [x] S48 Lobby chat channels team/match/group (PubSub) [agent]
- [x] S49 Position swap requests (two-step mutual consent) [agent]
- [x] S50 Captain claim seq keeper→rank→free→random + timers [agent]

> Built via 3 parallel agents (Booking ‖ Balance ‖ Lobby). Seeds now
> include a confirmed full 8v8 with balanced teams + booking at
> `/lobby/:id`. Verification: phase3_smoke.exs (pending seed run).

## Phase 4 — Days 43–60 · Voting + Rank + test ✅ VERIFIED

- [x] S51 `Fu.Matches` score/goals/assists + complete_match [agent]
- [x] S52 `Fu.Voting` opp MVP/def/keeper + own-team + tally [agent]
- [x] S53 `PostMatchLive` voting UI (4 cats, per-cat skip, 24h) [agent]
- [x] S54 `Fu.Ranking` engine §2.9 exact weights, idempotent ledger [agent]
- [x] S55 `DecayWorker` idle-rank decay toward 50 [agent]
- [x] S56 No-show tracking + 60-day suspension + operator flag [agent]
- [x] S57 Rank-delta inspection UI (tappable full derivation) [agent]
- [x] S58 Dispute/amendment append-only events (§2.10) [agent]
- [x] S59 E2E seed: confirmed full 8v8 + played/finalized 3-2 match
- [x] S60 Smoke scripts + README run instructions

> Built via 3 parallel agents (Matches+Voting ‖ Ranking ‖ Post-match UI).
> E2E seed exercises the full chain — record_score/goal → cast votes →
> complete_match → finalize_match — clean (exit 0). All 6 surfaces
> HTTP 200 authenticated incl. /lobby/:id and /postmatch/:id.

---

## Done: 60/60 slices. Phases 0–4 complete, all committed.
