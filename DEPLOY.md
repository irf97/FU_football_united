# FU rehearsal and production handoff

Scope: the Phoenix shared hobby core. The frozen mesh reference is unchanged;
this image contains no physical peer network or radios. No live app, SMS
account or persistent database has been provisioned by these changes.

## Run the operational rehearsal

With Docker Compose, Node 24 and free local ports 4000, 5432 and 9166:

```sh
cd fu
npm ci --prefix qa
npx --prefix qa playwright install --with-deps chromium
FU_BROWSER_QA=1 \
DATABASE_URL=postgres://postgres:postgres@localhost:5432/fu_pilot_qa \
qa/release.sh
```

This builds the production image and runs it with PostgreSQL 17 and a local
SMS provider emulator. It generates a fresh cookie secret and owns the
`fu-acceptance-qa` Compose project. The database is disposable: the script
removes its own containers and volume when it ends. It refuses to reuse an
existing acceptance project or another database. Run it on an isolated QA host.

The same command runs in `.github/workflows/app.yml`, after `mix precommit`.
Use the actual run result as evidence. The uploaded artifact contains
`results/rehearsal-report.html`, its JSON, raw latency measurements and browser
captures. A missing or failed gate makes the report fail; it never fills in
unobserved results. Source revision and image ID identify what was exercised.

| Executable gate | Pass condition / boundary |
| --- | --- |
| Runtime separation | Same image; production rejects a simulator endpoint; unconfigured SMS fails closed; no demo codes or admin fallback. |
| Provider failures | Actual HTTP transport handles 503, malformed success, 401, 429 and timeout; one POST per request; undelivered codes consumed. |
| Desktop and mobile | Login, create, discover, commit, access confirmation, start, self check-in, finish and cancellation. |
| Reconnect and restart | Real WebSocket interruption catches up on missed updates; completed history persists after restarting the app. |
| Mission cycles | 48 synthetic participants; 12 sessions in each of open, practice and committed modes; 27 complete and 9 cancel. Four additional browser identities run two more completed and two cancelled sessions. |
| Integrity | Capacity four under 24 contenders; 12 duplicate joins make one membership/event; withdrawal/rejoin resets commitment; unauthorized host changes rejected; player profiles unchanged. |
| Sustained reads | Eight authenticated HTTP readers plus eight domain readers, paced at 100 ms, for 60 seconds. Zero observed errors; HTTP p95 ≤ 1000 ms; context p95 ≤ 500 ms. Mutation p95 also ≤ 500 ms. |
| Resource envelope | App container limited to one CPU and 512 MiB. This is a measured envelope, not an unlimited capacity promise. |
| Interrupted transaction | Kill the app after a membership write, while its history INSERT waits on a table lock; no partial membership/event; retry produces exactly one of each. Readiness returns within 30 seconds. |
| Restore | Quiescent dump/restore matches all rows in five identity/OTP/hobby tables and all public sequence values. Boot the same image on the restored database, open completed history in an authenticated browser, then create a new record. |
| Database outage | Health changes to 503, then returns to 200 within 30 seconds after restarting PostgreSQL. |
| Configuration rollback | A candidate with an invalid database configuration returns 503; resume the known-good image/configuration within 30 seconds. Arbitrary future code/schema rollback is outside this test. |

Wall-clock session starts are observed normally; QA does not rewrite session
timestamps or select an alternate clock. Bulk mission setup invokes actual
application contexts through privileged release RPC, guarded by rehearsal mode
and the exact disposable database. These scripts are not compiled into the
production app and add no public fixture or mailbox routes to it.

## Explore the local app

For a rehearsal that stays running:

```sh
cd fu
export SECRET_KEY_BASE=$(openssl rand -base64 64)
docker compose -p fu-rehearsal -f compose.rehearsal.yml up --build --detach app
```

Open http://localhost:4000. Request a code for a synthetic number such as
`+31680000001`, then read its private local mailbox:

```sh
curl --silent \
  -H 'Authorization: AccessKey fu-sim-local-rehearsal-only' \
  'http://localhost:9166/mailbox?phone=%2B31680000001'
```

Use the six-digit code in the returned message. The app visibly labels
simulation, hides OTPs on screen and emits `x-fu-environment: rehearsal`.
The emulator performs no outbound delivery. Its mailbox and failure controls
require the dummy simulation token; all three exposed ports bind to loopback.
`docker compose -p fu-rehearsal -f compose.rehearsal.yml down` stops this stack
and preserves its local volume. Keep the exported secret while reusing it.

## Transfer the same image to real conditions

| Boundary | Rehearsal | Real deployment |
| --- | --- | --- |
| App | Production release image, `FU_MODE=rehearsal` | Same qualified image, `FU_MODE=production` |
| Database | Local disposable PostgreSQL 17 | Dedicated persistent PostgreSQL with host-specific backup/restore policy |
| SMS | Local emulator; `fu-sim-` dummy key; `FU_SMS_ENDPOINT=http://sms:9166/messages` | Optional MessageBird account; live key; omit `FU_SMS_ENDPOINT` (fixed HTTPS provider URL) |
| Host | `localhost`, loopback ports | Actual TLS hostname and host port |
| Cookie secret | Fresh random rehearsal secret | Separate persistent production secret from the host's secret manager |
| Participants / place | Synthetic identities and host declarations | Consenting people, their phones and actual venue permission |
| Evidence | Automated bounded scenarios | Actual delivery, participation, incidents, restore and sustained operation |

Do not transfer synthetic records, dummy credentials, mailbox containers or
QA RPC scripts to production. Material changes to code, schema, topology or
provider require qualification again. A local protocol emulator verifies the
client contract; it cannot establish a carrier's behavior or handset receipt.

`fu/.env.production.example` lists the values to supply through host secrets:

| Variable | Requirement |
| --- | --- |
| `FU_MODE` | `production` (also the default). |
| `DATABASE_URL` | Required dedicated persistent database; configure network/TLS for the chosen host. |
| `SECRET_KEY_BASE` | Required; generate separately, keep outside git and command history. |
| `PHX_HOST` | Required actual hostname, without scheme/path. |
| `PORT` | Fly supplies `8080`. |
| `POOL_SIZE` | Defaults to 10; measure before increasing. |
| `ECTO_IPV6` | Fly config enables IPv6 on its private database network. |
| `FU_SMS_PROVIDER` | `messagebird` for the included integration, or `disabled` to keep delivery closed. |
| `FU_SMS_API_KEY`, `FU_SMS_ORIGINATOR` | Required for MessageBird; never use a `fu-sim-` key in production. |
| `FU_ADMIN_PASSWORD` | Optional; absence disables admin login. |

The optional MessageBird provider uses `Fu.SMS.HTTPAdapter` and a bounded Req
transport, with redirects and automatic POST retries disabled. A provider
acceptance receipt is required; acceptance does not mean handset delivery.
Other providers can implement the existing Provider/Transport boundary.
The five-per-phone OTP request budget, five-attempt budget and consumption are
serialized in PostgreSQL. Before public registration, configure edge request
budgets and a provider spending cap to bound requests across many numbers.

## Fly.io handoff

Use a connected Fly account and an app name you own. From `fu/`, create/select
that app, provision persistent PostgreSQL and set the runtime secrets above.
`fu/fly.toml` intentionally receives its app name through `--app`:

```sh
fly config validate --app <your-app>
fly deploy --app <your-app> --ha=false
fly scale count 1 --app <your-app>
fly checks list --app <your-app>
node qa/live-preflight.cjs https://<your-host>/
```

Live preflight only reads HTTPS readiness, production labeling, the login
screen, authentication redirect and absence of the development dashboard.
It sends no OTP and creates no data. It cannot establish real operation.

Use a **single machine**: named Resolver and DecayWorker processes have no
distributed leader election. The config keeps it awake and uses rolling
replacement, with a brief interruption. The release command migrates before
serving. TLS terminates at Fly; forwarded HTTPS is honored and `/healthz`
remains available to the internal checker. Do not run demo seeds in production.
The rehearsal verifies the image; `fly deploy` rebuilds it from source. If an
identical image is required, publish the qualified image to your registry and
select its immutable digest in your host's deployment process.

## Real operational evidence still required

1. Confirm handset receipt and single-use login with the selected live account
   and intended devices. Check real delivery failures without exposing codes.
2. Obtain actual venue permission. In-app access confirmation remains a host
   declaration, not an automatic booking or operator verification.
3. Run sessions with consenting participants on their own phones. Exercise
   withdrawal, cancellation, reconnect and completion; record actual attendance
   separately from self check-ins and have the organizer confirm the outcome.
4. Assign an operator, monitoring/incident process and data retention controls.
   Test a restore on a separate database in the intended environment. The
   quiescent CI checkpoint does not establish a production backup RPO.
5. Observe repeated operation for an agreed period and retain the real outcomes,
   failures and recovery evidence. A 60-second local run cannot supply this.

The deliverable is an executable operational rehearsal with a configuration
handoff. Simulation passes do not confer real TRL 9 or prove every future
hobby-specific workflow.
