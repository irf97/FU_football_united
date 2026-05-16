# Football United · Audit
_Generated: 2026-05-16 · branch `feat/audit-test-deploy-polish` · raw command output in `audit/raw/`_

Every claim below is backed by a file:line traced from the captured enumeration
(`audit/raw/`). "WIRED" = reachable end-to-end from a real UI entry point with
observable Repo/PubSub side effects. "PARTIAL" = the unit exists and mutates
state correctly but a link in `UI → handler → context → Repo → PubSub` is
missing. "MISSING" = no implementation/surface.

## Summary

- Features **WIRED: 12 / 17** _(feature 16 was P2-PARTIAL, Balance loop fixed)_
- Features **PARTIAL: 4 / 17**
- Features **MISSING: 1 / 17**
- Integration breaks: **4 identified, #4 (Balance loop) RESOLVED in Phase 2**
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
| 1 | Phone-OTP login + session | WIRED | `login_live.ex:16,27` → `accounts.ex:16` (`request_otp`) / `:35` (`verify_otp`) → `Repo.insert` + `sms.ex:8`; session via `session_controller.ex` + `player_auth.ex` | `Fu.SMS` is a log stub; **no rate-limit** on `request_otp`; **no attempt cap / lockout** on `verify_otp` (replay *is* blocked via `consumed_at` `accounts.ex:51`). Deploy blockers. |
| 2 | Profile setup | WIRED | `profile_live.ex:46` save → `accounts.ex:78` `update_profile` → `Repo.update`; availability `:97/:103`; preview `:32` | — |
| 3 | Queue browser + filters | WIRED | `browse_live.ex:43/50/59` toggle/time/format → `queues.ex:106` `browse/2` (time/pos/format/distance filters) | — |
| 4 | Position-fill widget | WIRED | `queues.ex:64` `fill_status/1`, `:82` `needs_position?`; rendered in `browse_live.ex` queue card | — |
| 5 | Join queue (individual) | WIRED | `browse_live.ex:20` join → `queues.ex:215` `join/3` → `Repo` + `broadcast/2` (`queues.ex:200`) | — |
| 6 | Join queue (friend group ≤8) | **PARTIAL** | `home_live.ex:58` `Groups.create_group`, `:65` `Groups.add_member` wired; `groups.ex` `queue_as_group` exists | **No LiveView calls `Groups.queue_as_group`** — a group can be formed but never queued into a match from the UI (only `phase2_smoke.exs` exercises it). |
| 7 | T-3h lock + partial-fill | WIRED | `application.ex:15` `Fu.Queues.Resolver` supervised → `resolver.ex:21` tick → `queues.ex:359` `due_for_resolution` + `:317` `resolve_partial_fill` → `Repo` + broadcast. Idempotent via `state == "open"` filter (`queues.ex:362`). | No 8v8→7v7 format *downgrade* (spec §2.4 as implemented = confirm/extend-once/cancel only — matches `fu-mvp-spec`; the frontend-plan's downgrade example is not in the canonical spec). |
| 8 | Lobby rosters + avg rank | WIRED (8v8 only) | `lobby_live.ex:13` mount → `Balance.assign_teams` + `Balance.rosters` (`:46`) | Inherits Integration break #4: `Balance.assign_teams` hangs for non-8v8 → `LobbyLive.mount` hangs for any non-8v8 confirmed queue. |
| 9 | Sequenced captain claim | WIRED | `lobby.ex:34` `claim_phase` (keeper60→ranked120→free240→random), `:59` `eligible_to_claim?`, `:78` `claim_captain` → `Repo`; `lobby_live.ex:103` handler, `:69` 1s tick → `random_assign` (`lobby.ex:96`) | Lobby-open anchor approximated by `queue.updated_at` (`lobby.ex:45`, documented). `claim_phase/2` takes injectable `now` → testable. |
| 10 | Position swap (mutual consent) | WIRED | `lobby_live.ex:137` swap-request → PubSub `{:swap_request}` → `:159` swap-accept → `lobby.ex:116` `swap_positions` `Repo.transaction` (same-team guard `:121`) | — |
| 11 | Lobby chat (3 channels) | WIRED | `lobby_live.ex:10` `@channels ~w(team match group)`, `:122` send → broadcast `{:chat}` → `:85` `handle_info` | Ephemeral (in-assigns + PubSub, not persisted) — per spec §2.5 this is acceptable. |
| 12 | Live match UI + captain pause | **MISSING** | No `MatchLive`, no `/match*` route (`audit/raw/routes.txt`), no "pause" handler anywhere (`audit/raw/handle-events.txt`) | Entire surface absent. This is also where match-score entry would live (see Integration break #1). |
| 13 | Post-match voting (skip, penalty) | **PARTIAL** | `post_match_live.ex:57/80/85` vote/skip/skip-all → `voting.ex:42` `cast` / `:55` `skip` → `Repo`; skip detector `voting.ex:116`; tally `:151` | Gated by `voting_open?` (`voting.ex:101`) which needs a `MatchResult.votes_close_at` — set only by `Matches.complete_match`, **which has no app caller** (seed-only). So voting is unreachable in-app except on the seeded queue. Categories shipped = 3 (`mvp/defender/keeper`, `voting.ex:25`) with own/opp via a flag, vs spec's "4". |
| 14 | Rank system (Ranking + Decay) | **PARTIAL** | `ranking.ex:74` `finalize_match` — deterministic, idempotent (`:77-82`), transactional (`:91`), §2.9 breakdown (`:132`). `DecayWorker` supervised (`application.ex:16`) → `ranking.ex:325` `apply_decay`. | `finalize_match` has **no production caller** (only `seeds.exs:201`). `ranking.ex:246` `record_no_show` has **zero callers anywhere** (dead). `file_dispute` is called from `post_match_live.ex:100` but wrapped in `try/rescue/catch` that swallows all errors and flashes success regardless (`:99-107`). Decay path itself: WIRED. |
| 15 | Friends list + invite + requests | WIRED _(PARTIAL → **completed**)_ | `home_live.ex` add-friend form → `Friends.request_by_phone/2`; accept-friend & decline-friend → `accept_friend`/`decline_friend`; incoming/outgoing/list/invite all rendered. `Friends` context extended (`request_by_phone`, `decline_friend`, `pending_outgoing`). | Was: no send-request UI. Now full add/invite/accept/decline/cancel, 5 green DB tests (`test/fu/friends_test.exs`). |
| 16 | Multi-format (5v5–11v11, rated 8v8) | WIRED _(PARTIAL in P2 → **fixed**)_ | `positions.ex` formats; `queues.ex:20`; `ranking.ex:136` rated branch; `balance.ex` `feasibility_swaps/4` now terminates all formats (suite green incl. 7v7) | Was a non-8v8 `Balance.assign_teams` infinite-loop; fixed (strict-progress + fuel cap, Irfan-approved). Integration break #4 RESOLVED. |
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

1. **Match-lifecycle has no application entry point.** _Severity: blocker._
   - Callers of `Matches.record_score/record_goal/complete_match` and
     `Ranking.finalize_match`: **only `priv/repo/seeds.exs:185-201`**
     (`audit/raw` grep). No LiveView, controller, or worker invokes them.
   - Missing link: a referee/operator/captain surface to enter score + goals
     and complete the match. Without it `voting_open?` (`voting.ex:101`) is
     never true in-app, so feature 13 can't run, and `finalize_match`
     (feature 14) never fires → ranks never change from real play.
   - This is the root cause of PARTIALs #13 and #14 and is *why* #12 matters.

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

1. **No way to finish a match in-app** → ranks/voting only move via the seed
   script. A real footballer's match would never produce a rank change.
   (Integration break #1 — the single most important finding.)
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
