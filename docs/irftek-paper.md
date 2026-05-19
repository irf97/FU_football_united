> **Point-in-time document.** Current status & full project history: see README.md and CHANGELOG.md at the repo root. _(2026-05-19 — Football United app + P2P mesh protocol v5; 156 tests, 0 failures.)_

# IrfTek — Local-First Semantic Runtime Infrastructure

_Paper as supplied by the author, verbatim, 2026-05-16. This is a vision /
position paper. For what is actually implemented in this repository, see
`docs/IRFTEK-RECONCILIATION.md` (evidence-graded, file:line)._

---

## A Research Paper on Proximity-Governed AI-Readable Distributed Systems

# Abstract

IrfTek proposes a local-first semantic runtime infrastructure for human,
device, and AI coordination. The system combines proximity-governed
networking, semantic machine-readable state, local authority nodes,
AI-readable runtimes, distributed machine modules, exploration-based
discovery, federated trust, and layered global coordination. Unlike
cloud-centric architectures, IrfTek prioritizes local interaction,
low-latency coordination, human relevance, modular runtime governance,
semantic interoperability, and AI-native cognition. Target domains:
education, hobbies, football coordination, service ecosystems, trade,
local culture, persona-based identity systems, distributed machine
intelligence.

# 1. Introduction

Modern internet infrastructure centralizes identity, storage, computation,
coordination, visibility, and monetization — producing surveillance
concentration, platform dependency, cloud latency, information overload,
global synchronization inefficiency, opaque application state, and
AI-hostile runtime architectures. IrfTek introduces: local-first runtime +
semantic machine cognition + proximity-governed interaction + distributed
authority. Humans, devices, places, fields, tools, AI agents, and personas
are treated as semantic machine modules on a shared runtime substrate.

# 2. Foundational Principles

2.1 Local-First Infrastructure — local runtime handles queues, lobbies,
field reservations, discovery, AI inference, semantic state, interaction,
device coordination; global layer handles permanence, governance,
ownership, registries, resource coordination.

2.2 Proximity-Governed Fairness — physical proximity determines event
priority, visibility, reservation rights, discovery relevance, interaction
authority. C = P + T + E + A + R (proximity, trust, exploration, authority,
semantic relevance).

2.3 Exploration-Based Discovery — the network carries all semantic state;
the UI selectively reveals relevant portions by domain interest, proximity,
trust, mutual interaction, local authority, semantic relevance.

2.4 Semantic Runtime Architecture — every module exposes identity,
capabilities, permissions, state, memory, topology, runtime health,
semantic relationships. The runtime is AI-readable.

# 3. System Architecture

3.1 Layered Runtime Model — PHYSICAL (BLE/NFC/Wi-Fi/Zigbee/Sensors),
TRANSPORT (MQTT/NATS/libp2p/CRDT sync/Gossip), EVENT (JSONL semantic
events, append-only logs), STATE (SQLite/CRDT docs/YAML), MACHINE MEMORY
(snapshots/semantic compression/time decay/summaries), COGNITIVE (local
LLMs/Tinygrad/WASM/planning agents), UI (HTML/Phoenix LiveView/semantic
rendering).

3.2 Machine Module Families — IMM-S (lightweight edge: wristbands, field
beacons, sensors), IMM-M (local authority/runtime: Pi clusters,
orchestration servers), IMM-X (high-compute cognition: AI inference/GPU/
semantic planning). Aligns with Tool Twin / Machine Twin / runtime
governance / machine memory / AI placement per the IrfTek canonical
architecture specification.

# 4. Hardware Architecture

4.1 Wristbands — BLE identity, proximity broadcast, optional NFC, persona
selection (nRF52 / ESP32-C3). 4.2 Field Beacons — reservation authority,
queue sync, occupancy, gameplay authority (ESP32 / Pi Zero). 4.3 Local
Authority Nodes — runtime orchestration, local memory, event propagation,
AI inference, semantic sync (Pi 5 / mini PC / Jetson / IMM-X).

# 5. Communication Stack

BLE (discovery/identity/proximity/low-byte events), NFC (deliberate
interaction/claims/permissions/pairing), Wi-Fi/Hotspot (heavy local sync/
snapshots/media), LAN (authority-node sync/compute/state replication).

# 6. AI-Readable Runtime

6.1 Runtime structured for machine cognition — inspect/reason/summarize/
orchestrate/compress/simulate/govern without reverse-engineering opaque
apps. 6.2 Preferred formats: YAML/JSONL/SQLite/Markdown/typed schemas;
avoid hidden frontend state, opaque binary logic, giant SPA mutation trees.
6.3 Semantic event:
`{"t":"2026-05-16T18:01:00Z","type":"player.join_queue","player":"p102","field":"field_01","domain":"football"}`
6.4 Semantic state:
`field: {id: field_01, state: reserved, authority: local, queue_count: 10}`

# 7. Data Management

7.1 Event Compounding — raw telemetry not permanently stored; BLE ping
stream → semantic presence session (`presence_session: {player: p102,
duration: 52m, confidence: 0.94}`). 7.2 Time Decay — live state seconds,
lobbies hours, sessions weeks, summaries permanent. 7.3 Selective
Persistence — persist summaries/ratings/outcomes/reputation/snapshots;
discard telemetry/raw pings/noise.

# 8. Persona Architecture

Users maintain multiple personas, local identity vaults, wristband-linked
identities, context-specific participation (football persona, anonymous
explorer, educator, trader, organizer). No mandatory global identity.

# 9. Football United Coordination Model

Canonical deployment. Runtime flow: player joins queue → lobby builds →
field beacon validates availability → nearby users commit → field
RESERVED → BLE check-in → match starts. Authority: field node = local
authority / reservation source / gameplay coordinator / semantic anchor;
phones = ephemeral mirrors / UI endpoints / discovery relays /
participation clients.

# 10. Global Coordination Layer

10.1 The blockchain/global ledger is not the runtime; it is the
coordination archive / governance substrate / ownership registry / public
standards layer. 10.2 Suitable: module registries, protocol standards,
public governance, reputation anchors, AI model lineage, resource
ownership, open economic coordination. Unsuitable: live BLE telemetry,
field occupancy streams, UI sync, real-time queues. 10.3 Pi Network
Influence — demonstrated mobile-first distributed participation,
trust-based growth, lightweight node coordination, social consensus
bootstrapping; IrfTek extends into semantic runtime coordination + local
machine governance + AI-readable distributed cognition.

# 11. Domains

education / hobbies / football / trade / service coordination / culture /
local events / machine ecosystems / persona-based interaction — each a
semantic runtime namespace with local rules / AI / discovery / governance.

# 12. UI Architecture

Low-bandwidth, semantic rendering, server-maintained truth state, local
caching, lightweight updates, minimal JavaScript. Phoenix LiveView /
HTML / semantic templates. Avoid excessive frontend state, giant SPAs,
unnecessary animation.

# 13. Open Problems

Mobile OS background restrictions, BLE proximity noise, distributed trust
propagation, hostile node resistance, large-scale BLE congestion, battery
optimization, semantic spam filtering, conflict resolution at scale.

# 14. Conclusion

IrfTek = local-first semantic civilization infrastructure: proximity-
governed coordination, AI-readable runtimes, semantic machine modules,
distributed cognition, local authority, layered global governance, modular
human-machine interaction. Runtime authority local, visibility selective,
synchronization semantic, identity persona-native, AI cognition built into
the runtime. A distributed operating substrate for humans, machines,
places, AI agents, semantic coordination — aligned with the IrfTek Machine
Module architecture specification and IMM runtime direction.
