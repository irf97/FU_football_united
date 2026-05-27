# Boundaries — where each layer starts and stops

Three layers share this repo. This file draws the lines so no claim
leaks across them. If a sentence anywhere in the repo blurs these, the
sentence is wrong, not these boundaries.

---

## Layer 1 — The football app

**In scope (exists, tested, runnable):**

- Phoenix LiveView product: Browse / Queue → Lobby → Match → Post-match.
- Soft-join → hard-lock commitment model + bail penalties.
- Deterministic append-only rank ledger; idempotent finalize; disputes
  as amendments; decay; rated 8v8 + 7v7.
- Sub-positions are display-only — a test-locked invariant keeps them
  out of matchmaking.
- Phone-OTP auth (rate-limited, attempt-capped), captain-guarded
  tactics, friends/groups, queue chat.

**Out of scope (acknowledged blockers, not pretended-solved):**

- Real SMS gateway (OTP is printed to the server log by design).
- Admin credential out of source (hardcoded demo gate).
- These are launch blockers, listed as such in the root README.

**Boundary:** the app is a *product*. It does not depend on Layer 2 or
3 to run. The mesh modules are a research namespace beside it, not
underneath it.

---

## Layer 2 — The protocol kernel

**In scope (exists; a self-consistent reference, byte-exact):**

- Ed25519 identity (RFC 8032; deterministic seed keys).
- Canonical encoding (`{match}|{player}|{round(delta*1000)}` — language
  stable, integer delta, no float formatting).
- Signed ingest (verify-then-fold/drop).
- Witnessed rank (median of witnesses, self excluded) and recoverable
  rank (provisional-witness bootstrap).
- Wire framing codec (length-delimited, digest-checked, MTU chunking,
  adversarially robust decode).
- A versioned conformance contract (`vectors.json` v6) generated from
  the reference, with an independent re-derivation self-check and a CI
  gate.

**Explicitly NOT claimed:**

- Not a proven interop standard. No independent implementation exists
  (see `../SECOND_IMPLEMENTATION.md`).
- Not a general distributed-systems framework. It models *one*
  primitive — witnessed-rank propagation under proximity trust — not
  arbitrary protocols.
- Validated *in simulation* (to 10k; friendless-bootstrap mitigated to
  ~90%, not zero). Simulation is not field deployment.

**Boundary:** the kernel's authority comes from its property/relationship
tests and from Ed25519 being a public standard — **not** from the
snapshots matching themselves. The `/lab` LiveView is a *window* onto
the kernel, not part of it; it is disposable.

---

## Layer 3 — The runtime / ecosystem

**Entirely aspirational. Zero of this exists in the repo:**

- The Rust node runtime (named target only — no Rust in the tree).
- Real BLE/NFC transport / radios.
- The phone client and the solid-node OS layers (the 25-layer
  `../archive/fu-node.html` architecture is a *design document*, not an
  implementation).
- Any third-party implementation, adoption, or interop.

**Boundary:** nothing here may be described in the present tense.
"Targets," "design," "intended" — never "has," "provides," "is."

---

## The one-line test for any claim in this repo

> Name the layer (1/2/3) and the column
> (already-real / potential / aspirational). If it doesn't fit cleanly,
> the claim is overstated — rewrite it until it does.
