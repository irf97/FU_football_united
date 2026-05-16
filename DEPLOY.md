# Football United · Pre-deployment checklist
_For putting this in front of a real Enschede footballer. Stack-specific.
Phoenix LiveView monolith · PubSub realtime · 2 named GenServers ·
Postgres-only · `Fu.SMS` stub · Windows dev · no Docker._

## ⚠️ Read first — the #1 blocker is product, not infra

`AUDIT.md` integration break #1: **there is no in-app way to finish a
match.** `Matches.record_score/record_goal/complete_match` and
`Ranking.finalize_match` are called only from `priv/repo/seeds.exs`. A real
footballer's match would **never produce a rank change, and post-match
voting can never open** (`voting_open?` needs `complete_match`'s
`votes_close_at`). No amount of hosting fixes this. **Do not soft-launch
the rank/voting loop until a score-entry surface exists** (operator- or
captain-driven action calling `Matches.record_score` → `complete_match` →
`Ranking.finalize_match`; `Ranking.record_no_show` is also dead). This is a
~1-day wiring task, not a rebuild — but it gates "first user" for the
*ranked* product. The non-ranked loop (browse → join → lobby → captain →
chat) **is** shippable today (Balance loop fixed in Phase 2, `5bb1411`).

## 3.1 Hosting — **Fly.io** (decided)

Solo founder, one city, no ops bandwidth → Fly.io.

- **Why not Gigalixir:** hot-upgrades are a power feature you won't use;
  Fly's free allowance + managed Postgres covers ~first 50 users at ~€0.
- **Why not bare VPS:** you'd own Postgres backups, TLS renewal, systemd,
  monitoring — operational burden with zero upside at this scale.
- **Fly specifics that matter here:**
  - One `fly.toml` app, **`min_machines_running = 1`** (LiveView holds
    stateful WS connections + the two GenServers must stay alive; do NOT
    scale-to-zero). Single region `ams` (Amsterdam — closest to Enschede).
  - **Single machine for v1.** `Fu.Queues.Resolver` and
    `Fu.Ranking.DecayWorker` are plain named GenServers with **no
    distributed coordination**. Multiple machines ⇒ the workers run on
    every node ⇒ duplicate resolution/decay. Stay single-node until you
    add a leader-election lib (out of scope). Note in `fly.toml`.
  - Fly Postgres (managed) in `ams`, smallest size.

## 3.2 Real SMS — **MessageBird** (NL), behind a behaviour

**Refactor finding (from AUDIT):** `Fu.SMS` is a *plain module, not a
behaviour* — swapping providers needs the extract below. Apply this as the
first deploy task (it is a refactor, not a feature — same observable
behaviour, log stub still default in dev/test):

```elixir
# lib/fu/sms.ex
defmodule Fu.SMS do
  @callback deliver(String.t(), String.t()) :: :ok | {:error, term()}
  def deliver(phone, body), do: impl().deliver(phone, body)
  defp impl, do: Application.get_env(:fu, :sms_adapter, Fu.SMS.Log)
end

defmodule Fu.SMS.Log do
  @behaviour Fu.SMS
  require Logger
  @impl true
  def deliver(phone, body), do: (Logger.info("[SMS→#{phone}] #{body}"); :ok)
end

# lib/fu/sms/message_bird.ex
defmodule Fu.SMS.MessageBird do
  @behaviour Fu.SMS
  require Logger
  @endpoint "https://rest.messagebird.com/messages"

  @impl true
  def deliver(phone, body) do
    key = Application.fetch_env!(:fu, :messagebird_key)
    req = Finch.build(:post, @endpoint,
      [{"Authorization", "AccessKey #{key}"},
       {"Content-Type", "application/x-www-form-urlencoded"}],
      URI.encode_query(%{originator: "FootballU", recipients: phone, body: body}))
    case Finch.request(req, Fu.Finch) do
      {:ok, %{status: s}} when s in 200..299 -> :ok
      {:ok, %{status: s, body: b}} -> Logger.error("SMS #{s}: #{b}"); {:error, :sms_failed}
      {:error, e} -> Logger.error("SMS transport: #{inspect(e)}"); {:error, :sms_failed}
    end
  end
end
```

- Add `{:finch, "~> 0.18"}`; add `{Finch, name: Fu.Finch}` to
  `Fu.Application` children.
- `config/runtime.exs` (prod): `config :fu, sms_adapter: Fu.SMS.MessageBird,
  messagebird_key: System.fetch_env!("MESSAGEBIRD_KEY")`.
- **Why MessageBird over Twilio/Vonage:** Dutch company, best NL carrier
  routing/deliverability, EUR billing, GDPR-resident — matters for an
  Enschede launch.
- **SMS-layer rate limit is mandatory (AUDIT deploy blocker):**
  `Accounts.request_otp` is unbounded. Add before going public — minimal:
  a per-phone + per-IP token bucket (e.g. `Hammer` lib, or a Postgres
  count of `otp_codes` for that phone in the last 10 min, reject > 3).
  Also cap `verify_otp` attempts (5/code then invalidate). Without this,
  one script = your entire MessageBird balance.

## 3.3 Runtime configuration

- `config/runtime.exs` is already present (Phoenix 1.8 default). Verify it
  reads `DATABASE_URL`, `SECRET_KEY_BASE`, `PHX_HOST`, `PORT` from env
  (Phoenix scaffolds this; confirm the `:fu, FuWeb.Endpoint` `url: [host:]`
  + `server: true`). Add `MESSAGEBIRD_KEY` and the admin password
  (currently a literal in `login_live.ex` — move to
  `System.fetch_env!("ADMIN_PASSWORD")`).
- **`mix release` on Windows will NOT produce a Linux artifact.** Releases
  are not cross-platform. Do **not** build locally. Use **Fly's remote
  builder**: `fly deploy` with a `Dockerfile` (Fly's `mix phx.gen.release
  --docker` generates the standard Elixir release Dockerfile). Prod does
  not "run Docker" in any way you manage — Fly's builder uses it to
  produce the release image; the running app is just the BEAM. This is the
  documented Windows workaround: **never `mix release` on this machine.**
- Secrets: `fly secrets set SECRET_KEY_BASE=… DATABASE_URL=…
  MESSAGEBIRD_KEY=… ADMIN_PASSWORD=…`. Nothing in git (`.gitignore`
  already excludes envs; `mix phx.gen.secret` for `SECRET_KEY_BASE`).

## 3.4 Database operations

- **Backups:** Fly Postgres takes daily snapshots automatically. Set
  retention to 7 days. Restore drill (do once before launch):
  `fly pg list` → `fly volumes snapshots list` →
  `fly pg restore <snapshot>` into a throwaway app, verify, document the
  exact commands in an ops note.
- **Pool size:** prod `POOL_SIZE` default 10 is right for ~100 users on
  one machine; do not raise without measuring (Postgres conn limits).
  Test stays `Ecto.Adapters.SQL.Sandbox`.
- **Migrations:** run from the release, not the dev box. Use the standard
  `Fu.Release.migrate/0` (`mix phx.gen.release` creates `lib/fu/release.ex`)
  and a Fly `release_command = "/app/bin/migrate"`. Migrate runs once per
  deploy before the new machine serves traffic.
- **The two GenServers on deploy/restart:**
  - `Fu.Queues.Resolver` — **idempotent** (AUDIT feat 7): `due_for_resolution`
    filters `state == "open"`, so a restart re-scanning is safe; worst case
    a queue's resolution is delayed by ≤1 tick (60s). Fine.
  - `Fu.Ranking.DecayWorker` — **not double-firing** but **first tick is
    +24h after boot** (no run on start). Frequent deploys ⇒ decay could be
    perpetually deferred. Acceptable at launch (decay is a 3-month-idle
    slow drift); note it and, post-launch, persist a `last_decay_at` and
    compute the next interval from it. Not a blocker.

## 3.5 Observability — **AppSignal + UptimeRobot + LiveDashboard** (decided)

One paid tool, one free, one built-in. No à-la-carte stack to wire.

- **AppSignal** (`{:appsignal_phoenix, "~> 2.0"}`) — APM + error tracking +
  host metrics + Phoenix/Ecto/LiveView instrumentation in one agent, one
  bill (~€19/mo solo tier). Set `APPSIGNAL_PUSH_API_KEY` secret, add
  `Appsignal.Phoenix` to the endpoint. Covers Step 3.5's Logger/Telemetry/
  error-tracking asks together — that's why it beats Sentry+Prometheus+….
- **UptimeRobot** (free) — 5-min ping on a `GET /healthz`. **Action:** add
  a tiny health route (plug returning 200 + a one-line DB `SELECT 1`) — it
  is the *only* code addition Phase 3 needs and it is infra, not a feature;
  add during deploy, not now.
- **LiveDashboard** — already mounted at `/dev/dashboard` (`router.ex`).
  **Action:** before prod, move it behind the same admin gate as `/admin`
  (currently `:dev_routes` only — confirm it is NOT exposed in prod, or
  wrap with `Plug.BasicAuth` using `ADMIN_PASSWORD`).
- Logger: set `config :logger, level: :info` in prod (not `:debug` — the
  app currently logs `[debug]` SQL; noisy + leaks data).

## 3.6 Domain, TLS, PWA

- Domain: point an apex + `www` (or `app.<domain>`) at Fly via
  `fly certs add footballunited.app`; Fly issues/renews Let's Encrypt
  automatically — no Caddy/nginx.
- TLS: automatic on Fly. Set `force_ssl` in the endpoint for prod.
- PWA: `/manifest.webmanifest` + `/images/fu-icon.svg` + apple-touch-icon
  are present and were verified `200` (commit `ce681f4`/`6e4dc47` era).
  Verify once more post-deploy that they serve over the real domain (the
  manifest `start_url`/`scope` are relative `/` so they travel fine).
- Native app-store listing: **out of scope for v1** — PWA install
  (Add to Home Screen) is the v1 distribution. Future track only.

## 3.7 First-user vs first-hundred

### First user — MUST (in order)
1. **Wire match completion** (AUDIT break #1) — operator/captain action →
   `Matches.record_score`→`complete_match`→`Ranking.finalize_match`.
   *Without this the ranked product is non-functional.* (Product task,
   precedes infra.)
2. SMS behaviour refactor + `Fu.SMS.MessageBird` + **OTP rate limiting**
   (§3.2) — verified end-to-end with a real Dutch number.
3. App on Fly at the real domain over TLS, single machine `ams`,
   `min_machines_running = 1`.
4. Fly Postgres with snapshots on; restore drill done once.
5. AppSignal capturing crashes; `/healthz` + UptimeRobot live.
6. LiveDashboard prod-gated; admin password from env, not source.
7. Logger at `:info`.

### First hundred — CAN WAIT (track, don't block)
- Friend-group queue join + friend-request *send* UI (AUDIT breaks #2/#3).
- Live-match surface + captain pause (AUDIT feature 12 MISSING).
- Load test the LiveView/PubSub fan-out; Postgres slow-query log + index
  audit (the `browse/2` filter query especially).
- Edge rate limiting (Fly handles basic; tune later).
- `support@footballunited.app` + a written process for user reports.
- Multi-node story (leader-elect the two GenServers) before scaling > 1
  machine.

## Gate
This file exists at repo root. Phase 4 does not depend on executing any of
the above — only on it being documented. The single most important line in
it is §3.7 item 1: **infra is ready long before the product is, because the
match→rank loop has no in-app trigger.**
