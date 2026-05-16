# Appendix A — Football United: the one shipped artifact

_Citable companion to `irftek-paper.md`. Every claim here is verified
against the codebase (`AUDIT.md`, `STACK.md`, `DEPLOY.md`, git history)
and is safe to cite. Written deliberately in the paper's voice but graded
to reality — it documents what exists, not what is intended._

## A.1 What it is

Football United (FU) is the IrfTek programme's **only running system**. It
is a single-region amateur-football matchmaking application: a player
opens it, queues for a pickup match they didn't know existed, and plays it
the same week. It is a **deliberately centralized MVP**, not a deployment
of the local-first substrate the main paper proposes — that distinction is
load-bearing and stated up front so the artifact is not mistaken for the
architecture.

## A.2 As-built architecture (verified)

- **Stack:** Elixir 1.19.5 / Phoenix 1.8.7 / Phoenix LiveView /
  PostgreSQL 17 / Ecto. Tailwind v4 + daisyUI v5. HTTP+WebSocket via
  Bandit. Realtime via in-node `Phoenix.PubSub` (not Channels, not a
  mesh). (`STACK.md`.)
- **Topology:** one server process is the sole authority. There are no
  devices, beacons, BLE/NFC, peers, CRDTs, or ledgers. A "field" is a
  Postgres row (`Fu.Fields.Field`); authority is the server, not the
  place. This is the inverse of the paper's §9 "field = local authority,
  phones = ephemeral mirrors".
- **Contexts:** `Accounts` (phone-OTP), `Fields`, `Queues`, `Positions`,
  `Matching`, `Friends`, `Groups`, `Booking`, `Balance`, `Matches`,
  `Voting`, `Ranking`, `QueueChat`, `Admin`.
- **Surfaces (LiveView):** Login, Home, Browse, Lobby, Post-match,
  Profile, QueueChat, Admin — server-rendered, minimal JS (one
  `ChatScroll` hook). This is the part of the paper (§12) that the
  artifact genuinely realises.
- **Background workers:** `Fu.Queues.Resolver` (T-3h partial-fill
  resolution) and `Fu.Ranking.DecayWorker` (idle-rank time decay) in the
  supervision tree — a small, real instance of the paper's §7 "time
  decay / selective persistence" idea.
- **Trust/identity:** single phone-OTP identity, one profile, one avatar.
  No personas, no vault (paper §8 is unbuilt).

## A.3 Coordination model (verified, with the gap)

The real loop is: browse open queues → join (individual or friend group)
→ at T-3h the `Resolver` confirms / extends-once / cancels → on confirm,
`Balance` snake-drafts two rank-balanced teams → lobby opens with a
sequenced captain claim (keeper 60s → highest-rank 60s → free 120s →
random) → post-match peer voting feeds the deterministic, append-only
rank ledger (`Ranking`, spec §2.9).

**AUDIT integration break #1 — RESOLVED.** The captain now records the
final score from the lobby (`Fu.Matches.submit_result/3` → record score →
`complete_match` → `Ranking.finalize_match`, idempotent, confirmed-queue
only). The ranked loop closes end-to-end in-app: a real match now produces
a rank change and opens post-match voting. TDD-covered
(`matches_submit_test.exs`, `lobby_submit_test.exs`); suite 48/0. The
remaining pre-launch blocker is therefore the OTP abuse surface
(rate-limit `request_otp`/`verify_otp`), not match completion. Still
absent (by scope, not defect): a live *in-play* surface + captain pause
(spec feature 12) — score entry is post-whistle, in the lobby.

## A.4 Verification posture

- Audit: 12/17 spec features WIRED, every claim file:line-cited
  (`AUDIT.md`, `audit/raw/`).
- Tests: ExUnit suite green — Resolver, Ranking (incl. StreamData
  property tests on the rank math), captain-claim, OTP, friends, and a
  regression for the join-crash. `mix test` exit 0.
- A real latent bug was found *by* the tests and fixed with approval:
  `Fu.Balance.assign_teams` non-terminated for every non-8v8 format
  (8v8 happened to converge). Termination is now a strict-progress
  guard + fuel cap.
- Deploy posture documented (`DEPLOY.md`): Fly.io single-node (the two
  named GenServers have no multi-node story), MessageBird SMS behind a
  behaviour, OTP rate-limiting as a launch blocker, AppSignal.

## A.5 How to cite this honestly

> "Football United is IrfTek's only running system: a centralized
> Phoenix-LiveView/Postgres matchmaking MVP. It realises the paper's
> §12 (server-authoritative semantic UI) and narrow instances of §7
> (time-decay/selective-persistence via the rank ledger and decay
> worker). It does **not** implement the local-first, proximity-governed,
> AI-runtime, device, or ledger layers (§§1–6, 8–11, 13); those remain
> architectural direction. The ranked loop now closes end-to-end in-app
> (captain submits the score in the lobby); the remaining pre-launch
> blocker is OTP rate-limiting, not match completion."

Do not cite FU as evidence of proximity governance, AI-readable
distributed cognition, IMM hardware, or blockchain coordination — none of
those exist in it.
