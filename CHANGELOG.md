# Changelog

The chronological record of this project. Newest first. Work is on
branch `feat/audit-test-deploy-polish`. A remote now exists
(`github.com/irf97/FU_football_united`); the branch was reconciled by
**rebasing local work onto the remote's `817c2b6`** (no force-push,
nothing discarded). Agent pushes to that remote are tooling-blocked —
`git push` is run by the human. Tests grew ~48 → **156**, 0 failures
throughout.

Protocol/conformance versions have their own lineage in
[`fu/conformance/PROTOCOL_CHANGELOG.md`](fu/conformance/PROTOCOL_CHANGELOG.md).

---

## Phase 5 — External reproduction & contract hardening

### App pre-launch hardening — principled architecture before release *(latest)*
- **Admin credential out of source (TDD).** Removed the hardcoded
  `@admin_password` from `login_live.ex`. Secret now sourced from
  `FU_ADMIN_PASSWORD` (`config/runtime.exs`), validated in the
  `Fu.Admin` context via `Plug.Crypto.secure_compare/2` (constant-time),
  **fail-closed** (unset ⇒ admin login disabled, never a fallback). Dev
  default in `config/dev.exs` only. New `login_live_admin_test` (RED→GREEN).
- **SMS release-grade boundary (TDD).** `Fu.SMS` reworked into ports &
  adapters: `Fu.SMS.Provider` (IO-free vendor strategy) + injected
  `Fu.SMS.Transport` (HTTP seam) + fail-closed `Fu.SMS.HTTPAdapter` +
  resilient `deliver/2` (an adapter that raises becomes `{:error, _}`,
  never reaches the OTP caller). **No vendor or HTTP dependency added**
  — deliberate: principled architecture before vendor lock; `LogAdapter`
  stays the default, so no real texts send until a concrete
  provider+transport is wired (a small, localized step). New
  `sms_seam_test`; existing `sms_test` unchanged.
- Suite: **165 tests / 5 properties / 0 failures**. Blocker docs
  (CLAUDE.md, ONBOARDING.md, FU_END_TO_END.html) updated to the honest
  status: admin resolved; SMS architecture resolved, vendor deferred.

### Cold-start onboarding + end-to-end narrative
- `CLAUDE.md` added — the single auto-loaded brief any AI agent reads
  first: the journey, the hard operating constraints, the calibrated-
  honesty ethos, and the honest status (v6; clean-room threshold **not**
  crossed; nothing deployed). Closes the cold-start gap (no agent entry
  point existed).
- `redefinition/FU_END_TO_END.html` — one self-contained, hype-free
  page covering origin → pivot → kernel → conformance → second impl →
  findings → what is **not** built → threshold → next. Linked from
  README, the redefinition map, and CLAUDE.md.
- Audit fixes: corrected a stale contradiction in `redefinition/README.md`
  ("no independent implementation exists" → the Python one exists but is
  contaminated/audit-only); refreshed this header (a remote now exists).

### Reproducibility process hardening (Phase 2 of the de-risk)
- **Dual-runtime CI** (`.github/workflows/conformance.yml`): Elixir
  self-check + independent Python harness, failing **independently**.
- `redefinition/CLEANROOM_READINESS.md` — honest audit of whether a
  fresh implementer could reproduce v6 from docs alone; surfaced the
  untested frontier **R1** (`delta_milli` decimal-vs-binary64 domain)
  and **R2** (Ed25519 verify-equation variant), explicitly out of
  current conformance scope rather than pretended-covered.
- `redefinition/THIRD_IMPLEMENTATION_PLAN.md` — the legitimacy roadmap
  (a plan, not code): what a *truly* independent, uncontaminated third
  implementation must be to cross the threshold.
- Spec-stability pass (docs-only, no behaviour/vectors/version): the
  `[0..N]` inclusive-range trap, "ascending-sorted" median, anti-drift
  test-count wording. Positioning hardened in `fu-protocol.html` (no
  runtime/network presented as existing).

### F3 / F1 / F7 closed (docs-only — no behaviour, no vectors, no version)
- **F3:** `conformance/README.md` step 3 now constructs *both* witnesses
  (the vector needs two; prose built one).
- **F1:** stated explicitly that the 32-byte seed *is* the Ed25519
  private seed (RFC 8032 §5.1.5), no KDF.
- **F7:** the rank fold formula + clamp-once-at-read order written out.
  All four audit findings (F4/F3/F1/F7) closed; every gap an
  independent implementation exposed is now explicit in the contract.

### F4 fix — bootstrap scenario pinned (conformance **v6**)
- An independent Python implementation (`implementations/python-conformance/`,
  built from spec + vectors only, RFC 8032 crypto vendored) reproduced all
  7 sections — but the audit (`DIVERGENCE_LOG.md`) found **F4**: the
  `bootstrap` section pinned only its *outputs*; the node set, encounter
  counts, and the fact that the bootstrap fold is **unsigned** lived only
  in the generator. Two implementers could "pass" with different
  constructions — underspecification, not conformance.
- **Fix:** `bootstrap.scenario` is now structured input *in the contract*
  (subject · attestation · `acq_threshold`/`acq_decay`/`ticks` ·
  `friend_witnesses` · per-node `friends`/`encounters_with_subject`/
  `ingests_attestation`). Outputs unchanged (`["o1","o2"]`/`51.5`/`true`).
  `conformance_test` now *re-derives* bootstrap from the pinned scenario
  (data-driven, TDD: RED→GREEN); the Python harness builds from the same
  inputs. Contract `version` bumped **5 → 6** (additive; propagated through
  `conformance/README.md`, `PROTOCOL_CHANGELOG.md`, `fu-protocol.html`,
  root README). Suite: **156 tests / 0 failures**; Python harness 31/31 @v6.
- Also added (prior, this phase): `redefinition/` (honest three-layer
  framing + `SECOND_IMPLEMENTATION.md` legitimacy contract).

## Phase 4 — Make the protocol tangible

### Mesh Lab (interactive simulator/spec/conformance UI)
- New `/lab` LiveView (`FuWeb.MeshLabLive`) over the **real** `Fu.Mesh.*`
  modules: sign → wire-relay → witnessed rank; collude 2/5 vs 3/5;
  byzantine relay; orphan bootstrap; frozen kernel constants; and the
  conformance harness run **live in-browser** (PASS/FAIL per section).
- Makes the whole P2P arc clickable instead of CLI-only. (156 tests.)

### Documentation pass *(this entry)*
- `README.md` rewritten as the authoritative front door (app **and**
  network, doc map, honest state). This `CHANGELOG.md` added. `TODO.md`
  refreshed. Point-in-time banners prepended to the older standalone docs.

## Phase 3 — The P2P pivot, de-risked into a contract

> Decision: "go live the P2P way." The Phoenix app becomes the
> simulator/oracle; the live runtime target is Rust. Each layer was turned
> into a tested, vector-locked primitive rather than prose.

- **`84ce328` — Adversarial boundary + changelog (conformance v5).**
  `mesh_adversarial_test`: minority collusion cannot move the witnessed
  median; majority can (the *stated* limit); byzantine relay mangling is
  dropped (integrity, not availability); partition heals via one bridge.
  `PROTOCOL_CHANGELOG.md` freezes v1→v5 + the two version namespaces.
- **`e9e3f60` — Pipeline capstone (v4).** Two nodes converge on a
  witnessed rank using **only framed bytes** (sign→canonical→encode→MTU
  chunk→stream→decode→ingest_signed→relay). `V3.held_attestations/2`.
- **`e6516ee` — Adversarial decode robustness.** Properties: arbitrary
  garbage and any prefix never crash `Wire.decode` (L24 hostile peer).
- **`8dab840` — Wire framing codec (v3).** `Fu.Mesh.Wire`: length-
  delimited, SHA-256-digest-checked frame; decode (incomplete/oversize/
  corrupt/version/bad_frame); `decode_stream`; MTU chunking; StreamData
  round-trip property. Byte-exact `wire` vector.
- **`82730c1` — Language-stable canonical (v2).** Canonical delta moved
  from float-string to `round(delta*1000)` integer — kills cross-language
  float-format divergence (the v1→v2 break).
- **`1c5a449` — Identity + conformance + protocol spec.**
  `Fu.Mesh.Identity` (real Ed25519, `keypair_from_seed` for deterministic
  vectors / persona recovery), `bench/conformance_vectors.exs` →
  `conformance/vectors.json`, `conformance/README.md` (CI gate),
  `test/fu/conformance_test.exs` (reference self-verifies),
  `fu-protocol.html`.
- **Mesh model v1→v3 + friendless-bootstrap fix** (in `adedadb`/early
  Phase 3 work): `Fu.Mesh` (append-only — exposed the Scuttlebutt
  blow-up), `.V2` (friend-graph + TTL — flat O(network) storage, but
  witness delivery collapsed), `.V3` (subject-directed relay +
  acquaintance tier — ~100% witness delivery at 10k, NFC-feasible).
  Provisional-witness fix re-validated: orphan recoverability
  100/80.7/90.5% at 100/1k/10k. Scale harnesses under `fu/bench/`.
- **`fu-node.html`** — Solid Node full architecture: 25 operational
  layers (systemd, WireGuard, SQLite WAL, Mender, sandboxing, …) on the
  IrfTek 6-primitive kernel (Object/Authority/Propagation/Projection/
  Anchor/**Expiry** promoted first-class). Local AI scoped to robot
  persona/voice. Two device classes (phone client vs solid node).

## Phase 2 — Product depth + doc suite

- **Lock & penalty lifecycle.** Soft join → explicit lock-in (commitment);
  fast-path confirm when all slots filled by locked members; T-3h resolver
  force-locks stragglers; bailing after lock-in bans (1d >24h / 1w ≤24h,
  stacking). Browse/Lobby/Quick-match wired; quick-match **Accept =
  lock-in**.
- **Tactics manager.** Captain-guarded formation/style/notes
  (`Fu.Tactics`, test-locked: non-captain/wrong-team rejected); squad
  preview + positions board on `/match`.
- **Position model** settled: per-main default sub-position
  (`def_sub/mid_sub/fwd_sub`); main derived; **invariant test-locked that
  sub-positions never reach matchmaking**. Shown across home/profile/
  rosters/browse/chat.
- **Identity & cosmetics:** nickname/nation/birthdate→age (playstyle
  removed); 39-legend / 24-kit avatar system with patterns + hair; 4
  themes (dark/midnight/pitch/daylight) with persistence fix.
- **Auto-queue** `/queue` (timer + pops, soonest-first) and persistent
  queue chatroom.
- **Doc suite created:** `fu-network-pitch`, `fu-dossier`, `fu-spec`,
  `fu-features`, `fu-dashboard` (single-file, framework-free).

## Phase 1 — Audit, harden, fill the gaps

- **Audit brief** → `AUDIT.md` (WIRED/PARTIAL/MISSING with file:line
  evidence), `DEPLOY.md`, `POLISH.md`, `STACK.md`; first real ExUnit
  suite + StreamData properties.
- **Integration fixes:** in-app match completion (`Matches.submit_result/3`,
  idempotent) so the rank loop closes; `Fu.Balance` non-8v8 infinite-loop
  fixed (strict-progress + fuel cap); `Queues.join` changeset-crash fixed.
- **Spec decision:** 8v8 **and 7v7** are rated.
- **AUDIT closed to 17/17 WIRED:** #6 friend-group queue-as-unit wired,
  #12 live-match + captain pause built, #1 OTP hardened (rate-limit +
  attempt cap + pluggable `Fu.SMS` adapter).
- **Friends** system completed; **IrfTek** paper reconciled →
  `Fu.Events` semantic-event alignment slice (`docs/irftek-*`,
  `docs/ALIGNMENT.md`, `docs/FU-APPENDIX.md`).
- UI refinement passes (GPU-only motion, readability, reserved lime).

## Phase 0 — MVP

- Built to `fumvpspec` v1.2: 60-slice decomposition (`SLICES.md`,
  `FRONTEND_SLICES.md`), Phases 0–4, Elixir/Phoenix-LiveView/Postgres,
  the six-surface loop, contexts + supervised workers, the §2.9 rank
  engine, multi-format, password-gated admin. (`adedadb` is the initial
  import of all pre-version-control work.)

---

## Honest status

- **App:** complete, 156 tests/0 fail, 17/17 audited features WIRED.
  Pre-launch blockers: real SMS adapter, admin credential out of source.
- **Network:** deterministic simulation + a frozen, self-verifying
  conformance contract (v5). The Rust runtime, real BLE/NFC transport,
  the phone client, and the node OS layer are **unbuilt**. Friendless
  bootstrap is mitigated (~90% @10k), not zero.
- Nothing pushed to a remote.
