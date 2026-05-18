# Test backlog (post-P0)

P0 shipped this pass: `resolver_test`, `ranking_test` (+StreamData props),
`lobby_test` (captain claim), `accounts_otp_test`.

## P1 — write next
- Friend group join 8-player edge cases — **blocked**: `Groups.queue_as_group`
  has no app caller (AUDIT integration break #3); test the context fn directly.
- Position swap mutual-consent state machine (`Lobby.swap_positions` +
  `lobby_live` swap-request/accept/decline PubSub round-trip).
- Voting aggregation with skips (`Voting.tally`, `skip_streak_delta`,
  median keeper score).
- DecayWorker month-boundary behaviour (`Ranking.apply_decay`).

## P2 — nice to have
- Profile CRUD (`profile_live` save/preview/availability).
- Friends list ops (`Friends.request_friend/accept/list/pending`).
- Chat message ordering (`QueueChat`, `lobby_live` chat channels).

## Shipped 2026-05-17 (were deferred, now WIRED + tested)
- Friend-group queue join — `group_queue_test.exs` (HomeLive "Queue this group").
- OTP hardening — `accounts_otp_hardening_test.exs`, `sms_test.exs`.
- Live match surface + captain pause — `matches_clock_test.exs`,
  `match_live_test.exs` (kickoff/pause/resume/elapsed + LiveView flow).
- 7v7 rated — `positions_test.exs`, `ranking_test.exs`.

## Still deferred
- `Ranking.record_no_show` (dead code, zero callers) — no caller to test.
- Voting aggregation with skips / DecayWorker month boundary (P1 above).
- LiveView flow tests for login→home, browse→join (auth helper now exists
  via `log_in_player/2`; add when touching those surfaces).
