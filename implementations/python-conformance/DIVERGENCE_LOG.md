# Divergence log — Python second implementation

Run: all **31/31** assertions reproduce `vectors.json` **v6**
value/byte-exact (identity 5, canonical 8, signed_ingest 3, bootstrap 3,
wire 5, pipeline 2, adversarial 3, meta 2).

**No numeric divergence occurred. That is not the same as "the spec was
sufficient."** Per `../../redefinition/SECOND_IMPLEMENTATION.md`, a
divergence includes *spec ambiguity* — a rule the implementer had to
*decide* rather than *read*. Four were found. **All four are now
resolved** — F4 by pinning the scenario (spec v6); F3/F1/F7 as
docs-only spec clarifications (no behaviour, vector, or version change).
The audit's purpose is served: every gap an independent implementation
exposed has been written into the contract.

| ID | Section | Class | Severity |
|---|---|---|---|
| F4 | bootstrap | spec_ambiguity | **RESOLVED — pinned in spec v6** |
| F3 | signed_ingest | spec_ambiguity | **RESOLVED — prose clarified (no behaviour change)** |
| F1 | identity | spec_ambiguity | **RESOLVED — stated explicitly (docs-only)** |
| F7 | mesh rank | spec_ambiguity | **RESOLVED — fold formula stated (docs-only)** |

---

## F4 — bootstrap is an output with no specified input scenario  *(RESOLVED, spec v6)*

> **Resolution (conformance v6).** `vectors.json` now carries
> `bootstrap.scenario` — subject, the (unsigned) attestation,
> `acq_threshold`/`acq_decay`/`ticks`, `friend_witnesses`, and per-node
> `friends`/`encounters_with_subject`/`ingests_attestation`. The
> reference self-check (`conformance_test`) and this Python harness both
> *build* bootstrap from those pinned inputs instead of inventing one;
> the previously-hidden fact that the bootstrap fold is **unsigned**
> (`ingest`, not `ingest_signed`) is now explicit (`scenario.attestation
> .signed == false`, spec §9 P9.4/P9.5, `PROTOCOL_CHANGELOG.md` v6). The
> invented-scenario code below was deleted. Original finding kept for
> the record:

**Source:** `conformance/README.md` step 4 ("reproduce the
provisional-witness scenario (acquaintance threshold from §6)");
`fu-protocol.html` §9 (P9.1–P9.3), §6 (thresholds 3 / 6).

**Problem.** The spec states the *rule* (a provisional witness is a
non-self node that holds S's record and regards S as a sustained
acquaintance, encounters ≥ 3) but never the *scenario*: which nodes
exist, their encounter counts, which hold `orphan`'s record, or how the
value `51.5` arises. `vectors.json` gives only the outputs
(`provisional_witnesses=["o1","o2"]`, `recoverable_rank=51.5`).

**What I did (not silent):** invented a scenario — `o1`,`o2` with
`encounters=3` holding an `orphan` attestation of `+1.5`; a stranger
`s1` with `encounters=1` (must be excluded); an `orphan` node (must be
self-excluded). It passes.

**Why the PASS is hollow.** It proves my invented scenario is
*consistent with* the vector, not that the spec *determines* it. A
second implementer inventing a different but rule-valid scenario would
also "pass." That is underspecification, not conformance. **Cause:
spec_ambiguity. Recommended fix:** the spec MUST pin the bootstrap
scenario concretely (node set, encounter counts, the record's delta) —
or the bootstrap section is not a conformance test, it is a vibe check.
Not patched here; reported, per instruction.

## F3 — signed_ingest prose ingests one witness, vector needs two  *(RESOLVED — prose clarified)*

> **Resolution.** `conformance/README.md` step 3 now explicitly
> constructs `node w2 = new_node("w2",["p"]); ingest_signed(w2, att)`
> before the `witnessed_rank({w1,w2},…)` assertion, with an inline note
> on *why* (per §8 an unknown witness contributes 50.0, so the 51.5
> vector requires both). **No behaviour, vector, or version change** —
> the generator and `conformance_test` always built both witnesses; only
> the prose omitted `w2`. Docs-only fix. Original finding kept below.

**Source:** `conformance/README.md` step 3 vs. `fu-protocol.html`
§8 (P8.1/8.3).

**Problem.** Step 3 prose builds `att`, does `ingest_signed(w1, att)`
only, then asserts `witnessed_rank({w1,w2},["w1","w2"],"p") == 51.5`.
`w2` is never constructed or given the attestation. With the literal §8
rule (unknown witness ⇒ 50.0; median index `div(n-1,2)`), views
`[w1=51.5, w2=50.0]` sort to `[50.0, 51.5]`, index 0 → **50.0 ≠ 51.5**.

**Resolution.** The vector (`51.5`) is only reachable if both witnesses
hold the fact, so I ingest into `w1` *and* `w2` (documented in
`harness.py`). Less severe than F4: the vector *forces* the
interpretation (precedence: vectors > prose). **Cause: spec_ambiguity
(prose incompleteness). Recommended fix:** step 3 prose must ingest into
both witnesses (or §8 must define unknown-witness handling explicitly).

## F1 — "32-byte seed → keypair" never says the seed *is* the key  *(RESOLVED — docs-only)*

> **Resolution.** `conformance/README.md` (Primitives) and
> `fu-protocol.html` §3 P3.2 now state explicitly: the 32-byte seed is
> used **directly and unmodified as the Ed25519 private-key seed**
> (RFC 8032 §5.1.5) — no application-level hash/KDF/derivation before
> key generation. No behaviour, vector, or version change. Original
> finding kept below.

**Source:** `fu-protocol.html` §3 P3.2; `conformance/README.md`
(reference uses `:crypto.generate_key(:eddsa, :ed25519, seed)`).

**Problem.** "Derive deterministically from a 32-byte seed" admits
multiple readings (seed = RFC 8032 private key? HKDF of seed? SHA-256 of
seed?). **Resolution.** Implemented seed == RFC 8032 private key; the
`identity[0]` vector (`01·32 → 8a88e3dd…`) matches the standard RFC 8032
value, confirming the reading. Vector-resolved. **Recommended fix:** one
sentence — "the 32-byte seed is the RFC 8032 private key."

## F7 — the rank-fold function is never stated  *(RESOLVED — docs-only)*

> **Resolution.** `conformance/README.md` (Primitives → rank) and
> `fu-protocol.html` §5 P5.5 now state the explicit fold:
> `rank = clamp(base_rank + Σ a.delta for a in pending)`, application
> keyed by `match` id (idempotent; `≤ base_seq` or already-pending not
> re-applied), **clamp applied once to the final sum at read time**, and
> the per-step clamp on compaction past `W = 8` noted for completeness.
> No behaviour, vector, or version change. Original finding kept below.

**Source:** inferred from `signed_ingest` (51.5), `adversarial`
(100.0), `pipeline` (51.5); `fu-protocol.html` §5 P5.3/P5.4.

**Problem.** §5 specifies clamp `[30,100]`, start `50.0`, idempotent by
match id — but never *how* accepted deltas combine into rank. The only
model consistent with every vector is
`clamp(50.0 + Σ deltas of distinct accepted match-ids)`. Implemented on
that basis. Vector-resolved but should be stated. **Recommended fix:**
add the fold formula to §5.

---

## Bottom line

The kernel's *deterministic primitives* (identity, canonical, wire,
pipeline, adversarial) are genuinely reproducible from spec + vectors by
an independent codebase and an independent crypto stack — strong. F4 —
the one *scenario-shaped* section that was asserted rather than earned —
**has been fixed**: bootstrap is now spec-determined via the pinned
`bootstrap.scenario` (conformance v6), and both the reference self-check
and this harness re-derive it from that contract input. The audit did
exactly its job: an independent implementation surfaced an
underspecification invisible while the reference checked itself, and the
contract was tightened in response. **F3, F1, and F7 are likewise
fixed** — all docs-only spec clarifications (step 3 builds both
witnesses; the seed is stated as the direct Ed25519 private seed; the
rank fold/clamp-order is written out), with **no behaviour, vector, or
version change**. All four findings are closed: every gap an independent
implementation exposed is now explicit in the contract rather than
inferable only from the vectors. The honest residual remains the one
stated up top — this was a spec-sufficiency audit by a context-
contaminated implementer, so the clean-room legitimacy threshold is
still uncrossed; what improved is that the contract is now sufficient
*to* a clean-room implementer.
