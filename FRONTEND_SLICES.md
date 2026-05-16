# Frontend Plan v1.0 → LiveView Port — Slices

Bringing each existing LiveView surface up to the frontend plan's component
anatomy. Design system + login + home + nav + global tokens already done
(commit 8324203). Stack stays Phoenix LiveView (no Next.js).

Legend: `[ ]` todo · `[x]` done · ‖ parallel-safe (file-disjoint).
Orchestrator owns app.css / layouts.ex / router.ex / core_components.

## Wave A — per-surface anatomy (4 parallel agents, one LiveView each)

Queue browser (`browse_live.ex`) — ✅ done, runtime-verified:
- [x] FE01 Queue Card → §6.3 (meta row, field h3, distance, summary, lock)
- [x] FE02 Position-Fill widget → §6.4 (slot-cell bar, count states, NEEDS YOU)
- [x] FE03 Filter chips → §6.5 (selected solid, scroll)
- [x] FE04 Empty states → §6.9 (serif italic + CTA)

Lobby (`lobby_live.ex`) — ✅ done, compile-verified:
- [x] FE05 Roster row → §7.3 (number·name·pos·rank·badges, self tint, ★)
- [x] FE06 Captain claim widget → §7.4 states
- [x] FE07 Position-swap → §7.5 sheet
- [x] FE08 Chat tabs (friend-group banner omitted — no such assign)

Post-match (`post_match_live.ex`) — ✅ done, compile-verified:
- [x] FE09 Final score → §9.2/§9.3 (serif score, editorial line)
- [x] FE10 Rank-delta hero + itemized breakdown → §9.4
- [x] FE11 Voting flow → §9.5 (editorial taglines, keeper 1–10)

Profile (`profile_live.ex`) — ⛔ DEFERRED (agent hit usage cap mid-write,
reverted to working brand-themed 8324203):
- [ ] FE12 Settings sectioned list → §10.2
- [ ] FE13 Availability editor → §10.3
- [ ] FE14 Match history + SVG sparkline → §10.4

Queue chatroom (`queue_chat_live.ex`) — ⛔ DEFERRED (agent cap):
- [ ] FE15 Type-scale/divider polish (already messenger-style + themed)

> Wave A: 2 agents completed cleanly (browse, lobby); post-match agent
> also completed (compiles); profile agent truncated → reverted.
> Re-run FE12–15 after usage resets (06:00 Europe/Amsterdam).
> /lobby & /postmatch runtime click needs a fresh `mix run seeds.exs`
> (current seed ids 33/34 reassigned) — code is compile-clean.

## Wave B — polish (orchestrator + shared files)

- [ ] FE16 Skeleton loaders on async surfaces (§11.2)
- [ ] FE17 Error/offline banner + toast retry (§11.1)
- [ ] FE18 Accessibility pass — aria-labels, contrast, kbd nav (§11.3)
- [ ] FE19 PWA: manifest.json + icons + iOS meta (§11.5)

Deferred (plan §14, not v1): onboarding, avatar generator (have SVG),
card-as-PNG share, push, contact import, multi-language, dark toggle.
