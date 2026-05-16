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
   Until decided, `mix test` is **30/31 (1 failure)** — Phase 3 gate
   (green suite) is NOT met. Not silently fixed; not silently skipped.

Suite result this pass: **2 properties, 31 tests, 1 failure** (the Balance
timeout above). All other P0 — Resolver (9), Ranking 8v8 + clamp
properties, Lobby captain claim (9), OTP (6) — **green**.
