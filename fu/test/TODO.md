# Test backlog

Suite: **156 tests / 5 properties / 0 failures** (as of 2026-05-19). Full
project history: `/CHANGELOG.md`.

## Shipped & test-locked (was backlog, now done)

- Lock lifecycle & bail penalties — `queues_lock_test`, `lock_ui_test`.
- Captain tactics guard — `tactics_test`, `match_live_test`.
- Sub-positions never reach matchmaking (invariant) — `position_detail_test`.
- OTP hardening — `accounts_otp_hardening_test`, `sms_test`.
- Live match clock / completion — `matches_clock_test`, `matches_submit_test`,
  `match_live_test`, `lobby_submit_test`.
- Friend-group queue-as-unit — `group_queue_test`.
- Rated 8v8 + 7v7 — `positions_test`, `ranking_test`.
- Quick-match pops — `matching_pops_test`.
- Mesh model — `mesh_test` (v1), `mesh_v2_test`, `mesh_v3_test`
  (+ bootstrap/provisional witnesses), `mesh_identity_test` (Ed25519),
  `mesh_wire_test` (codec + adversarial-decode properties),
  `mesh_pipeline_test` (byte-only convergence), `mesh_adversarial_test`
  (collusion boundary / byzantine relay / partition-heal).
- Conformance self-check — `conformance_test` (reference reproduces
  `vectors.json` v5).
- Mesh Lab — `mesh_lab_test` (mount, live harness PASS, sim actions).
- Ranking math — `ranking_test` + StreamData clamp properties.

## Still open (genuinely worth writing, not blockers)

- LiveView flow tests: login→home, browse→join→lobby (auth helper
  `log_in_player/2` exists; add when touching those surfaces).
- `Voting.tally` skip aggregation + median keeper score edge cases.
- `Ranking.apply_decay` month-boundary behaviour.
- `QueueChat` / lobby chat message ordering.

## Won't / dead

- `Ranking.record_no_show` — zero callers (dead code); nothing to test
  until it has a trigger.

## Out of this repo (the real remaining build)

- The Rust runtime is verified against `conformance/vectors.json` via the
  harness contract (`conformance/README.md`), not ExUnit.
- Real BLE/NFC transport, phone client, node OS layer — not here.
