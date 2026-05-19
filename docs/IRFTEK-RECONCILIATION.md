> **Point-in-time document.** Current status & full project history: see README.md and CHANGELOG.md at the repo root. _(2026-05-19 — Football United app + P2P mesh protocol v5; 156 tests, 0 failures.)_

# IrfTek paper ↔ shipped reality — reconciliation
_Generated 2026-05-16 · same evidence discipline as `AUDIT.md`
(IMPLEMENTED / PARTIAL / ASPIRATIONAL / UNVERIFIABLE, file:line)._

## Headline

The paper describes a 14-section local-first, proximity-governed,
AI-readable, blockchain-anchored, hardware-module distributed substrate.
**Exactly one section (§12, UI) is IMPLEMENTED.** Two more (§7 data
lifecycle, §9 football) have a *narrow* real analog that the paper
overstates. The other ~11 sections are **ASPIRATIONAL** — there is no
code for them anywhere in this repository.

Evidence sweep (`grep -rinw` over `fu/lib fu/config mix.exs`, false
substrings removed): **0** files contain BLE/Bluetooth, NFC, Zigbee, MQTT,
NATS, libp2p, CRDT, gossip, blockchain, "Pi Network", tinygrad, WASM, LLM,
persona, proximity, beacon, wristband, Jetson, SQLite, YAML, JSONL, Tool
Twin, Machine Twin, IMM. (`BLE`→substring of "ta**ble**/availa**ble**";
`ledger`→the rank audit-trail prose in `ranking.ex`; `IMM`→"co**mm**it
i**mm**ediately" in `queues.ex:213`.) The shipped system is a **single
centralized Phoenix LiveView monolith on one Postgres** (`STACK.md`).

So: Football United is real and shipped, but it is the *opposite* of the
paper's thesis — it is cloud/server-authoritative, not local-first; it has
no proximity, no devices, no AI runtime, no ledger. The paper should
present it as **the one shipped artifact and a deliberately centralized
MVP**, not as a deployment of the IrfTek substrate.

## Section-by-section

| § | Topic | Status | Evidence |
|---|---|---|---|
| Abstract,1,2 | Local-first / proximity-governed / semantic principles | ASPIRATIONAL | Position statement. No `C=P+T+E+A+R`, no proximity, no local-authority code. Reality: server is sole authority (`fu_web/endpoint.ex`, LiveView). |
| 3.1 | Layered runtime (BLE→…→LLM→UI) | ASPIRATIONAL | None of the layers exist except UI. Transport = WebSocket/HTTP (`bandit`), in-node `Phoenix.PubSub` (`application.ex:14`). State = Ecto/Postgres rows, not JSONL/YAML/CRDT/SQLite. No cognitive layer. |
| 3.2 | IMM-S/M/X module families | ASPIRATIONAL | No module/hardware/twin code. "IMM" appears nowhere in source. |
| 4 | Wristbands / field beacons / authority nodes | ASPIRATIONAL | Zero hardware/firmware. A "field" is a Postgres row (`fu/lib/fu/fields/field.ex`), not a beacon. |
| 5 | BLE / NFC / Wi-Fi / LAN comms | ASPIRATIONAL | No Bluetooth/NFC/mesh. Only HTTP+WS to one server. |
| 6 | AI-readable runtime (YAML/JSONL, AI inspects state) | ASPIRATIONAL | State is `Ecto.Schema` in Postgres; no semantic event log, no AI inspection surface. The repo *is* AI-legible (Markdown specs, `AUDIT.md`) but that is docs, not a runtime property. |
| 7 | Event compounding / time decay / selective persistence | **PARTIAL** | Real, narrow analog: append-only rank ledger (`fu/lib/fu/ranking/rank_event.ex`, `ranking.ex`) and time-decay worker (`fu/lib/fu/ranking/decay_worker.ex` → `Ranking.apply_decay/0`). But "BLE ping → presence_session" is ASPIRATIONAL — no telemetry exists. |
| 8 | Persona architecture / identity vaults | ASPIRATIONAL | Single identity: one phone-OTP `Player` row, one profile, one avatar (`fu/lib/fu/accounts/player.ex`). No personas, no vault. |
| 9 | Football United coordination model | **PARTIAL (overstated)** | Queue→lobby→teams is real (`Fu.Queues`, `Fu.Lobby`, `Fu.Balance`). But the paper's flow — "field beacon validates availability → BLE check-in → match starts" — is **not implemented**: no beacon, no BLE, and per `AUDIT.md` integration break #1 there is **no in-app way to start/complete a match at all** (seed-only). "Phones = ephemeral mirrors, field = local authority" is inverted: the **server** is authoritative (LiveView), the field is a DB row. |
| 10 | Global blockchain / ledger / Pi Network | ASPIRATIONAL | No blockchain, no chain client, no Pi integration. "ledger" in code = the rank audit trail, a Postgres table — not a distributed ledger. |
| 11 | Domains as semantic namespaces | ASPIRATIONAL | One hardcoded domain (football). No namespace/multi-domain mechanism. |
| 12 | UI architecture | **IMPLEMENTED** | This section matches: Phoenix LiveView, server-maintained truth, server-rendered HEEx, minimal JS (one hook, `fu/assets/js/app.js` `ChatScroll`), Tailwind, no SPA. See `STACK.md`, `fu/lib/fu_web/components/layouts.ex`, `POLISH.md`. |
| 13 | Open problems (BLE noise, mesh trust, …) | ASPIRATIONAL | All presuppose unbuilt systems. The repo's *actual* #1 open problem is `AUDIT.md` break #1 (match-lifecycle has no entry point) — not in the paper. |
| 14 | Conclusion | ASPIRATIONAL | Restates the vision. |
| `fileciteturn0file0` | "IrfTek canonical architecture specification / IMM runtime direction" | UNVERIFIABLE | No such file in this repo (only `fu-mvp-spec.md`, `fu-backend-design.html`, `fu-frontend-implementation-plan.md`). The citation cannot be checked against anything here. |

## Recommendation

If this is published, label it a **position/vision paper** and add one
honest sentence up front: *"§12 is implemented; §7 and §9 have partial
analogs in the Football United MVP; §§1–6, 8, 10, 11, 13 are architectural
direction with no implementation as of this writing."* Conflating the two
is precisely the WIRED-looking-but-STUB failure mode the audit was
commissioned to prevent — applied to prose instead of code.

The paper and this reconciliation live together in `docs/` so the claim
and its evidence are never separated.
