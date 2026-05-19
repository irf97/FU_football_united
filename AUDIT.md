> **Point-in-time document.** Current status & full project history: see README.md and CHANGELOG.md at the repo root. _(2026-05-19 — Football United app + P2P mesh protocol v5; 156 tests, 0 failures.)_

# Football United · Audit
_Generated: 2026-05-16 · branch `feat/audit-test-deploy-polish` · raw command output in `audit/raw/`_

Every claim below is backed by a file:line traced from the captured enumeration
(`audit/raw/`). "WIRED" = reachable end-to-end from a real UI entry point with
observable Repo/PubSub side effects. "PARTIAL" = the unit exists and mutates
state correctly but a link in `UI → handler → context → Repo → PubSub` is
missing. "MISSING" = no implementation/surface.

## Summary

- Features **WIRED: 17 / 17** _(2026-05-17: #6 friend-group queue join wired
  via HomeLive "Queue this group"; #12 live in-play UI + captain pause built
  as `/match/:queue_id` MatchLive; #1 OTP hardened — rate-limit + verify cap
  + pluggable SMS adapter)_
- Features **PARTIAL: 0 / 17**
- Features **MISSING: 0 / 17**
- Integration breaks: **4 identified; #1 (match-lifecycle) and #4
  (Balance loop) RESOLVED; #2/#3 remain (no-show dead code, group-queue UI)**
- PubSub integrity: **clean** (no dead broadcasts, no dead subscribers)
- Deployment blockers: **3** (SMS stub, no OTP rate-limit, no OTP attempt-cap)

**Headline:** the contexts are individually sound (real `Repo` mutations,
deterministic rank math, idempotent workers). The defect is *integration*:
the **match-lifecycle has no application entry point**. `Matches.record_score/
record_goal/complete_match` and `Ranking.finalize_match` are called **only
from `priv/repo/seeds.exs`** — never from a LiveView/controller/worker. That
single gap cascades into 3 PARTIAL features (post-match voting, rank
finalization, and — by absence — the entire live-match surface). This is the
classic AI-multi-component *integration-stub* pattern: each part works in
isolation; nothing triggers them in the running product.

## Feature matrix

| # | Feature | Status | Evidence | Gap |
|---|---|---|---|---|
| 1 | Phone-OTP login + session | WIRED **(hardened 2026-05-17)** | `login_live.ex` → `accounts.ex` `request_otp` (rate-limited: 5/phone/15min → `{:error, :rate_limited}`) / `verify_otp` (attempt cap 5 → code burned, `{:error, :locked}`); SMS via pluggable `Fu.SMS` adapter (`Fu.SMS.Adapter` behaviour, default `Fu.SMS.LogAdapter`, real provider config-swappable); session via `session_controller.ex` + `player_auth.ex` | Deploy blockers cleared. TDD: `accounts_otp_hardening_test.exs`, `sms_test.exs`. Remaining: ship a real SMS adapter + secret-store the admin password before production. |
| 2 | Profile setup | WIRED | `profile_live.ex:46` save → `accounts.ex:78` `update_profile` → `Repo.update`; availability `:97/:103`; preview `:32` | — |
| 3 | Queue browser + filters | WIRED | `browse_live.ex:43/50/59` toggle/time/format → `queues.ex:106` `browse/2` (time/pos/format/distance filters) | — |
| 4 | Position-fill widget | WIRED | `queues.ex:64` `fill_status/1`, `:82` `needs_position?`; rendered in `browse_live.ex` queue card | — |
| 5 | Join queue (individual) | WIRED | `browse_live.ex:20` join → `queues.ex:215` `join/3` → `Repo` + `broadcast/2` (`queues.ex:200`) | — |
| 6 | Join queue (friend group ≤8) | **WIRED (2026-05-17)** | `home_live.ex` `group_queues/3` lists fitting queues for the leader → "Queue this group" button → `handle_event("queue-group")` → `Groups.queue_as_group/2` → `Queues.join_group/2`. Non-fitting queues are filtered out. | TDD: `group_queue_test.exs` (fitting queue queues the group; non-fitting shows no button). Only the group leader sees the controls (spec §2.12). |
| 7 | T-3h lock + partial-fill | WIRED | `application.ex:15` `Fu.Queues.Resolver` supervised → `resolver.ex:21` tick → `queues.ex:359` `due_for_resolution` + `:317` `resolve_partial_fill` → `Repo` + broadcast. Idempotent via `state == "open"` filter (`queues.ex:362`). | No 8v8→7v7 format *downgrade* (spec §2.4 as implemented = confirm/extend-once/cancel only — matches `fu-mvp-spec`; the frontend-plan's downgrade example is not in the canonical spec). |
| 8 | Lobby rosters + avg rank | WIRED (8v8 only) | `lobby_live.ex:13` mount → `Balance.assign_teams` + `Balance.rosters` (`:46`) | Inherits Integration break #4: `Balance.assign_teams` hangs for non-8v8 → `LobbyLive.mount` hangs for any non-8v8 confirmed queue. |
| 9 | Sequenced captain claim | WIRED | `lobby.ex:34` `claim_phase` (keeper60→ranked120→free240→random), `:59` `eligible_to_claim?`, `:78` `claim_captain` → `Repo`; `lobby_live.ex:103` handler, `:69` 1s tick → `random_assign` (`lobby.ex:96`) | Lobby-open anchor approximated by `queue.updated_at` (`lobby.ex:45`, documented). `claim_phase/2` takes injectable `now` → testable. |
| 10 | Position swap (mutual consent) | WIRED | `lobby_live.ex:137` swap-request → PubSub `{:swap_request}` → `:159` swap-accept → `lobby.ex:116` `swap_positions` `Repo.transaction` (same-team guard `:121`) | — |
| 11 | Lobby chat (3 channels) | WIRED | `lobby_live.ex:10` `@channels ~w(team match group)`, `:122` send → broadcast `{:chat}` → `:85` `handle_info` | Ephemeral (in-assigns + PubSub, not persisted) — per spec §2.5 this is acceptable. |
| 12 | Live match UI + captain pause | **WIRED (2026-05-17)** | `/match/:queue_id` → `MatchLive`: synced clock from `MatchResult` (`started_at`/`paused_at`/`pause_seconds`), `Matches.kickoff`/`pause`/`resume`/`elapsed_seconds`; captain-only controls + final-whistle `submit_result` → `/postmatch`; PubSub `match:<id>` keeps all screens in lock-step. Reached from `LobbyLive` "Enter live match →" when confirmed. | TDD: `matches_clock_test.exs` (kickoff/pause/resume/elapsed math), `match_live_test.exs` (captain controls, non-captain read-only, final whistle → postmatch). |
| 13 | Post-match voting (skip, penalty) | WIRED _(PARTIAL → fixed via break #1)_ | Voting handlers + tally as before; **now reachable**: captain `LobbyLive` "Final score" → `Matches.submit_result/3` → `complete_match` sets `votes_close_at` → `voting_open?` true → `post_match_live` voting runs. | Minor: 3 categories (`mvp/defender/keeper`) with own/opp via a flag vs spec's nominal "4" — modelling choice, not a break. |
| 14 | Rank system (Ranking + Decay) | WIRED _(PARTIAL → fixed via break #1)_ | `finalize_match` now has a real production caller: `LobbyLive submit-result → Matches.submit_result/3 → Ranking.finalize_match` (TDD: `matches_submit_test.exs`, `lobby_submit_test.exs`). Deterministic/idempotent/transactional as before; `DecayWorker` WIRED. | Remaining minor: `ranking.ex:246` `record_no_show` still has zero callers (dead); `post_match_live.ex` dispute handler still swallows errors via try/rescue. Neither blocks the rank loop. |
| 15 | Friends list + invite + requests | WIRED _(PARTIAL → **completed**)_ | `home_live.ex` add-friend form → `Friends.request_by_phone/2`; accept-friend & decline-friend → `accept_friend`/`decline_friend`; incoming/outgoing/list/invite all rendered. `Friends` context extended (`request_by_phone`, `decline_friend`, `pending_outgoing`). | Was: no send-request UI. Now full add/invite/accept/decline/cancel, 5 green DB tests (`test/fu/friends_test.exs`). |
| 16 | Multi-format (5v5–11v11, rated **8v8 + 7v7**) | WIRED _(PARTIAL in P2 → **fixed**; rated set updated 2026-05-17)_ | `positions.ex` `rated?/1` now `format in ~w(8v8 7v7)` (user decision); `queues.ex:23` forces `rated` from it; `ranking.ex:136` rated branch unchanged (honors the flag); `balance.ex` `feasibility_swaps/4` terminates all formats | TDD: `positions_test.exs`, `ranking_test.exs` ("7v7 IS rated"). Non-8v8 infinite-loop fixed earlier (strict-progress + fuel cap). No automatic 8v8→7v7 *downgrade* path (canonical spec §2.4 = confirm/extend/cancel; not requested). |
| 17 | Admin surface (password-gated) | WIRED | `login_live.ex:38` show-admin / `:41` admin-login (pw check) → `Admin.ensure_admin_player` → token; `/admin` route → `admin_live.ex` (`:26` filter, `:29` toggle-suspend → `Admin.toggle_suspend`) | Shared hardcoded password in source (`login_live.ex`) — acceptable demo gate, not real auth (already flagged in `STACK.md`). |

## PubSub integrity

Topics enumerated from `audit/raw/pubsub-broadcasts.txt` / `pubsub-subscribes.txt`.

| Topic | Broadcast | Subscribe | Verdict |
|---|---|---|---|
| `"queue:<id>"` (`queues.ex:192`) | `queues.ex:200` | `queues.ex:194` (`Queues.subscribe/1`) — callers `lobby_live.ex:25`, `queue_chat_live.ex` | PAIRED — `lobby_live.ex:82` & `queue_chat_live` `handle_info({:queue_changed,_})` |
| `"queues"` | `queues.ex:201` | `queues.ex:197` (`subscribe_all`) — caller `browse_live.ex` | PAIRED — browse `handle_info({:queue_changed,_})` |
| `"queue_chat:<id>"` (`queue_chat.ex`) | `queue_chat.ex:87` | `queue_chat.ex:23` | PAIRED — `queue_chat_live` `handle_info({:queue_message,_})` |
| `"lobby:<id>"` | `lobby_live.ex:75,106,130,149,165` | `lobby_live.ex:26` | PAIRED — `lobby_live.ex:83-98` handles `:captain_changed`, `{:chat}`, `{:swap_request}`, `:swap_done` |

**No broadcasts without subscribers. No subscribers without broadcasts.** PubSub layer is clean.

## Integration breaks

1. **Match-lifecycle had no application entry point — RESOLVED.**
   _Severity: was blocker._
   - Was: `Matches.complete_match` / `Ranking.finalize_match` were
     seed-only; `voting_open?` never true in-app; ranks never moved.
   - Fixed (TDD): `Fu.Matches.submit_result/3` (records score →
     `complete_match` → `Ranking.finalize_match`, idempotent, refuses a
     non-confirmed queue) called from a **captain-only "Final score" form
     in `LobbyLive`** (`handle_event("submit-result", …)` →
     `push_navigate` to `/postmatch/:id`). Tests:
     `test/fu/matches_submit_test.exs` (3, incl. idempotency) +
     `test/fu_web/lobby_submit_test.exs` (2, full LiveView flow + the
     non-captain negative). Suite 48/0.
   - Knock-on: PARTIAL #13 and #14 are now reachable in-app (see matrix).
     #12 (live in-play UI + captain *pause*) is still MISSING — only
     post-match score entry was added, not an in-play surface.

2. **`Ranking.record_no_show/2` is dead code.** _Severity: bug._
   - `ranking.ex:246`, **zero callers** (not even seeds). The no-show penalty
     (spec §2.9, part of feature 14) is implemented but unreachable.

3. **`Groups.queue_as_group` has no UI caller.** _Severity: bug._
   - `home_live.ex` wires group create/add only. Friend-group *queue join*
     (feature 6) cannot be triggered by a user.

4. **`Fu.Balance.assign_teams/1` non-terminated for non-8v8 — RESOLVED.**
   _Severity: was blocker._ _(Found in Phase 2 by `ranking_test.exs:49`.)_
   - `balance.ex:122-141` `feasibility_swaps/3` recurses with only an
     exact-state-equality stop (`:135`); an oscillating swap that changes
     teams without reducing a position deficit loops forever. 8v8 quotas
     converge; 5v5/6v6/7v7/9v9/11v11 do not.
   - Caller path: `LobbyLive.mount` (`lobby_live.ex:13`) →
     `Balance.assign_teams` on any confirmed non-8v8 queue → process hangs
     (per-request DoS). Also blocks Resolver-confirmed non-8v8 lobbies.
   - **FIXED (Irfan-approved):** `feasibility_swaps/4` now requires a strict
     decrease in `total_deficit/3` + a fuel cap — deterministic, terminating
     (spec §2.7 "or no improving swap remains"). `mix test` → green
     (31 tests, 2 properties, 0 failures, 0.8s). See `audit/test-findings.md#5`.

Secondary (not breaks, flagged): `post_match_live.ex:99-107` dispute handler
swallows all errors via `try/rescue/catch` and flashes success
unconditionally — a real `file_dispute` failure is invisible to the user.

## Out-of-spec (shipped beyond `fu-mvp-spec.md v1.2`)

- Persistent **per-queue chatroom** at `/queue/:id/chat` (`queue_chat.ex`,
  `QueueChatLive`) — distinct from spec's ephemeral lobby chat. Functional,
  WIRED. Future work, not scope creep.
- **Mini-footballer SVG avatars** (`fu_web/avatars.ex`) — profile-configured.
- **Admin dashboard** (`/admin`) — not in MVP spec; useful ops surface.

## Code-quality concerns (noted, not fixed — per brief)

- `Fu.SMS` is a **plain module, not a behaviour** → swapping in a real
  provider needs an extract-behaviour refactor (Phase 3.2 finding).
- `accounts.ex:51` ignores the `consumed_at` `Repo.update` result.
- Admin password is a module-literal in `login_live.ex`.

## Critical-path concerns for deployment

1. ~~No way to finish a match in-app~~ **RESOLVED** — captain submits the
   final score in the lobby (`Matches.submit_result/3`); the ranked loop
   now closes end-to-end in-app. (Integration break #1, TDD-fixed.) The
   remaining product gap is now **#2 below**, which becomes the single
   most important pre-launch item.
2. **OTP abuse surface**: unbounded `request_otp` (SMS-bomb / DB-fill) and
   unbounded `verify_otp` guesses (brute-force). Must be rate-limited before
   any public exposure.
3. **`Fu.SMS` is a log stub** — no real OTP delivery.
4. Friend-group queue join and friend-request *send* have no UI.

## Verdict vs the brief's "stop if <50% WIRED" gate

12/17 WIRED (> 50%). The codebase is **not** in rebuild territory — the
contexts are well-built. Proceeding to Phase 2, but Phase 2 will test only
WIRED features (the brief's rule), and the match-lifecycle gap is recorded
here as the #1 thing to resolve before launch (a wiring task, not a rebuild).
