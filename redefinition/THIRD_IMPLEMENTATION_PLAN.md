# Third implementation — legitimacy roadmap

**This is a plan, not an implementation.** Its only purpose is to define
what a third implementation would have to be in order to actually move
the project across the clean-room legitimacy threshold that
`SECOND_IMPLEMENTATION.md` defines and the Python implementation
*explicitly did not cross* (its author had contaminated context).

Nothing here changes the contract. Building this is optional and out of
this repo's current scope.

## Why a third one is needed

State of evidence today:

- **Elixir reference** — the oracle. Self-consistent; checks itself.
- **Python implementation** — reproduces 31/31 v6 vectors from spec +
  vectors, with a vendored RFC 8032. **But** its author (an AI instance)
  had prior exposure to paraphrases of the algorithm. Per the contract
  this is a *spec-sufficiency audit*, not an independence proof. It
  raised the contract's quality (F1/F3/F4/F7) — it did not certify it.

A third implementation exists to convert "the contract appears
sufficient" into "an actor with no inside knowledge reproduced it." That
is the only thing that upgrades the claim from *reproducible-in-
principle* to *independently reproduced*.

## What counts as "truly independent"

All of the following are **required**; failing any one means the result
is informative but does **not** cross the threshold:

1. **No contaminated context.** The implementer (human or model) has had
   **zero exposure** to: the Elixir source, the Python implementation,
   the generator (`bench/conformance_vectors.exs`), any test file, the
   Mesh Lab, this repository's issue/chat history, or any transcript
   that paraphrases the algorithm. A fresh model session primed only
   with the allowed inputs qualifies; *this* assistant lineage does not.
2. **Different language and runtime** from both Elixir and Python
   (e.g. Rust, Go, TypeScript, C). Not BEAM, not CPython.
3. **Independent crypto path.** Either a different RFC 8032 library or a
   from-scratch implementation — not a port of the vendored Python one.
4. **Different author** from the Elixir reference and the Python
   implementation. Same author, new language is weak evidence.
5. **Disclosed method.** A short statement of who, what language, which
   inputs, and an attestation that the forbidden list was honored.

## Contamination rules

- Allowed, and **only** these: `fu-protocol.html`,
  `fu/conformance/README.md`, `fu/conformance/vectors.json`,
  `redefinition/SECOND_IMPLEMENTATION.md`,
  `redefinition/CLEANROOM_READINESS.md`, and cited public standards
  (RFC 8032, FIPS 180-4).
- Forbidden: everything in `fu/lib/**`, `fu/test/**`,
  `fu/bench/**`, `implementations/**`, `fu/lib/fu_web/**`, and any prose
  (chat, commit body, notes) that explains *how* a primitive works.
- `CLEANROOM_READINESS.md` is allowed deliberately: telling the
  implementer where the known ambiguities are does not leak the
  algorithm; it tests whether the *documented* contract is enough.
- If the implementer consults a forbidden source even once, the run is
  logged as **contaminated** and counts only as another spec-sufficiency
  audit — never as a threshold crossing. Self-attestation of cleanliness
  is recorded as self-attestation (weak), not proof.

## Acceptable inputs / expected outputs

- **Inputs:** the allowed set above. The harness contract is
  `fu/conformance/README.md` step 0–7.
- **Expected outputs:** every value in `vectors.json` v6, byte/value
  exact, for all sections: `identity`, `canonical_attestations`,
  `mesh.signed_ingest`, `bootstrap` (built from `bootstrap.scenario`),
  `wire` (byte-exact `frame_hex`), `pipeline`, `adversarial`. Version
  handshake MUST assert `spec == "fu-mesh-conformance"` and
  `version == 6` and refuse otherwise.

## Evaluation criteria

A run is scored on three independent axes — do **not** collapse them:

1. **Reproduction:** pass/partial/fail per section, byte/value exact.
2. **Independence:** clean / self-attested-clean / contaminated
   (per the rules above). Only *clean* contributes to the threshold.
3. **Divergence findings:** every rule the implementer had to *decide*
   rather than *read* is logged with cause class (impl_bug /
   spec_ambiguity / dependency_mismatch / vector_suspicion), exactly as
   in `DIVERGENCE_LOG.md`. A clean run that surfaces a new spec ambiguity
   is the *most* valuable outcome, not a failure.

## What would increase confidence

- A **clean, different-language, different-author** run that reproduces
  31/31 → the threshold is crossed (still: reproducibility, not
  correctness).
- The same surfacing a divergence on **R1** (decimal vs. binary64
  `delta_milli`) or **R2** (Ed25519 verify variant) from
  `CLEANROOM_READINESS.md` → high value: confirms a real gap and tells
  us exactly which vectors to add.
- Two independent third parties agreeing → strongest practical signal
  short of formal proof.

## What would NOT increase confidence

- This assistant lineage re-implementing in any language (contaminated).
- A model session that was shown the Elixir/Python or this transcript.
- Transliteration of the reference rather than derivation from the spec.
- Curve-fitting constants until the vectors pass instead of implementing
  the stated rules.
- "Passes the harness" presented as "the protocol is correct/secure/
  deployed" — reproduction is not validation, and nothing here is a
  running network.

## Honest ceiling

Even a perfect clean third implementation proves exactly one thing: the
contract is *externally reproducible from its stated inputs*. It does
not prove the trust model is sound, that the bootstrap recovery rate
holds in the field, or that any runtime, radio, or network exists. Those
remain unbuilt and are not claimed.
