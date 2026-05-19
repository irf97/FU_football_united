# CLAUDE.md — cold-start brief

You are a fresh agent in **Football United**. Read this first. It is the
non-obvious, hard-won context you cannot reconstruct from the code or git
log alone. ~2 minutes.

## Read in this order

1. `redefinition/FU_END_TO_END.html` — the whole story, one honest page.
2. `redefinition/README.md` — the three-layer framing.
3. `CHANGELOG.md` — chronological Phases 0→5 (newest first).
4. `fu/conformance/README.md` + `fu/conformance/PROTOCOL_CHANGELOG.md` —
   the contract (currently **v6**) and why it changed.
5. `implementations/python-conformance/DIVERGENCE_LOG.md` — findings
   F1/F3/F4/F7 and the residual R1/R2 frontier.
6. `redefinition/{SECOND,THIRD}_IMPLEMENTATION*.md`,
   `CLEANROOM_READINESS.md` — the legitimacy rules.

## What this repository actually is (do not conflate)

1. **A football app** — Phoenix LiveView / Postgres matchmaking product.
   *Real, tested (156/0), runnable.*
2. **A protocol reference kernel** — deterministic Elixir mesh modules +
   a frozen byte-exact conformance contract. *Real but bounded: a
   self-consistent reference, **not** a proven interop standard.*
3. **A runtime / radio / network / ecosystem.** *Aspirational. Zero of
   it exists.* Never describe it in the present tense.

## What we've been through (digest)

- Built the app (Phases 0–2): lock/penalty lifecycle, tactics, an
  append-only rank ledger, full test suite.
- Pivoted (Phase 3): made the Phoenix app the simulator/oracle and froze
  the trust/sync core into a versioned contract; mesh model v1→v3;
  friendless bootstrap mitigated (~90% @10k sim, not solved).
- Hardened the contract by use: conformance **v1→v6** (v6 pinned the
  bootstrap scenario — the only behaviour-adjacent change, additive).
- Wrote an **independent Python implementation** (vendored RFC 8032,
  zero deps): reproduces **31/31 v6 vectors**. Its author had
  contaminated context, so it is a *spec-sufficiency audit*, **not** a
  clean-room crossing. It surfaced and closed F1/F3/F4/F7.
- Added dual-runtime CI, the clean-room audit + third-impl plan, the
  end-to-end narrative, and this brief.

## Honest status — never contradict these

- Contract is **v6**. Precedence is law: `prose < vectors.json <
  reference code`.
- The **clean-room legitimacy threshold is NOT crossed.** The Python
  impl is contaminated/audit-only. Say this plainly; do not imply
  otherwise.
- **Nothing is deployed.** No Rust runtime, no BLE/NFC transport, no
  phone client, no node OS, no network, no third-party adoption.
- Known untested frontier: **R1** (`delta_milli` decimal-vs-binary64)
  and **R2** (Ed25519 verify variant) — out of conformance scope, not
  pretended-covered.
- App pre-launch blockers, by design: real SMS adapter; admin is a
  **hardcoded demo gate** (a known, flagged blocker — do **not** treat
  it as a vuln to silently patch, nor as a real secret).

## Operating constraints (hard — learned the hard way)

**Dev env (Windows):**
- Run `mix` only via git-bash from `fu/` with `source ../devenv.sh`.
  Never WSL/PowerShell for mix.
- **One mix process at a time** (compile lock). Before any server/test
  run, kill `erl.exe`/`beam.smp`/`epmd.exe` and free port 4000.
- CSS changes need a Tailwind rebuild (`_build/tailwind-windows-x64.exe`)
  + server restart, or they won't show.

**Git:**
- Commit or push **only when the human asks.**
- Every commit message MUST end with exactly:
  `Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>`
- Agent pushes to the external remote are tooling-blocked — the **human
  runs `git push`**. Branch: `feat/audit-test-deploy-polish`. A remote
  exists; reconcile by **rebase, never force-push**.

**Engineering:**
- Strict **TDD**: write the test, watch it fail for the right reason,
  minimal GREEN, refactor. No production code without a failing test.
- **Fix application bugs only with explicit permission.**
- Conformance is law: any normative change ⇒ bump `version`, regenerate
  via `bench/conformance_vectors.exs`, keep `conformance_test` green.
  The bootstrap fold is **unsigned**. Sub-positions never reach
  matchmaking (test-locked invariant).

## Ethos (the spine of this project — honor it)

- **Calibrated honesty over impressiveness.** State strength with
  evidence; state what does not exist plainly. Never market aspirational
  runtime/network features as real.
- **Ambiguity discovery is success**, not failure. Surface
  underspecification; do not paper over it.
- **Don't mark your own homework.** If you read the reference, you are
  contaminated for clean-room purposes — disclose it.
- **Lean beats official-looking.** Doc proliferation was deliberately
  rejected (`LEGITIMACY_LEDGER.md`, `prompts/` — do not recreate them).
- When the human pushes back, take the true part even if it is
  unflattering. This repo's value is its epistemic honesty; protect it.
