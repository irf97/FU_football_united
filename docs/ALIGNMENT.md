# Aligning the built system with the IrfTek paper

_What "align the built with the paper" can honestly mean in a centralized
Phoenix/Postgres codebase — without manufacturing the stubs the audit
existed to prevent._

## The constraint

The paper is a local-first / proximity / device / blockchain / AI-runtime
substrate. ~11 of 14 sections need hardware (wristbands, beacons, BLE/NFC),
external networks (a chain, Pi), or are research programmes (proximity
consensus, distributed cognition, CRDT mesh, local LLMs). **None of those
can be "aligned" inside this repo without writing fiction.** Doing so would
reproduce exactly the WIRED-looking-but-STUB failure `AUDIT.md` was
commissioned to catch. So alignment here = (a) state what is already
aligned, (b) ship the *one* bounded, real slice that genuinely moves the
runtime toward the paper, (c) name what is out of reach and why.

## (a) Already aligned (no work — just acknowledged)

| Paper | In the build |
|---|---|
| §12 UI: server-truth, semantic, minimal-JS LiveView | IMPLEMENTED — `STACK.md`, `POLISH.md` |
| §7 time decay / selective persistence | `Fu.Ranking.DecayWorker` + append-only `rank_events` ledger (`ranking.ex`) |
| §2.4 module exposes state/health | `/admin` + `Fu.Admin.overview/0` (players, live status) |

## (b) Shipped this commit — the one real alignment slice

**§6 "AI-readable runtime" + §3 EVENT LAYER ("JSONL semantic events,
append-only logs") + §6.3 semantic-event format.**

This is the single paper concept that is genuinely implementable in a
centralized monolith and genuinely useful: the runtime already
*broadcasts* domain events over `Phoenix.PubSub` (`Fu.Queues` join/leave/
state-change) but discards them. We now also **persist them as an
append-only semantic event log** in exactly the paper's §6.3 shape:

```json
{"t":"2026-05-16T18:01:00Z","type":"player.join_queue","domain":"football","player_id":102,"queue_id":49,"position":"GK"}
```

- `Fu.Events` context + `semantic_events` table (append-only, jsonb
  payload, `type`, `domain`, `ts`).
- `Fu.Events.to_jsonl/1` emits the paper's literal JSONL line format, so
  an AI/agent can read the runtime's history without touching Ecto.
- Recorded at the existing broadcast sites in `Fu.Queues`:
  `player.join_queue`, `player.leave_queue`, `queue.confirmed` /
  `queue.cancelled` / `queue.extended`.
- Side-effect only (failure never breaks the domain action); covered by
  a test.

This makes the runtime measurably *AI-readable* (paper §6) for real —
not a stub — while staying inside the centralized reality.

## (c) Out of reach in this codebase (research / hardware — NOT stubbed)

Honest non-goals; attempting them in code would be fiction:

- §3.1 BLE/NFC/Zigbee/MQTT/NATS/libp2p/CRDT/local-LLM/WASM layers,
  §4 hardware (wristbands/beacons/Pi/Jetson), §5 comms stack — require
  physical devices and firmware; nothing to align in software here.
- §2.2 proximity-governed consensus, §10 blockchain/Pi coordination,
  §3.2 IMM-S/M/X module families, §8 persona vaults, §11 multi-domain
  namespaces — distributed-systems / identity research programmes, each a
  project in its own right, not a refactor of this app.

The paper's §9 "field beacon validates → BLE check-in → match starts"
specifically cannot be aligned until (i) AUDIT break #1 is fixed (an
in-app match-completion trigger exists at all) and (ii) there is hardware.
Step (i) is the real, fundable next step; step (ii) is the research arc.

## Net

Alignment delivered: one truthful slice (semantic event log → AI-readable
runtime). Everything else is documented as direction with the same
honesty as `AUDIT.md`. The build now emits the paper's own §6.3 events;
it still is not, and is not pretended to be, the local-first substrate.
