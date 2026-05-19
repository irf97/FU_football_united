# Strategic Runtime Architecture — IrfTek / Football United

> **Audience:** architects and investors. Systems-level, not a tutorial,
> not marketing.
> **Thesis:** Football United is **the first product domain** of a
> broader **IrfTek local-first semantic runtime** — it is the runtime's
> **first projection** and its **validation surface**: a real, shippable
> product *and* the proving ground for a persona-native, proximity-trust
> substrate that any coordination domain (sport, community, logistics,
> governance) can run on. FU is not a throwaway demo and not the whole
> system; it is the first, real instance of both.

This document is the bridge between what exists today and the build that
follows. It does not change protocol behaviour, vectors, or versions.

---

## Maturity legend (used on every claim)

| Tag | Meaning |
|---|---|
| ✅ **Implemented** | Code in this repo, tested, runnable. |
| 📐 **Specified** | Frozen as a contract / vector / written design. No running implementation. |
| 🛠 **Planned** | Strategic intent, designed here at architecture level. Not yet contract-grade or built. |

**What is true today, stated plainly:** there is a runnable Phoenix
football app ✅, a deterministic Elixir mesh **reference kernel** ✅, a
byte-exact conformance contract at **v6** 📐, and one independent
(context-contaminated, audit-grade) Python reproduction ✅. There is **no
Rust runtime, no radio, no peer network, no deployment, and no external
adoption.** The clean-room legitimacy threshold is **not crossed**. Every
forward statement below carries a maturity tag so this honesty survives
re-reading.

---

## 1. Strategic architecture overview

The system is four concentric layers. Confusing them is the primary way
to misjudge the project.

```
        ┌─────────────────────────────────────────────┐
        │  DOMAIN LAYER   Football United (and next    │  ✅ FU built
        │                 domains) — projection + UX    │
        ├─────────────────────────────────────────────┤
        │  RUNTIME LAYER  IrfTek local semantic runtime │  🛠 Rust target
        │                 (authority, sync, governance) │  📐 contract v6
        ├─────────────────────────────────────────────┤
        │  PROTOCOL LAYER IrfTek kernel: 6 primitives,  │  📐 frozen
        │                 conformance vectors (law)     │  ✅ Elixir ref
        ├─────────────────────────────────────────────┤
        │  TRANSPORT LAYER proximity radios + peer sync │  🛠 unbuilt
        └─────────────────────────────────────────────┘
```

The **protocol layer** is the centre of gravity: a small, frozen,
machine-checkable semantic contract that stays invariant while
implementations evolve around it. Football United is the runtime's
**first product domain and first projection** — the real surface on
which the substrate is validated. The *Phoenix implementation* hosting
that projection today is not the final runtime; it is re-pointed at the
runtime in Phases 1–6. The product (FU) is durable and first-class; the
current host is the part that moves.

The strategic claim is narrow and defensible: **we have de-risked the
semantic core by freezing it and reproducing it; we have validated it
against a real domain; the remaining work is a runtime and transport that
must *conform* to the frozen core rather than reinvent it.**

---

## 2. Why Football United is the first domain

Amateur sport is an unusually good forcing function for a trust runtime:

- **Real identity friction without high stakes.** People misreport
  scores, smurf, no-show, and collude socially — but a wrong rank is
  recoverable, so the domain can be iterated safely.
- **Inherent proximity.** A match *is* a physical co-presence event —
  the exact signal the substrate's trust model is built on. The domain
  generates proximity proofs naturally; we don't have to synthesize them.
- **Group-witnessed truth maps directly.** "Who actually played, and how
  it went" is a witnessed-median problem, which is the kernel's core
  primitive (§7).
- **Bounded blast radius.** A failure is a bad pickup game, not lost
  funds — ideal for validating governance and Sybil handling in the wild.

FU is therefore the **domain validation surface** (§5). The substrate's
generality is a *hypothesis*; FU is the first experiment. Multi-domain
generalization (§9, Phase 8) is explicitly deferred until the substrate
survives this one domain.

---

## 3. The IrfTek kernel — six primitives

The entire semantic contract reduces to six primitives. This is the
durable intellectual asset; it is 📐 **specified and frozen** (conformance
v6) and ✅ **implemented as an Elixir reference** (`Fu.Mesh.*`).

| Primitive | Meaning | Repo realisation | Maturity |
|---|---|---|---|
| **Object** | An immutable, content-addressed, signed claim. | Signed attestation; canonical encoding `"{match}\|{player}\|{delta_milli}"`. | ✅/📐 |
| **Authority** | Who may assert what; verification gate. | Ed25519 author key, `verified?` verify-or-drop. | ✅/📐 |
| **Propagation** | How objects move without a server. | Subject-directed relay + closeness filter. | ✅ ref / 🛠 in field |
| **Projection** | Local, non-authoritative derived view. | `rank` fold (clamp 50→[30,100]); the Phoenix UI. | ✅ |
| **Anchor** | What makes a value trustworthy. | Witnessed median (self-excluded) + signature + proximity. | ✅ math / 🛠 proximity |
| **Expiry** | Bounded by construction; nothing unbounded. | TTL eviction, acquaintance lapse, compaction (W=8). | ✅/📐 |

The kernel's invariants — *unverifiable is not state*; *truth is the
witnesses' median, never self*; *nothing is retained unbounded* — are the
contract a runtime must satisfy, not advice it may follow.

---

## 4. Rust runtime — role and decomposition (🛠 a real target now)

The Rust runtime is the **intended production embodiment** of the runtime
layer. It is **not built**. Its specification already exists as the
conformance vectors: the runtime is correct iff it reproduces them
byte/value-exact. This is the project's central leverage — the runtime
has a frozen acceptance test before a line of it is written.

| Runtime responsibility | What it does | Conformance anchor | Maturity |
|---|---|---|---|
| **Local authority engine** | Ed25519 keypairs, verify-or-drop ingest. | `identity`, `mesh.signed_ingest` vectors. | 🛠 (📐 spec'd) |
| **Event/state processor** | Append-only objects → derived projections; idempotent fold; clamp/decay. | rank fold (§10), `pipeline`. | 🛠 (📐 spec'd) |
| **WASM execution boundary** | Domain logic (FU rules, future domains) runs as sandboxed WASM over the kernel — domains cannot break invariants. | kernel invariants as host enforcement. | 🛠 (design only) |
| **Peer sync engine** | Subject-directed relay, reconcile, compaction; offline-first. | `wire`, `pipeline`, propagation rules. | 🛠 (📐 partial) |
| **Device/proximity bridge** | BLE/NFC co-presence → proximity proofs feeding the Anchor. | Anchor primitive; R-frontier. | 🛠 (unspecified) |
| **Trust/governance evaluator** | Witnessed median, provisional witnesses, rate limits, decay, dispute amendments. | `bootstrap`, `adversarial` vectors. | 🛠 (📐 spec'd) |

The WASM boundary is the generalization mechanism: **domains are
guests; the kernel is the host.** FU's rules become a WASM module; a
second domain is another module; neither can violate Object/Authority/
Expiry because the host enforces them.

---

## 5. Phoenix app — role and limits

The Phoenix/LiveView app is ✅ **implemented and runnable** — the first
shipping form of the Football United product. The distinction this
section draws is deliberately narrow: the *Phoenix implementation
substrate* is not the final runtime; the **product it delivers is
first-class and durable**.

- **Current product & projection ✅** — `Browse/Queue → Lobby → Match →
  Post-match`, lock/penalty lifecycle, append-only rank ledger, tactics,
  friends/groups, fail-closed admin, release-grade SMS *boundary*.
- **First projection & validation surface ✅** — it is simultaneously a
  real, shippable product *and* the proving ground showing the kernel's
  semantics survive a real domain with real users and real misbehaviour.
  Both roles are durable; what is impermanent is the implementation
  substrate below, not FU's product value.
- **Reference oracle host ✅** — it hosts `Fu.Mesh.*`, the conformance
  generator, and the Mesh Lab simulator.
- **Host, not runtime 🛠** — the *current implementation* is
  server-centric, Postgres-backed, and phone-identity coupled. Those
  three substrate choices are what the runtime layer removes; the
  product, its domain logic, and its UX carry forward and are
  **re-pointed** at the runtime. What moves is the host — not Football
  United.

Strategic rule: **the app may not acquire capabilities that contradict
the runtime architecture** (e.g., deepening phone-as-identity). Where the
app and the substrate disagree, the substrate wins and the app is
refactored (§14, §15 Phase 1–2).

### Phoenix vs Rust runtime responsibilities

| Concern | Phoenix app (today) | Rust runtime (target) |
|---|---|---|
| Identity / authority | Phone-OTP, server-issued session ✅ | Ed25519 persona/device keys, local verify-or-drop 🛠 |
| Source of truth | Postgres rows, server-authoritative ✅ | Append-only signed objects, no server 🛠 |
| Trust evaluation | Computed server-side in `Fu.*` contexts ✅ | Local trust/governance evaluator 🛠 |
| Sync | None (single DB) | Peer subject-directed relay, offline-first 🛠 |
| Proximity | Implicit (match record) ✅ | BLE/NFC proximity bridge → Anchor 🛠 |
| Domain logic | Elixir contexts ✅ | WASM guest module over the kernel host 🛠 |
| Projection / UX | LiveView (the product) ✅ | Thin client over runtime projections 🛠 |
| Role | **Domain validation + reference oracle** | **Production embodiment of the kernel** |

Read this table as the **migration contract**: every 🛠 cell is a Phase
1–6 work item; no cell permits the app to entrench a ✅ that contradicts
its 🛠 counterpart.

---

## 6. Persona-native identity (🛠 planned refactor; honest current state)

**Today (✅):** identity is a phone number + OTP; `Player` is
phone-keyed. This is a domain-onboarding convenience, not the
architecture.

**Target (🛠):** identity is **persona-native and key-native**:

- **Personas are plural.** A human may hold many personas (e.g.,
  "Sunday-league striker", "coach", "referee"); the substrate never
  assumes one human = one identity. This is a feature, not an attack —
  Sybil resistance comes from *trust accrual* (§7), not from identity
  scarcity.
- **Phone removed from core identity.** Core identity is an **Ed25519
  signing key** (✅ the primitive already exists in `Fu.Mesh.Identity`).
  Phone, if present at all, is **optional recovery/contact metadata** at
  the projection layer — never the thing that authorizes a claim.
- **Device keys vs persona keys.** A device holds device keys; personas
  are signing keys that may be used across devices. Key separation,
  rotation, and revocation are 📐 named at the node layer and 🛠
  unspecified on the wire (an honest open item — see `fu-protocol.html`
  §11 O.4).

The migration is non-trivial and is **Phase 1** of the roadmap, not a
silent change. Until then, the honest statement is: *the substrate is
key-native; the shipped app is still phone-native; closing that gap is
the first build.*

---

## 7. Trust model

Trust is **earned locally and witnessed socially**, never asserted.
Mathematical core is ✅ implemented and 📐 frozen; physical inputs are 🛠.

| Trust signal | Mechanism | Maturity | Sybil/abuse role |
|---|---|---|---|
| **Witnessed rank** | Median of a subject's witnesses' views, self excluded; minority cannot move it, majority can (stated limit). | ✅/📐 | Defeats lone forgers; bounds collusion. |
| **Local reputation** | Per-node history; rank fold clamped `[30,100]`, decays toward neutral. | ✅ | Smurfs start neutral, must *earn* signal. |
| **Proximity proofs** | Physical co-presence (match = co-presence) feeds the Anchor. | 🛠 (radio unbuilt) | Makes fake history expensive (must be *somewhere*). |
| **Device reputation** | Device keys accrue/lose standing independent of persona. | 🛠 | Cheap new personas inherit no device trust. |
| **Acquaintance tier** | Repeated co-presence promotes peers (≥3 encounters, decays after 6 idle). | ✅/📐 | Provisional-witness bootstrap for the friendless. |
| **Rate limits** | OTP request caps today ✅; object/relay caps 🛠 at runtime. | ✅ partial | Throttles automated smurf creation. |
| **Decay** | Idle rank/bonds erode; nothing is permanently inflated. | ✅ | Abandoned smurfs self-expire. |
| **Moderation** | Admin suspension (bounded, §8) + disputes-as-amendments. | ✅ | Human backstop with explicit limits. |

**Sybil/smurf stance (explicit):** identity is *cheap by design*; trust
is *expensive by design*. A new persona is free and powerless. It gains
weight only through witnessed, proximity-anchored, decaying signal that a
colluding minority cannot fabricate. This is the honest security model —
**majority collusion can still move local truth**; that is a stated
limit, documented, not patched away by trusting fewer parties.

---

## 8. Governance model

Authority is **scoped and local**. There is no global admin god-mode.

### Object authority matrix

| Object | Who may assert | Who may amend | Who may not |
|---|---|---|---|
| Rank attestation | Any witnessing persona (signed) | Original author via amendment; disputes | Subject (self) — excluded from own median |
| Match result | Match participants / captains | Captains via dispute amendment | Non-participants |
| Field/venue fact | Field authority (venue node) | Field authority | Arbitrary peers |
| Group membership | Group authority (owner/admins) | Group authority | Outsiders |
| Suspension | Admin (bounded) | Admin (lift) | Self-lift |

- **Local authority** — a node is sovereign over its own derived view; it
  may *refuse* but never *forge* (verify-or-drop).
- **Field / group / match authority** — scoped roles assert only
  domain-local facts; they cannot rewrite global trust.
- **Dispute/amendment process** — truth is append-only; corrections are
  *new signed amendments*, not edits. ✅ implemented in the rank ledger.
- **Admin powers and limits** — admin can suspend (✅ bounded 14-day) and
  is itself **fail-closed and out of source** (✅ this build). Admin
  **cannot** mint rank, alter signed history, or impersonate a persona.

### Governance failure modes

| Failure | Vector | Mitigation | Residual |
|---|---|---|---|
| Bad admin | Over-suspension, favoritism | Bounded powers; append-only history; no rank minting | Social, not cryptographic |
| Governance capture | Group authority abuse | Authority is scoped to group; global trust unaffected | Group-local damage |
| Collusion ring | Majority of a witness set lies | Witnessed median holds vs *minority*; proximity cost | **Stated limit:** majority moves local truth |
| Dispute spam | Amendment flooding | Rate limits 🛠; amendments are signed & attributable | Needs runtime rate limiting |
| Authority forgery | Fake field/group authority | Ed25519 verify-or-drop | Key distribution is an open item |

---

## 9. Scaling model

| Stage | Topology | What must hold | Maturity |
|---|---|---|---|
| **Single field** | One venue, phone peers + optional venue node | Witnessed rank, bootstrap, expiry | ✅ simulated |
| **City cluster** | Many fields, overlapping personas, venue nodes as bridges | Subject-directed relay, ~flat storage, ~100% witness delivery @10k | ✅ simulated to 10k |
| **National network** | Inter-city, sparse bridges, partitions | Partition tolerance, heal-on-bridge, compaction | 📐 spec'd / 🛠 unproven in field |
| **Multi-domain** | Same kernel, new domain WASM modules | Kernel invariants enforced for *all* domains | 🛠 design only |

Scaling is **storage-bounded by construction** (Expiry/§3), not by
hope. The 10k-user result holds *only* because of the expiry invariants;
a runtime that "stores everything for now" is non-conformant by
construction.

---

## 10. Data model

- **Semantic objects** — signed, immutable, content-addressed claims
  (the only thing ever signed). ✅/📐
- **Append-only events** — objects accrue; nothing is mutated. ✅
- **Derived state** — projections (rank, status) computed from objects;
  never authoritative; recomputable. ✅
- **Summaries / checkpoints** — `(base_rank, base_seq)` fold so the
  newest `W=8` objects per subject are kept; older fold into base. ✅/📐
- **Anchors** — witnessed median + signature (+ proximity 🛠) — what
  promotes a derived value to *trusted*. ✅ math
- **Expiry/compaction** — stranger TTL 4, acquaintance threshold 3 /
  decay 6, window 8. **Nothing unbounded, ever.** ✅/📐

Honest open frontier (📐 documented in `CLEANROOM_READINESS.md`): **R1**
(`delta_milli` decimal-vs-binary64 domain) and **R2** (Ed25519 verify
variant) are *not* pinned by vectors yet — out of conformance scope, not
pretended-covered.

---

## 11. Runtime / network model

| Concern | Design | Maturity |
|---|---|---|
| Local node | Owns keys, store, projections; sovereign view | 🛠 (📐 reference exists) |
| Phone client | Persona host, proximity participant, projection UI | 🛠 (today: server app) |
| BLE/NFC proximity | Co-presence → proximity proof; NFC-feasible payloads | 🛠 unbuilt |
| Peer propagation | Subject-directed relay, closeness filter, no blind flood | ✅ ref / 🛠 field |
| Offline-first sync | Reconcile is convergent & idempotent (second pass moves 0 bytes) | 📐 spec'd |
| Conflict resolution | Append-only + idempotent fold + checkpoint adoption; no destructive merge | ✅/📐 |

The wire is frozen: a length-delimited, digest-checked frame; codec ≠
crypto. The runtime must reproduce the `wire`/`pipeline` vectors exactly.

---

## 12. Risk model

| Risk | Nature | Mitigation | Honest residual |
|---|---|---|---|
| Smurfing / Sybil | Cheap identities | Trust is earned, decaying, proximity-anchored; identity scarcity *not* relied on | New persona is harmless but rings can still grind trust slowly |
| Fake proximity | Spoofed co-presence | Physical radios + witness corroboration | **Unbuilt; the hardest open problem** |
| Collusion | Coordinated lying | Witnessed median resists minorities | Majority moves local truth — stated limit |
| Hostile nodes | Drop/mangle in transit | Verify-or-drop; mangling → unverifiable → dropped | Can *withhold* (availability), never *inject* |
| Bad admins | Abuse of moderation | Bounded powers, append-only, no minting | Social remediation only |
| Governance capture | Authority abuse | Scoped authority; global trust insulated | Local damage possible |
| Data bloat | Unbounded growth | Expiry/compaction invariants (non-optional) | Conformance-enforced |

The two risks with **no current technical answer** are fake proximity and
majority collusion. Both are stated, not hidden. The strategy is to make
them *expensive and observable*, not to claim they are solved.

---

## 13. Model strategy (the de-risking method)

This is the project's transferable methodology and its strongest asset:

1. **Deterministic protocol model** ✅ — `Fu.Mesh.*`, no hidden state.
2. **Conformance vectors as law** 📐 — generated from the reference;
   `prose < vectors.json < reference code`; normative change ⇒ version
   bump. Currently **v6**.
3. **Independent reproduction** ✅ (audit-grade) — Python, vendored
   RFC 8032, 31/31 @ v6; honestly *contaminated*, so a spec-sufficiency
   audit, not a clean-room crossing.
4. **Future Rust implementation** 🛠 — must pass the same harness; the
   contract exists before the code (the rare, valuable inversion).
5. **Simulation before deployment** ✅ — validated to 10k in simulation;
   **deployment is gated on conformance + simulation, never vibes.**

The legitimacy threshold (an *uncontaminated*, different-language,
different-author reproduction) is **not crossed**; `THIRD_IMPLEMENTATION_PLAN.md`
defines exactly what would cross it.

---

## 14. Product strategy

- **No premature MVP shortcut.** The football app ships only when it
  *reflects* the persona/trust/governance architecture — not before. A
  phone-native, server-trusting MVP would be negative work: it would
  encode the exact assumptions the substrate removes.
- **Release only when aligned with principles.** Pre-launch hardening is
  already principled-first (admin out of source/fail-closed ✅; SMS as a
  release-grade boundary, vendor deliberately deferred ✅).
- **The app must mirror the architecture.** Persona-plural identity,
  witnessed trust visible to users, scoped governance surfaced in the UI.
  The app is how non-architects *experience* the substrate; it must not
  lie about it.

Calibrated honesty is a product principle here, not just a doc style:
the repo's durable credibility is that it never claims more than it has.

---

## 15. Implementation roadmap

| Phase | Goal | Exit criterion | Maturity entering |
|---|---|---|---|
| **1 — Persona-first app refactor** | Identity = signing key; phone → optional recovery; personas plural | App auth no longer phone-keyed; key-native sessions; tests | 🛠 next |
| **2 — Trust/governance in Phoenix** | Witnessed trust + scoped authority + disputes surfaced in the product | Governance matrix (§8) enforced in app, tested | 🛠 |
| **3 — Rust runtime skeleton** | Project, key engine, object store, no domain logic | Builds; loads vectors; identity section green | 🛠 |
| **4 — Runtime conforms to vectors** | Rust passes the full v6 harness | `conformance` 7/7 in Rust CI alongside Elixir/Python | 🛠 (📐 contract ready) |
| **5 — Local node simulation** | Multi-node sim on the Rust runtime | Matches Elixir simulation results @ scale | 🛠 |
| **6 — Phone/device integration** | Personas on devices; BLE/NFC proximity bridge | Real proximity proof feeds the Anchor | 🛠 (hardest) |
| **7 — Field pilot** | One venue, real players, real proximity | Witnessed rank survives a real Sunday league | 🛠 |
| **8 — Multi-domain generalization** | Second domain as a WASM module | Two domains, one kernel, invariants intact | 🛠 (deferred by design) |

Phases 1–2 are **Phoenix work** (no runtime code) and are the immediate
next build. Phases 3–4 are where the Rust runtime becomes real, gated by
the existing frozen contract. Nothing past Phase 4 is scheduled or
promised — it is mapped, not committed.

---

## Consolidated: implemented / specified / planned

| Capability | Status |
|---|---|
| Football app (queues→match→rank, lock/penalty, tactics, friends, admin fail-closed, SMS boundary) | ✅ Implemented |
| Elixir mesh reference kernel (`Fu.Mesh.{V3,Identity,Wire}`) | ✅ Implemented |
| Conformance contract v6 (identity/canonical/ingest/bootstrap/wire/pipeline/adversarial) | 📐 Specified (frozen) |
| Independent reproduction (Python, audit-grade, contaminated) | ✅ Implemented (scoped honestly) |
| Simulation to 10k users | ✅ Implemented (simulated) |
| Persona-native key identity | 📐 primitive exists / 🛠 app refactor |
| Trust math (witnessed median, bootstrap, decay) | ✅/📐 |
| Proximity radios, fake-proximity defense | 🛠 Planned (unspecified) |
| Rust runtime (all roles in §4) | 🛠 Planned (contract ready) |
| Peer network in the field, conflict resolution at scale | 📐 spec'd / 🛠 unproven |
| Multi-domain WASM generalization | 🛠 Planned (design only) |
| Deployed production network / external adoption | ❌ Does not exist — not claimed |

## Release readiness checklist

| Item | State |
|---|---|
| App pre-launch: admin credential out of source, fail-closed | ✅ Done |
| App pre-launch: SMS release-grade boundary | ✅ Done (concrete provider+transport = localized remaining) |
| Persona-native identity in app (Phase 1) | 🛠 Not started — **gates principled release** |
| Trust/governance visible in product (Phase 2) | 🛠 Not started |
| Rust runtime conforms to v6 vectors (Phase 4) | 🛠 Not started (contract ready) |
| Real proximity proof (Phase 6) | 🛠 Not started — hardest open problem |
| Field pilot evidence (Phase 7) | 🛠 Not started |
| Clean-room legitimacy threshold crossed | ❌ Not crossed (see `THIRD_IMPLEMENTATION_PLAN.md`) |
| Honest-claims invariant (no overclaim anywhere) | ✅ Held — the non-negotiable |

---

## Related documents

- `redefinition/README.md` — three-layer honest framing.
- `redefinition/FU_END_TO_END.html` — narrative walkthrough.
- `redefinition/CLEANROOM_READINESS.md` — R1/R2 frontier, spec-stability.
- `redefinition/THIRD_IMPLEMENTATION_PLAN.md` — what crosses the threshold.
- `fu/conformance/{README,PROTOCOL_CHANGELOG}.md`, `vectors.json` — the law.
- `fu-protocol.html` — protocol spec v6. `fu-node.html` — node-layer design.
- `CLAUDE.md` — operating constraints + ethos for any builder.

> **The one rule that outranks this entire document:** never claim more
> than is built. Maturity tags are load-bearing. If a future edit removes
> them, the edit is wrong, not the tags.
