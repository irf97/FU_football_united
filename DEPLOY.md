# FU pilot deployment

Current scope: the Phoenix app and its shared hobby sessions. The mesh stays
an executable reference; this release contains no peer network or radios.

The repository now contains a production Dockerfile, release migration and
server commands, and `fu/fly.toml` for the existing Amsterdam hosting choice.
No live app or database has been provisioned by these changes.

## Release gate

`.github/workflows/app.yml` runs the full application suite on PostgreSQL 17,
builds the browser assets, then builds and boots the actual production image.
Its guarded QA suite uses a disposable database and synthetic identities:

- Desktop and mobile Chromium: phone verification, host creation, discovery,
  explicit commitment, host access confirmation, start, self check-in and finish.
- A disconnected participant catches up after reconnecting; completed history
  survives a container restart; connected guests receive cancellations.
- `pg_dump`/`pg_restore` must preserve every identity, OTP and hobby record.
- A database outage must turn `/healthz` into HTTP 503; recovery restores 200.

The browser suite deliberately replaces the SMS adapter through a privileged
release RPC in the disposable container and reads synthetic codes from its
DB. It never calls a provider, sends a real text or tests venue availability.
It restores the fail-closed adapter afterward. Do not run QA against live data.

Local reproduction, with a disposable PostgreSQL 17 container reachable on
localhost:5432 and an empty `fu_pilot_qa` database:

```sh
cd fu
npm ci --prefix qa
npx --prefix qa playwright install --with-deps chromium
export FU_BROWSER_QA=1
export DATABASE_URL=postgres://postgres:postgres@localhost:5432/fu_pilot_qa
export FU_QA_POSTGRES_CONTAINER=<disposable-postgres-container-id>
qa/release.sh
```

## Production configuration

| Variable | Requirement |
| --- | --- |
| `DATABASE_URL` | Required; dedicated persistent PostgreSQL database. |
| `SECRET_KEY_BASE` | Required; generate with `mix phx.gen.secret`, keep outside git. |
| `PHX_HOST` | Required; the actual hostname, without a scheme or path. |
| `PORT` | Fly config supplies `8080`. |
| `POOL_SIZE` | Defaults to 10; measure before increasing. |
| `ECTO_IPV6` | Fly config enables IPv6 for its private database network. |
| `FU_ADMIN_PASSWORD` | Optional; absence disables admin login. |

Production forces demo codes off and selects `Fu.SMS.HTTPAdapter`, which
returns an error until a concrete `Fu.SMS.Provider` and `Fu.SMS.Transport` are
configured. `Accounts.request_otp/1` now reports that failure, consumes the
undelivered code and retains the request count. It never pretends a text was
sent. Keep credentials in runtime configuration. Provider choice remains
open; the older MessageBird example was not a working integration.

The five-per-phone request budget, attempt budget and single-use consumption
are serialized in PostgreSQL. Before opening registration publicly, also
configure an edge request budget and a provider spending cap; a per-phone cap
does not bound traffic spread across many numbers.

## Fly.io handoff

Use a connected Fly account and an app name you own. From `fu/`, create or
select that app, provision persistent PostgreSQL, and set the runtime values
above through Fly secrets. Keep generated secret values out of command history.
The committed config intentionally gets its app name from `--app`:

```sh
fly config validate --app <your-app>
fly deploy --app <your-app> --ha=false
fly scale count 1 --app <your-app>
fly checks list --app <your-app>
```

Confirm the app is a **single machine** before routing users to it. Named
`Resolver` and `DecayWorker` processes have no distributed leader election.
The config keeps the machine awake and uses a rolling replacement; a single
machine deployment has a brief interruption. The release command migrates
before serving traffic. TLS terminates at Fly; the app honors forwarded HTTPS
and leaves `/healthz` available to its internal health checker.

Do not run demo seeds in production. Use the database service's backup policy
and repeat the restore drill on a separate database in the real environment;
the disposable CI drill does not establish the production backup policy.

## Real pilot acceptance

After the release gate is green and hosting plus real SMS are configured:

1. Verify a real phone can request and consume a code without exposing it on
   screen, and that failed delivery offers an honest retry path.
2. Arrange actual permission to use the place. The in-app confirmation is a
   host declaration, not an operator integration or booking.
3. Run a small session with consenting participants on their own phones;
   exercise a withdrawal or cancellation and a reconnect.
4. Record completion, actual participation, failures and recovery; have the
   organizer confirm the outcome. Keep identities and contact details private.
5. Review crash logs, delivery failures, database backup and restore results.

These are the next relevant-environment evidence gates. Automated tests and
synthetic attendance do not establish TRL 5–9. Retention, real operations and
repeated successful sessions still need to be observed.
