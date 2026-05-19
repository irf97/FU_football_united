# Football United

Two things live in this repo:

1. **The app** — an amateur-football matchmaking product (Elixir / Phoenix
   LiveView / PostgreSQL). Built, tested, runnable.
2. **The network** — a server-less, proximity-trust P2P protocol the project
   pivoted to. Validated in simulation to 10k users and frozen into a
   versioned, machine-checkable contract. **Not** a running product yet.

> **New here? Read [`redefinition/README.md`](redefinition/README.md) first** —
> what this repo actually is (app vs. reference kernel vs. aspirational
> runtime) and what is honestly claimed vs. not.
> Full chronological history of how this got here: **[CHANGELOG.md](CHANGELOG.md)**.
> Protocol version lineage: **[fu/conformance/PROTOCOL_CHANGELOG.md](fu/conformance/PROTOCOL_CHANGELOG.md)**.

**Status (2026-05-19):** 156 tests / 0 failures · 17/17 audited app features
WIRED · mesh protocol conformance **v6** · branch
`feat/audit-test-deploy-polish` · commits are **local-only** (not yet pushed).

---

## Run it

```sh
cd "fu" && source ../devenv.sh        # PATH persistence is sandbox-blocked
mix deps.get
mix ecto.create && mix ecto.migrate
mix run priv/repo/seeds.exs           # 3 fields, 16 players, queues, a
                                      # confirmed lobby + a finalized match
mix phx.server                        # http://localhost:4000
```

Sign in with any seeded phone, e.g. **`+31610000001`** — there is no SMS
gateway, the OTP is printed to the server log (a pre-launch blocker, by
design). Windows/dev gotchas (one mix process at a time, port-4000 zombies,
manual Tailwind rebuild): see CHANGELOG and the agent notes.

**Mesh simulators / protocol (no DB, deterministic):**

```sh
mix test                                        # full suite (156)
mix run --no-start bench/mesh_v3_scale.exs      # P2P model @ 100/1k/10k
mix run --no-start bench/conformance_vectors.exs  # regenerate vectors.json
```

…or **interactively in the browser: [`/lab`](http://localhost:4000/lab)** —
the Mesh Lab pokes the real `Fu.Mesh.*` modules (sign → wire-relay →
witnessed rank, collusion, byzantine relay, bootstrap) and runs the
conformance harness live.

---

## The app

`Browse / Queue → Lobby → Match → Post-match`, plus a soft-join → hard-lock
commitment model with bail penalties.

| Route | Surface |
|---|---|
| `/login` | Phone-OTP (rate-limited, attempt-capped) |
| `/` | Home — player card, quick position swap, friends/groups, ⚡ QUEUE |
| `/queue` | Quick-match auto-search — pops, **Accept = lock-in** |
| `/browse` | Scheduled queues — join soft, **Lock in**, bail (penalty) |
| `/queue/:id/chat` | Persistent per-queue chatroom |
| `/lobby/:id` | Rosters, sequenced captain claim, swaps, lock progress |
| `/match/:id` | Synced clock, captain controls, **tactics manager** |
| `/postmatch/:id` | Peer voting (24h) → append-only rank ledger |
| `/profile` | Identity, sub-positions, avatar picker, themes, history |
| `/admin` | Password-gated console |
| `/lab` | **Mesh Lab** — interactive P2P simulator + conformance |

Contexts: `Accounts · Positions · Queues · Matching · Balance · Lobby ·
Matches · Tactics · Voting · Ranking · Friends · Groups · QueueChat · Events
· Admin`, plus the research namespace `Fu.Mesh{,.V2,.V3,.Identity,.Wire}`.
Supervised workers: `Queues.Resolver`, `Ranking.DecayWorker`.

**Lock & penalty model:** join is soft (free to leave); locking in is a
commitment; the queue confirms the instant every slot is filled by *locked*
members (or the T-3h resolver force-locks stragglers). Bailing after lock-in
bans you: **1 day** if >24h before kickoff, **1 week** if within 24h, stacking.

**Ranking** is a deterministic append-only ledger (every delta carries its
breakdown), idempotent finalize, disputes-as-amendments, decay, rated 8v8 +
7v7. Sub-positions (CB/CDM/ST…) are display-only — a test-locked invariant
keeps them out of matchmaking.

---

## The network (research)

The P2P pivot: state lives on phones/nodes and propagates by physical
proximity; rank is **group-witnessed** (median of your witnesses, never
self — minority collusion can't move it, majority can: the stated limit).
Validated in `Fu.Mesh` v1→v3 (flat O(network) storage, ~100% witness
delivery at 10k, NFC-feasible payloads; friendless-bootstrap closed to
~90% via provisional witnesses).

Everything above the radio is now a **frozen, byte-exact, self-verifying
contract**: identity (Ed25519) · canonical encoding · signed ingest ·
witnessed/recoverable rank · wire framing · end-to-end pipeline ·
adversarial bounds — all in `fu/conformance/vectors.json` (spec v6), with a
self-checking harness (`fu/test/conformance_test.exs`) and a CI gate
(`fu/conformance/README.md`). The Rust runtime, radios (BLE/NFC), and
client are the genuine remaining build — outside this repo.

---

## Document map

| File | What it is |
|---|---|
| `redefinition/FU_END_TO_END.html` | **End-to-end narrative — read this first** (honest, single page) |
| `CLAUDE.md` | Cold-start brief for any AI agent: journey, constraints, honest status |
| `CHANGELOG.md` | **The chronological record of everything that happened** |
| `fu-network-pitch.html` | Why (engineer/marketing pitch) |
| `fu-dossier.html` | How it's built (architecture & state) |
| `fu-spec.html` | What it must do (normative MUST/SHOULD clauses) |
| `fu-features.html` | What ships (feature catalog + traceability) |
| `fu-dashboard.html` | Unified PM dashboard (spec/features/req/personas/…) |
| `fu-node.html` | Solid-node full architecture (25 layers on the IrfTek kernel) |
| `fu-protocol.html` | Mesh protocol spec v6 (vectors are law) |
| `fu/conformance/` | `vectors.json` + `README.md` (CI gate) + `PROTOCOL_CHANGELOG.md` |
| `AUDIT.md`, `STACK.md`, `DEPLOY.md`, `POLISH.md`, `SLICES.md`, `FRONTEND_SLICES.md` | Point-in-time build artifacts (see banner in each) |
| `docs/irftek-*`, `docs/ALIGNMENT.md`, `docs/FU-APPENDIX.md` | IrfTek research lineage |

## Honest state

- **App:** complete and tested; pre-launch blockers remain — real SMS
  adapter, admin credential out of source.
- **Network:** simulation + frozen contract only. Real BLE/NFC transport,
  the Rust runtime, the phone client, and the node OS layer are unbuilt.
  Friendless-bootstrap is mitigated (~90%), not zero.
- Nothing has been pushed to a remote; all work is local commits on
  `feat/audit-test-deploy-polish`.
