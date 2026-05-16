# Football United — Stack

The app is a **Phoenix LiveView monolith** (server-rendered, WebSocket UI —
no separate API, no client SPA). The Next.js frontend plan was *not* built;
its design system was ported into LiveView instead.

## Runtime / language
- Elixir 1.19.5 · Erlang/OTP 28.5
- Phoenix 1.8.7 · Phoenix LiveView
- PostgreSQL 17 via Ecto (`Fu.Repo`)

## Frontend (rendered by LiveView)
- Tailwind CSS v4 + daisyUI v5 — theme rewritten to FU brand tokens
- Fonts: Instrument Serif × Schibsted Grotesk × JetBrains Mono (Google Fonts)
- esbuild; one JS hook (`ChatScroll`); heroicons
- PWA: `priv/static/manifest.webmanifest` + SVG icon + iOS meta (installable)
- Design rule: dark `#0A0908` canvas, lime `#C5FF3D` is the ONE reserved
  accent (CTAs / moments that land — never headings/all buttons)

## App structure (`fu/`)
- Contexts: Accounts (phone-OTP), Fields, Queues, Positions, Matching,
  Friends, Groups, Booking, Balance, Matches, Voting, Ranking, QueueChat,
  Admin
- LiveViews: Login, Home, Browse, Lobby, PostMatch, Profile, QueueChat, Admin
- Supervised workers: `Queues.Resolver` (T-3h partial-fill),
  `Ranking.DecayWorker`
- Realtime: Phoenix PubSub (queue fill, lobby, captain, chat)
- Auth: phone-OTP → signed token → httpOnly session cookie
  (`SessionController` + `PlayerAuth`). SMS = log stub (`Fu.SMS`).
  Admin = `players.is_admin`; password-gated entry on /login (pw lives in
  `LoginLive` — demo gate, not real security).

## Infra / tooling
- Dedicated git repo at `C:\Users\irfan\football united` (NOT the home-dir
  repo), branch `main`. Commit-per-feature history.
- Windows dev: toolchain on PATH via `source ../devenv.sh` per shell
  (PATH persistence is sandbox-blocked). Run server with the Bash tool's
  background mode, never `setsid`. One `mix` process at a time (shared
  `_build` compile lock). Don't wrap `mix run seeds.exs` in a short
  `timeout` — it deletes-then-inserts; a kill leaves a partial DB.
- Seed/verify: `priv/repo/seeds.exs` (prints live /lobby & /postmatch
  ids; marks first player +31610000001 "Sven" admin) and
  `priv/repo/*_smoke.exs`. No ExUnit suite — verification is smoke
  scripts + HTTP checks.

## NOT in the stack (referenced by docs, not built)
NATS, S3, Redis, Docker; the Next.js/TypeScript/Zustand/TanStack
frontend; JSON REST API; Phoenix Channels client. Persistence is
Postgres only.

## Slice ledgers
`SLICES.md` (backend MVP S00–S60), `FRONTEND_SLICES.md` (design-system
port FE01–19). Plus post-MVP: queue chatroom, avatars, admin dashboard.
