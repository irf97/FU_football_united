# Football United — Redefinition Layer

This folder reframes what the repository currently is without exaggerating what has not been built.

Football United began as an amateur-football matchmaking app. That app still exists: it is a Phoenix LiveView product with queues, lobbies, matches, voting, ranking, chat, friends, groups, admin tooling, and tests.

During the build, a second asset emerged: a deterministic mesh-protocol reference kernel. That kernel is not yet a production P2P network. It is a runnable reference model, conformance-vector generator, simulator, and test harness for a future phone/node runtime.

## The calibrated identity

Football United is currently:

1. **A built football app** — usable as the original product direction.
2. **A protocol reference kernel** — Elixir modules that define deterministic behavior for signed attestations, witness-based rank recovery, wire framing, adversarial boundaries, and conformance vectors.
3. **A reference-first methodology artifact** — an example of the workflow: formalize behavior, freeze semantics, verify independent implementations.

Football United is not yet:

- a running serverless phone network;
- a Rust runtime;
- a BLE/NFC transport;
- a standards ecosystem;
- infrastructure with external adoption.

Those may become future paths, but they are not present facts.

## Why this folder exists

The repo previously risked sounding like it already possessed the whole network stack. This folder makes the boundary explicit:

- what exists now;
- what is only specified;
- what must be independently implemented next;
- what prompts should be used by agents so they do not overclaim.

## The current value hierarchy

### Already real

- Phoenix football app.
- Elixir reference kernel.
- Property tests and behavioral invariants.
- Conformance vectors generated from the reference.
- Mesh Lab demo/simulator over the kernel.
- Documentation that records the pivot.

### Potential, but gated

- Verification infrastructure.
- Simulation platform.
- Rust/phone runtime.
- Protocol ecosystem.
- Standards authority.

### Critical next proof

A second implementation must reproduce `fu/conformance/vectors.json` from `fu-protocol.html` and `fu/conformance/README.md` without reading the Elixir source.

Until that exists, the mesh layer is best described as a **self-consistent reference kernel**, not a proven interop standard.

## Folder map

| Path | Purpose |
|---|---|
| `LEGITIMACY_LEDGER.md` | Honest accounting of what exists, what is aspirational, and what would change the status. |
| `SECOND_IMPLEMENTATION.md` | Guidance for implementing the conformance core in another language. |
| `spec/BOUNDARIES.md` | Scope boundaries: football app vs mesh reference vs future runtime. |
| `prompts/` | Copy-paste prompts for project agents, auditors, and second-implementation builders. |
