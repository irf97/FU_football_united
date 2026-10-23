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
`feat/audit-test-deploy-polish`.

---

## Hobby sessions · 22 October 2026

The authenticated `/hobbies` area adds a shared session model for futsal,
table tennis, music and other hobbies. Open presence, practice and committed
participation retain distinct obligations. Football matchmaking and its
ranking remain in their existing domain.

The flow is create → discover → join → optionally commit → confirm access →
start → self check-in → finish. Hosts can cancel with a reason; participants
can withdraw, explain a committed withdrawal and rejoin. The session row is
locked while capacity, participation and its event record change together.
Duplicate joins/commitments/check-ins reuse existing state. PubSub refreshes
connected views; reopening a page reads persisted state.

`/explore` searches events by interest, format, hobby, participation mode,
place and available space. Hobby names remain open-ended; categories organize
discovery rather than restrict activities. **My events** includes persisted
participation history and cancelled/completed events.

New hobby participants sign in with their phone code and land in Explore,
without football profile setup. Opening an event or filtered discovery link
while signed out preserves that exact page through login. Each login handoff
binds its destination to the signed token, so a second tab cannot replace it;
only known FU pages are accepted and event access checks still apply. The
Football tab keeps the existing football home available explicitly.

`/equipment` keeps owner-scoped inventory, condition, interval reservations
and last-reported zones separate. Scoped, revocable receiver credentials accept
timestamped collector reports; retries are deduplicated, old reports become
stale and radio signal strength is never displayed as a distance estimate.
The included JSON-line collector bridge needs an external tag scanner/gateway;
its optional private SQLite outbox preserves pending IDs and timestamps across
restart, including an uncertain HTTP receipt. Fixed receivers and native Android
collectors are candidates for the first physical test; an engineer will help
select the setup. The Android scanner and RF performance are not yet qualified.
The review brief, delivery contract and field checks are in [DEPLOY.md](DEPLOY.md).

An event's **assistant** explains venue, people, time and gear readiness.
Hosts can optionally configure a shared timer and scoreboard and appoint a
current participant as referee. Commands have revisions and retry keys;
corrections require reasons and remain in the audit history. A persistent
deadline survives restarts. People adjudicate and confirm results; this does
not introduce autonomous refereeing or cross-hobby ranking.

Access confirmation records what the host checked with the venue operator.
It does not reserve a venue. An optional MessageBird provider and bounded Req
transport now support real SMS configuration; a local emulator exercises the
same HTTP path in rehearsal. No deployed mesh network is included.

Validate on Elixir 1.19 / OTP 28 with PostgreSQL:

```sh
cd fu
mix deps.get --check-locked
mix precommit
mix test test/fu/hobbies test/fu_web/live/hobbies_live_test.exs --seed 0
mix phx.server
```

`.github/workflows/app.yml` runs the full application suite, including
simultaneous seat-contention and duplicate-request tests, on PostgreSQL 17.
Use its actual run result as evidence; adding a workflow does not establish
that it passed. Protocol conformance retains its separate existing gate.

**Operational rehearsal:** [DEPLOY.md](DEPLOY.md) gives the executable gate,
local exploration command and production handoff. The same release image runs
48 synthetic mission participants through 36 sessions, desktop/mobile browser
flows, capacity contention, interrupted transactions, sustained reads and
restore/configuration recovery. The 60-second, one-CPU/512-MiB envelope and
measured results appear in each CI artifact's HTML/JSON report. Treat a gate as
passed only when its actual run succeeds. Rehearsal mode is visibly labeled;
production rejects simulator endpoints and dummy credentials.

**Readiness boundary:** simulated outcomes support the current core within
that measured envelope. Real TRL 9 still requires actual venue permission,
handset delivery, completed sessions with consenting people, operator recovery
and sustained successful operation in the intended environment.

## Run it

```sh
cd "fu" && source ../devenv.sh        # PATH persistence is sandbox-blocked
mix deps.get
mix ecto.create && mix ecto.migrate
mix run priv/repo/seeds.exs           # 3 fields, 16 players, queues, a
                                      # confirmed lobby + a finalized match
mix phx.server                        # http://localhost:4000
```

In development, sign in with a seeded phone, e.g. **`+31610000001`**. The
log adapter and visible demo code are development conveniences. Production
hides codes and fails login closed until a real SMS provider and transport are
configured. The container, browser and recovery gate plus deployment steps are
in [DEPLOY.md](DEPLOY.md). Windows/dev gotchas (one mix process at a time, port-4000 zombies,
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
| `/explore` | Search all hobby events and personal event history |
| `/hobbies`, `/hobbies/new`, `/hobbies/:id` | Create and run shared hobby events |
| `/equipment` | Private inventory, event reservations and reported zone map |
| `/hobbies/:id/assistant` | Member-scoped organizer, timer and human scorekeeper |
| `/queue/:id/chat` | Persistent per-queue chatroom |
| `/lobby/:id` | Rosters, sequenced captain claim, swaps, lock progress |
| `/match/:id` | Synced clock, captain controls, **tactics manager** |
| `/postmatch/:id` | Peer voting (24h) → append-only rank ledger |
| `/profile` | Identity, sub-positions, avatar picker, themes, history |
| `/admin` | Password-gated console |
| `/lab` | **Mesh Lab** — interactive P2P simulator + conformance |

Contexts: `Accounts · Positions · Queues · Matching · Balance · Lobby ·
Matches · Tactics · Voting · Ranking · Friends · Groups · QueueChat · Events
· Admin · Hobbies · Equipment · Assistant`, plus the research namespace `Fu.Mesh{,.V2,.V3,.Identity,.Wire}`.
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

- **App:** football and shared hobby workflows have executable validation.
  A real host, provider account, physical collector integration and real
  operational evidence remain pending; see DEPLOY.md for the current boundary.
- **Network:** simulation + frozen contract only. Real BLE/NFC transport,
  the Rust runtime, the phone client, and the node OS layer are unbuilt.
  Friendless-bootstrap is mitigated (~90%), not zero.
- Published to GitHub (this repo). A public live deployment is planned;
  until then, run locally as above.
