# Second Implementation — the legitimacy contract

This document defines what counts as a legitimate independent
implementation of the Football United protocol kernel, and what does
not. It exists **so the rules cannot be written to fit whatever was
actually done.** It is normative. If an attempt violates a MUST here, it
does not count, regardless of whether the vectors pass.

## Why this matters

The conformance harness today checks the Elixir reference against
snapshots produced by the Elixir reference. That is determinism, not
reproducibility. The only thing that converts this repo from
*self-referential* to *externally reproducible* is an implementation
that reproduces `fu/conformance/vectors.json` **without having seen the
reference's logic.** Everything below protects that one property.

## Allowed inputs (the implementer MAY read only these)

- `fu-protocol.html` — the prose/spec.
- `fu/conformance/README.md` — the conformance contract and procedure.
- `fu/conformance/vectors.json` — the frozen input→output pairs.
- `fu/conformance/PROTOCOL_CHANGELOG.md` — version lineage only.
- Public external standards the spec cites (e.g. RFC 8032 for Ed25519,
  FIPS 180-4 for SHA-256). These are *meant* to be shared ground truth.

## Forbidden (reading any of these voids the attempt)

- `fu/lib/fu/mesh/**` — the Elixir reference (Identity, V3, Wire, etc.).
- `fu/bench/conformance_vectors.exs` — the generator.
- `fu/test/fu/conformance_test.exs` and any `fu/test/fu/mesh_*` tests —
  they encode the reference's own re-derivation path.
- The Mesh Lab LiveView (`fu/lib/fu_web/live/mesh_lab_live.ex`).
- Any transcript, chat log, or notes in which the reference's algorithm
  is paraphrased.

Rule, stated minimally:

```
The second implementation MUST be written from:
  - fu-protocol.html
  - fu/conformance/README.md
  - fu/conformance/vectors.json
The Elixir implementation MUST NOT be read during implementation.
```

## What counts (MUST all hold)

1. **Different language.** Not Elixir/Erlang/BEAM. A reimplementation on
   the same runtime by the same author is the weakest possible evidence
   and does not satisfy the threshold on its own.
2. **Independent code path.** Derived from the spec + vectors, not
   transliterated from the reference.
3. **Reproduces the vectors unaided.** It regenerates every value in
   `vectors.json` (identity, canonical, signed ingest, bootstrap, wire,
   pipeline, adversarial) from the same fixed inputs, byte-for-byte.
4. **Disclosed authorship and method.** Who wrote it, in what language,
   from which inputs, and an attestation that the forbidden list was
   honored. Self-attestation is weak evidence; a *different person* is
   strong evidence. Both are recorded honestly as what they are.

## What does NOT count

- Passing the vectors after reading the reference ("I only peeked").
- Generating the implementation from a transcript that paraphrases the
  algorithm.
- Matching the vectors by tuning constants until they fit (curve-fitting
  to the snapshot instead of implementing the spec).
- A second Elixir module by the same author claiming independence.
- "It mostly matches" — partial reproduction is a divergence, logged as
  one (see below), not a pass.

## Divergence logging (MUST)

Every mismatch found while building a second implementation is
*signal*, not failure to hide. For each divergence, record:

- the vector section and key,
- expected (from `vectors.json`) vs. produced,
- root cause: **spec ambiguity**, **spec error**, **reference bug**, or
  **implementation bug**,
- resolution: which of the four artifacts changed (and note that
  precedence is `prose < vectors.json < reference code` — if the spec is
  ambiguous, the spec gets fixed, not the vectors bent).

A divergence traced to **spec ambiguity** or **spec error** is the most
valuable outcome of the whole exercise: it means the contract was
underspecified and the reference's correctness was resting on unstated
assumptions. Finding that is the point, not an embarrassment.

## Honest limitation of even a passing result

A successful independent reproduction proves the contract is
*externally reproducible from its stated inputs*. It does **not** prove
the semantics are *correct* for the real-world goal — a faithfully
reproduced design flaw is still a design flaw. The threshold removes
ambiguity about *what the protocol is*, not doubt about *whether the
protocol is the right one*.

## Procedure

1. The attempt is run in an isolated worktree, with only the allowed
   inputs in reach.
2. Output is checked against `fu/conformance/vectors.json` by the
   procedure in `fu/conformance/README.md`.
3. Divergences are logged per the section above as they are found.
4. The result — pass, partial, or fail — and the divergence log are
   recorded plainly. A failed or partial attempt that surfaces a real
   spec ambiguity is a *successful* exercise of this contract.
