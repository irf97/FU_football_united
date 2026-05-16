# Football United · Polish (Phase 4)
_Surface: **Home** (`lib/fu_web/live/home_live.ex`). Branch
`feat/audit-test-deploy-polish`._

## Why Home

Per the brief's default and `AUDIT.md`: Home is **WIRED** (feature 2,
`home_live.ex` handlers → `Accounts`/`Friends`/`Groups`/`Matching` →
`Repo`, all traced) and is the load-bearing daily-return surface. It was
structurally sound after the design-system port but failed four concrete
items of the Phase-4 checklist. No Phase-1 findings were discovered during
polish (handlers/subscribers unchanged). **No behaviour changed** — every
edit is presentational; all `phx-click`/handlers/assigns are byte-identical.
`mix test` still **31 tests, 2 properties, 0 failures**; `/` verified
HTTP 200 with the new markup.

## What was wrong, and what changed (file:line in the post-edit file)

### 1. Lime discipline (visual hierarchy — the headline rule)
**Before:** lime (`btn-primary`) appeared 3× — the Queue CTA *and* the
friend **Accept** button *and* the **Fill-mode "on"** state.
**After:** lime is now only the Queue CTA (`home_live.ex:142-160`). Accept
→ `btn-outline` (`:227`); Fill-mode → `btn-outline` with a `✓` + bordered
active state, `aria-pressed` (`:175-182`); add-to-group chips → `btn-outline`
(`:255`); create-group → `btn-outline` (`:262`). Verified live: the only
lime on the page is the CTA (+ the shared bottom-nav "you-are-here" dot,
which is the legitimate single current-state signifier).

### 2. Touch targets — were sub-44px (non-negotiable)
**Before:** position pills (`pos-pill`, ≈22px tall) tapped on every visit;
friend Accept (`btn-xs`, ≈20px); add-friend chips (`pos-pill`).
**After:** `min-h-[44px]` on the position pills (`:289`, the core Home
interaction), Accept (`:227`), fill toggle (`:178`), add-to-group chips
(`:255`), create-group (`:262`), suggestion rows (`:198`), and the
"set availability" empty-state CTA (`:191`). All now ≥44×44.

### 3. Empty states — were dead-end muted text
**Before:** "Add availability windows…" and "No friends yet." — flat
`fu-ink-soft`, no editorial voice, no next action.
**After (brief: serif-italic OR a clear action — now both):**
- Suggestions empty (`:188-194`): `fu-serif` *"We can't see you yet —
  tell us when you play."* + a real `btn` → `~p"/profile"` "Set your
  availability →".
- Friends empty (`:224-226`): `fu-serif` *"No teammates yet — share your
  link to bring someone."* (the invite link directly below is the action).

### 4. Section-header consistency
**Before:** Position / Suggested / Friends used an ad-hoc
`text-xs fu-ink-dim font-mono uppercase tracking-wider` — inconsistent
with every other surface, which uses the design-system `fu-divider`.
**After:** all three are `<div class="fu-divider">…</div>`
(`:160`, `:185`, `:206`) — the established "──── LABEL ────" rule.

### 5. Accessibility floor
- Decorative `⚡` in both Queue CTA branches wrapped
  `<span aria-hidden="true">` (`:146`, `:156`); the link carries a real
  `aria-label` ("Find a match" / "Set availability to find matches").
- `aria-pressed` on the fill-mode toggle (`:177`) and each position pill
  (`:288`); `aria-label` on position pills (`:289`) and add-to-group
  buttons (`:251`) so the icon/code-only controls are screen-reader clear.
- Form cells already carry the W/L/D **letter** inside the colour cell
  (`:130`) — colour is not the only signifier; left as-is.
- Theme consistency: stray `border-neutral` → `border-[var(--fu-line)]`
  (`:197`, `:243`).

## Not changed (deliberately)
- **Loading states / skeletons:** N/A — LiveView `mount` loads all data
  before first render; there is no SPA async gap on Home. (Same reasoning
  as the audit; `.skeleton` util exists if a future async panel needs it.)
- **Error states:** existing handlers already use `put_flash` where they
  can fail (`set-pos`, `add-to-group`); `accept-friend`/`create-group`
  are low-risk and unchanged — touching handler behaviour is out of
  Phase-4 scope (polish, not feature work).
- The player-card hero, Queue CTA copy, position-quick-edit logic, and the
  friend/group data flow were already correct from the design-system port
  — not rebuilt (brief: "don't rebuild what already works").

## Verification
- `mix compile` clean (0 warnings). `mix test` → 31 tests / 2 properties /
  0 failures (unchanged — no behaviour touched).
- Server booted; `GET /` (authenticated) → **200**, rendering
  `fu-divider`, `min-h-[44px]`, `aria-hidden`, `aria-label`, `btn-outline`,
  the editorial empty-state copy, and exactly one lime CTA.
