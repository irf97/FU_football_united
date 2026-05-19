# Football United — Onboarding

Welcome. This repo is **three distinct things**. The fastest way to be
useful is to not conflate them.

1. **A football app** — Phoenix LiveView / PostgreSQL amateur-football
   matchmaking. *Real, tested (156/0), runnable.*
2. **A protocol reference kernel** — deterministic Elixir mesh modules
   frozen into a byte-exact conformance contract (**v6**). *Real but
   bounded: a self-consistent reference, **not** a proven interop
   standard.*
3. **A runtime / radio / network / ecosystem.** *Aspirational — none of
   it exists.* Never describe it in the present tense.

> The repo's core value is its **calibrated honesty**. State strength
> with evidence; state what doesn't exist plainly. Protect that.

## Start here (in order)

1. **`redefinition/FU_END_TO_END.html`** — the whole story on one honest
   page (origin → pivot → kernel → conformance → second impl → findings
   → what is *not* built → threshold → next).
2. **`CLAUDE.md`** — the cold-start brief for AI agents: hard operating
   constraints + ethos. Read it even if you're human; it's the rulebook.
3. **`CHANGELOG.md`** — chronological Phases 0→5 (newest first).
4. **`fu/conformance/README.md`** + `PROTOCOL_CHANGELOG.md` — the
   contract and why it has changed (v1→v6).
5. `implementations/python-conformance/DIVERGENCE_LOG.md` — what an
   independent implementation found (F1/F3/F4/F7) and the residual
   R1/R2 frontier.

## Run it

```sh
# Football app (needs Postgres). On Windows: git-bash only.
cd fu && source ../devenv.sh
mix deps.get && mix ecto.create && mix ecto.migrate
mix run priv/repo/seeds.exs
mix phx.server                       # http://localhost:4000

# Conformance gates (no DB):
mix test test/fu/conformance_test.exs                 # Elixir self-check
cd ../implementations/python-conformance
python -m fu_mesh_conformance.harness                 # independent, zero-dep
```

CI runs both gates independently (`.github/workflows/conformance.yml`).

## Honest status — do not contradict

- Contract **v6**. Precedence is law: `prose < vectors.json < reference
  code`.
- **Clean-room legitimacy threshold: NOT crossed.** The Python
  implementation reproduces 31/31 v6 vectors but its author had
  contaminated context — it is a *spec-sufficiency audit*, not an
  independence proof.
- **Nothing is deployed.** No Rust runtime, BLE/NFC transport, phone
  client, node OS, network, or third-party adoption.
- Known untested frontier (out of conformance scope, not hidden):
  **R1** (`delta_milli` decimal-vs-binary64), **R2** (Ed25519 verify
  variant).
- App pre-launch blockers — **updated**: admin credential is now **out
  of source** (runtime env, constant-time, fail-closed) — resolved. SMS
  is now a **release-grade boundary** (provider strategy + injected
  transport, fail-closed); `LogAdapter` is still the default, so **no
  real texts send until a concrete provider+transport is wired** —
  deliberate, a localized add, not an architectural blocker.

## Working here

- **Strict TDD.** No production code without a failing test first.
- **Fix application bugs only with explicit permission.**
- Commit/push only when asked. Commit messages end with the
  `Co-Authored-By: Claude Opus 4.7 (1M context)` trailer. Pushes to the
  remote are done by the human; reconcile by rebase, never force-push.
- Windows: `mix` only via git-bash + `source ../devenv.sh`; one mix
  process at a time; free port 4000 before restarts.
- Any normative contract change ⇒ bump `version`, regenerate vectors,
  keep `conformance_test` green.

## Where it's going (honest milestone ladder)

1. **Clean-room third implementation** — different language, different
   author, no contaminated context. The single event that crosses the
   legitimacy threshold. (See `redefinition/THIRD_IMPLEMENTATION_PLAN.md`.)
2. Pin the R1/R2 frontier with new vectors (would bump the version).
3. App pre-launch blockers: admin credential **done**; SMS boundary
   **done** — remaining is wiring one concrete SMS provider+transport
   (small, localized) plus the usual prod release config.
4. Transport + runtime — large, genuinely unscoped engineering. Not
   implied to be near.
