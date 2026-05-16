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

## Deferred (PARTIAL/MISSING per AUDIT — not worth testing yet)
- Post-match voting *flow* (no in-app trigger: `complete_match` seed-only).
- `Ranking.finalize_match` *trigger* (seed-only) — the math is P0-tested;
  the wiring is an AUDIT blocker, not a test gap.
- `Ranking.record_no_show` (dead code, zero callers).
- Live match surface (MISSING).
- LiveView flow tests (login→home, home→browse→join, lobby claim):
  scaffold `conn_case` ready; add once auth-session test helper exists.
