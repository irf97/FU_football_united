> **Point-in-time document.** Current status & full project history: see README.md and CHANGELOG.md at the repo root. _(2026-05-19 — Football United app + P2P mesh protocol v5; 156 tests, 0 failures.)_

# Test findings (Phase 2)

One-line notes for Irfan to review. Nothing was silently fixed — per the
brief, application bugs are flagged here, not patched.

1. **OTP has no rate limit** (`accounts.ex:16` `request_otp`). Test
   `accounts_otp_test.exs` tag `:documents_gap` asserts the *current*
   insecure behaviour (25 unbounded requests all succeed). Deploy blocker —
   fix belongs in Phase 3 (SMS-layer rate limiting). Code wrong, not test.

2. **OTP verify has no attempt cap** (`accounts.ex:35`). Not test-covered
   (no mechanism to test); reinforced from AUDIT. Brute-force surface.

3. **Replay protection works** (`accounts.ex:51` `consumed_at`) — verified
   green by `accounts_otp_test.exs`. No action.

4. Obsolete scaffold test `test/fu_web/controllers/page_controller_test.exs`
   asserted the removed Phoenix welcome page at `/` — **deleted** (not an
   app bug; removing a dead scaffold test, not silently changing behaviour).

5. **BLOCKER — `Fu.Balance.assign_teams/1` infinite-loops for non-8v8
   formats.** Surfaced by `ranking_test.exs:49` ("unrated format", a 7v7
   queue): test timed out at 60s, stack pinned in
   `Fu.Balance.feasibility_swaps/3` → `deficit_position/3` (`balance.ex:122-159`).
   Root cause: the recursion's only termination guard is exact state
   equality `{a,b} == {team_a,team_b}` (`balance.ex:135`); a swap that
   changes the teams but does not reduce the position deficit (oscillation)
   never satisfies it → non-termination. 8v8 quotas happen to converge, so
   seeds/manual checks (all 8v8) never hit it.
   Impact: any confirming non-8v8 queue → `LobbyLive.mount` →
   `Balance.assign_teams` hangs the LiveView process (effective per-request
   DoS). **Code is wrong, not the test.** Test wrong-vs-code: code.
   Decision required (brief: "fix only with permission"):
     A) fix `feasibility_swaps` (bound iterations / cycle-detect), or
     B) `@tag :skip` the unrated test + ship the bug as a documented
        DEPLOY blocker and proceed to Phase 3.
   **RESOLVED** (Irfan approved option A): `feasibility_swaps/3` now has a
   strict-progress guard (`total_deficit` must strictly decrease) + a fuel
   cap (`balance.ex` `feasibility_swaps/4` + `total_deficit/3`).
   Deterministic, terminating, matches spec §2.7 "or no improving swap
   remains". Suite re-run → green; 8v8 paths unaffected.

Suite result after fix: **2 properties, 31 tests, 0 failures** (0.8s).
P0 green: Resolver (9), Ranking 8v8 + clamp/monotonic properties, Lobby
captain claim (9), OTP (6). Phase 3 gate (green suite) MET.

6. **BUG (user-reported, post-brief) — `Queues.join/3` leaked an
   `Ecto.Changeset` → LiveView crash. FIXED.** Player had a `status:
   "left"` `queue_memberships` row for queue 49; `already_member?/2` only
   checks `status == "queued"`, so `join` proceeded to `Repo.insert`, hit
   the `(queue_id, player_id)` unique index, returned `{:error,
   %Ecto.Changeset{}}`; `BrowseLive.join_error/1`'s `"#{other}"` then
   raised `Protocol.UndefinedError` (String.Chars on Ecto.Changeset) and
   crashed the LiveView. Two fixes: (a) `queues.ex` `join/3` now
   reactivates an existing (left) row instead of blind-inserting, and
   normalises any changeset error to `{:error, :already_joined}`;
   (b) `browse_live.ex` `join_error/1` guards `is_atom/1` + safe generic
   fallback (never interpolates arbitrary terms). Regression:
   `test/fu/queues_join_test.exs` (3 tests). Suite → **34 tests, 0
   failures**. Not a Phase-4 regression (pre-existing error path).
