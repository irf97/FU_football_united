# Clean-room readiness audit (conformance v6)

**Question:** could a *fresh* implementer — no exposure to the Elixir
reference, the Python implementation, the generator scripts, the tests,
or this project's chat history — reproduce all 31 v6 vectors from only:

- `fu-protocol.html`
- `fu/conformance/README.md`
- `fu/conformance/vectors.json`
- `redefinition/SECOND_IMPLEMENTATION.md`

**Honest verdict up front.** *Reproducing the 31 pinned vectors:*
**likely yes** — the vectors plus prose now over-determine almost every
section. *Being a genuinely independent confidence signal:* **medium** —
several rules are still rescued by the vectors rather than stated, and
two are notation traps a careful reader could fall into. *Correctness of
the protocol itself:* **out of scope** — reproducing a frozen design
proves reproducibility, not that the design is right.

This audit treats every ambiguity as a finding (success), not a defect
to hide.

---

## Resolved since the audit began (recap)

| ID | Was | Now |
|---|---|---|
| F4 | bootstrap scenario only in the generator | pinned as `bootstrap.scenario` (v6) |
| F3 | step 3 prose built one witness | prose builds both `w1`,`w2` |
| F1 | "32-byte seed" derivation unstated | stated: seed *is* the Ed25519 private seed |
| F7 | rank fold/clamp-order unstated | fold formula + clamp order written out |

These no longer require the implementer to guess.

---

## Remaining hidden assumptions

- **R1 — `delta_milli` numeric domain (serialization edge case).** The
  spec says `delta_milli = round(delta*1000)`, round-half-away-from-zero.
  It does **not** say *in what domain* the multiply happens: IEEE-754
  binary64 (`round(float*1000.0)`) vs. exact decimal. For the four
  pinned deltas (`1.5`, `-0.8`, `0.3`, `0.1+0.2`) both domains agree
  (that is *why* they pass). For other deltas they can disagree at the
  half-ulp boundary. A third implementer choosing exact-decimal vs.
  binary64 would pass the vectors and **diverge on untested inputs**.
  This is the single most likely real-world divergence.
- **R2 — Ed25519 verification variant.** RFC 8032 permits both the
  cofactored (`[8][S]B = [8]R + [8][h]A`) and the unbatched
  (`[S]B = R + [h]A`) verify equations, and implementations differ on
  small-order / non-canonical `R`/`S` rejection. Every vector signature
  is honest, so this surface is **untested**. Two correct-per-RFC
  implementations could disagree on adversarial signatures the contract
  never exercises.
- **R3 — `new_node(id, friends)` second argument.** The conformance
  scenarios pass `["p"]`/`["P"]`/`[]`. Nothing states that, in the
  asserted paths (no `tick`/`reconcile` is invoked), the `friends`
  argument is **inert** for every asserted output. A fresh implementer
  may reasonably assume friends affects `rank`/`knows`/`witnessed_rank`
  and waste effort, or model it differently — harmless to the vectors,
  but a real "what does this argument do?" gap.
- **R4 — witness-list semantics in `witnessed_rank`.** §8 + step 3 now
  make the scenario reproducible, but the *rule* "an unknown witness
  contributes 50.0" is conveyed only by an inline comment in step 3, not
  as a normative clause. An implementer who instead *filters* unknown
  witnesses gets the same answers on every current vector (they all have
  all witnesses informed) but a different model.

## Undefined terminology

- **U1 — integer→string format in `canonical`.** `"{match}|{player}|{delta_milli}"`
  assumes base-10, no leading zeros, `-` for negatives, no `+`, no
  thousands separators, ASCII digits. The examples imply it; it is never
  stated. A locale-aware or zero-padded formatter would diverge.
- **U2 — `[0..N]` slice notation (drift trap).** `fu-protocol.html`
  wrote `SHA-256(public_key)[0..16]` and `SHA-256(payload)[0..4]`
  alongside "first 16 hex chars" / "first 4 bytes". `0..16` read as an
  inclusive range (Elixir/Ruby semantics) is **17**, `0..4` is **5** —
  contradicting the prose. Only the vectors' fixed lengths save a reader
  who trusts the bracket over the words. *Fixed this pass* (see Spec
  stability below).
- **U3 — "sorted views" direction.** Median is "index `div(n-1,2)` of
  the sorted views" — ascending vs. descending was unstated. Symmetric
  for the current vectors; not in general. *Fixed this pass.*

## Implicit state transitions

- **S1 — ingest signed vs. unsigned per section.** Now mostly explicit
  (bootstrap = unsigned `ingest`, others = `ingest_signed`), but the
  contract states this per-scenario in prose, not as a table. An
  implementer must read carefully to not apply signature verification in
  the bootstrap path (where it would still pass, since the rule there is
  acquaintance, not authorship — but the *model* would be wrong).
- **S2 — idempotence key.** "Idempotent by match id" + the F7 fold make
  re-ingest safe; the interaction with the (out-of-scope-for-vectors)
  `base_seq` checkpoint is described but never exercised by a vector, so
  an implementer cannot validate their checkpoint logic against the
  contract at all — it is spec-only, untestable here.

## Serialization edge cases (beyond R1/R2)

- **E1 — `player` / witness byte form.** "Opaque UTF-8, no `|`" is
  stated for `player`; witness ids are encoded the same way on the wire
  but the UTF-8 + `|`-freedom constraint is not restated for witnesses.
  All vectors use ASCII, so untested.
- **E2 — empty witness set on the wire.** `wit_count = 0` path is not
  covered by the `wire` vector (it has one witness). Implementable from
  the layout, but unverified.
- **E3 — numeric comparison tolerance.** The contract gives expected
  ranks as JSON numbers (`51.5`, `100.0`) but never states whether a
  runtime must match them exactly or within an epsilon. The Elixir
  self-check uses `assert_in_delta 1e-9`; the Python harness uses `==`.
  All current expected values are exactly representable, so this hasn't
  bitten — but the comparison contract is unspecified.

## Would a third implementer likely diverge?

- **On the 31 pinned vectors:** unlikely. The contract now over-
  determines them; the residual notation traps (U2/U3) are fixed.
- **On untested inputs:** **likely**, specifically via **R1**
  (decimal vs. binary64 `delta_milli`) and **R2** (Ed25519 verify
  variant). These are the honest frontier — the vectors do not pin
  them, so "passes the harness" would not guarantee interop on real
  traffic.
- **Recommended next contract hardening (not done here — would need
  vectors, hence a version bump):** add `canonical_attestations`
  entries at half-ulp `delta` boundaries to pin R1, and a negative
  `wire`/verify vector to pin R2/E2. Until then, state R1/R2 as
  *explicitly out of conformance scope* so implementers do not assume
  coverage they do not have.

---

## Spec stability pass (findings + minimal edits applied)

Searched the live contract chain (`fu-protocol.html`,
`fu/conformance/README.md`, `vectors.json`, `PROTOCOL_CHANGELOG.md`,
`redefinition/*`) for duplicated/conflicting normative rules, prose that
can drift from vectors, unstated ordering, hidden defaults. Minimal
clarifying edits only — **no behaviour, no `vectors.json`, no version
change.**

| Finding | Action |
|---|---|
| U2: `[0..16]`/`[0..4]` vs "first N" — inclusive-range drift trap | **Edited** to "first N … (indices 0–N-1)" in `fu-protocol.html` P3.3 & §9.5 and the README constants table |
| U3: median "sorted views" direction unstated | **Edited** to "ascending-sorted" in README + `fu-protocol.html` P8.3 |
| Drift: header callout said "128-test reference", footer "156-test" — both rot | **Edited** both to "the test-locked Elixir reference" (no magic number) |
| Duplication: `canonical`, clamp, witnessed-rank stated in both README and `fu-protocol.html` | **Left as-is** (consistent; precedence rule `prose < vectors.json < reference` already governs drift). Not deduped — aggressive rewrite avoided per scope. |
| Conflicting MUST/SHOULD | none found |

Residual prose-drift risk is now bounded by: (a) the precedence rule,
(b) the dual-runtime CI gate, (c) the unambiguous length/order wording.
