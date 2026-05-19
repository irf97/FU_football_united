# FU Mesh Protocol — Changelog &amp; Compatibility

Authoritative lineage of `spec: "fu-mesh-conformance"`. A runtime targets
exactly one `version`; the harness (step 0) **refuses any mismatch**. There
is no silent cross-version interop — bumps are breaking unless explicitly
marked additive.

## Two version namespaces (do not conflate)

| Namespace | Where | Meaning |
|---|---|---|
| **conformance `version`** | `vectors.json` `.version` | the *contract* revision a runtime targets (1→5) |
| **wire frame version** | the `0x02` byte inside a frame | the *on-wire frame* revision; currently fixed at `2` |

They move independently. Conformance v3 and v4 both carry frame version
`0x02`. A frame-version bump (e.g. a new payload field) would be its own
breaking event with its own migration note here.

---

## v5 — Adversarial security boundary *(current)*

- **Added** `adversarial`: the collusion boundary &amp; transit integrity,
  contract-locked. Pins `collusion_minority_2of5` (51.5 — unmoved),
  `collusion_majority_3of5` (100.0 — moved), `byzantine_relay_delivered`
  (false).
- **Invariant locked (honest security model):** a *minority* of colluding
  witnesses cannot move the witnessed median; a *majority* can — this is
  the stated limit, not a bug. A byzantine relay that mangles in transit
  produces an unverifiable Object → dropped → it can withhold
  (availability) but never inject (integrity).
- **Compatibility:** additive over v4 (new section only). Still a version
  bump — a v4-only runtime is not v5.

## v4 — Pipeline capstone

- **Added** `pipeline`: end-to-end convergence using **only framed bytes**
  (sign → canonical → encode → MTU chunk → stream reassemble → decode →
  ingest_signed → relay → witnessed rank). Pins `final_witnessed_rank`
  (51.5) and `forged_verified` (false).
- **Invariant locked:** the full stack composes; a delta tampered *after*
  signing re-frames with a valid digest but fails Ed25519 → not state.
- **Compatibility:** additive over v3 (new section only; no existing
  section changed). Still a version bump — a v3-only runtime is not v4.

## v3 — Wire framing

- **Added** `wire`: byte-exact frame
  (`"FU"` · `0x02` · type · u32 len ≤ 4096 · payload · SHA-256[0..4]
  digest). Pins `frame_hex`, `frame_bytes`, MTU `chunk_count`.
- **Invariant locked:** codec ≠ crypto — digest catches transit bit-rot;
  authorship is Ed25519 only. Decode is adversarially total
  (garbage/prefix never crash).
- **Compatibility:** additive over v2.

## v2 — Language-stable canonical encoding *(breaking vs v1)*

- **Changed** `canonical(att)` from `"{match}|{player}|{delta}"` (float
  string) to `"{match}|{player}|{delta_milli}"` where
  `delta_milli = round(delta*1000)`, round-half-away-from-zero.
- **Why:** float `to_string` diverges across languages → signatures would
  not match between an Elixir reference and a Rust runtime. The integer
  form removes all float formatting from the wire; arithmetic noise
  (`0.1+0.2`) collapses to `300`.
- **Added** the `|`-forbidden-in-`player` constraint.
- **Compatibility:** **BREAKING.** Every signature in v1 is invalid under
  v2 (different signed bytes). No migration path; v1 is dead.

## v1 — Initial frozen reference

- `identity` (Ed25519, seed-deterministic, RFC 8032; address =
  `lower_hex(SHA-256(pub))[0..16]`), `canonical_attestations`,
  `mesh.signed_ingest` (verify-or-drop), `bootstrap` (provisional
  witnesses for the friendless).
- Established: rank band `[30,100]`, start `50`, witnessed = median,
  self-excluded; Expiry constants (window 8, stranger-TTL 4,
  acq-threshold 3, acq-decay 6).

---

## Compatibility rules

1. A conformant runtime **declares its target `version`** and the harness
   aborts on mismatch (no "best effort").
2. A bump is **breaking** unless this changelog marks it *additive*. Even
   additive bumps are a new version — feature detection is by version, not
   by probing.
3. Two runtimes interoperate **iff they share both** the conformance
   `version` and the wire frame version.
4. The reference (`Fu.Mesh.*`, the test suite) is the oracle. Prose loses
   to `vectors.json`; `vectors.json` loses to the reference code.
5. Regenerate after any normative change:
   `mix run --no-start bench/conformance_vectors.exs`, bump `version`
   here, add a section above. The self-checking harness
   (`test/fu/conformance_test.exs`) must stay green.
