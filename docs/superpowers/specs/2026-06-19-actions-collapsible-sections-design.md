# Actions Page — Collapsible Sections + Section Queue Controls

**Date:** 2026-06-19
**Status:** Design approved, pending spec review
**Scope:** Frontend only (`dashboard-react/`) + dashboard redeploy. No BigQuery / Cube / engine changes.

## Goal

Restructure the Actions page so each existing top-level block becomes a **collapsible section** with a **summary row** and **Queue all / Unqueue all** controls, and give **every** action row/card a consistent per-item **unqueue** control so any queue action can be undone. Also surface budget-decrease actions (today buried) as their own section, and wire the New Campaigns (launch) actions into the Do/bulksheet export so their Queue all works end-to-end.

## Background — current state

- `ActionsPage.tsx` renders several distinct blocks today: the curated **clear-case cards** (`clearCases`, grouped by family, cap 10), the **🆕 New campaigns** launch block (`launchGroups`, ~L1499), and the big **grouped table** (`filtered` rows → tree, grouped by a `hierarchy` selector: campaign/action/action_type/strategy/branch).
- Budget actions exist in the data (`action_type = 'BUDGET'`, `search_term = NULL`) but are effectively invisible: the default **"Show Monitor"** toggle (`hideMonitor`, default `true`, ~L529) drops `BUDGET_OK`, and the actionable `GUARDIAN_BUDGET_DECREASE` rows only appear nested deep in the campaign tree.
- Queue plumbing (`useDoQueue.tsx`) already exposes `addItem`, `removeItem(id)`, `clearAll`, `clearCampaign`, `hasItem`, `items`. The Do/bulksheet export is built **from the queue** (`DoPage.tsx:69`, iterates `doQueue.items`), grouped campaign → action → target.
- Per-item queue UX is inconsistent today: some rows toggle add/remove (hot signals, ~L1025), others only add (phrases, ~L1063).

## Design

### 1. `<CollapsibleSection>` (new reusable component)

`dashboard-react/src/components/Actions/CollapsibleSection.tsx`

Props:
- `id: string` — stable key for persistence (e.g. `'budget'`, `'top-picks'`, `'all-actions'`, `'new-campaigns'`).
- `title: ReactNode` — icon + label (e.g. `💰 Budget Actions`).
- `summary: ReactNode` — the right-aligned summary stats (rendered by the caller).
- `onQueueAll?: () => void`, `onUnqueueAll?: () => void` — omit either to hide that button (e.g. New Campaigns may hide Unqueue all if nothing queued; a section with no queueable items hides Queue all).
- `queueableCount: number`, `queuedCount: number` — drive button enabled/disabled state and labels.
- `defaultCollapsed?: boolean` (default `true`).
- `children` — the section body.

Behavior:
- Header row always visible: `title  …summary…  [Queue all] [Unqueue all]  ▸/▾`.
- Body collapses/expands on header click (chevron). State persisted per `id` in `localStorage` under key `oi_actions_sections` (a `Record<id, collapsed>`); **default collapsed**.
- `Queue all` disabled when `queueableCount - queuedCount === 0`; `Unqueue all` disabled when `queuedCount === 0`.

### 2. The four sections

| id | Title | Rows it owns | Queueable rows |
|---|---|---|---|
| `top-picks` | 🎯 Top picks | `clearCases` | all (existing clear-case actions) |
| `budget` | 💰 Budget Actions | `acts` where `action_type === 'BUDGET'` and `action !== 'BUDGET_OK'` | the increases/decreases |
| `all-actions` | 📋 All actions | the existing `filtered` table rows | term/target actions already exportable |
| `new-campaigns` | 🆕 New campaigns | `launchGroups` rows | rows where `launch_decision ∈ {LAUNCH_REDUCE_BID, LAUNCH_NEGATE}` |

`BUDGET_OK` stays out of the Budget section (no-op). **To avoid double-listing, the 📋 All actions `filtered` set must exclude `action_type === 'BUDGET'` rows** — budget rows are owned solely by the 💰 Budget section (today they also leak into the table). The 📋 All actions section otherwise keeps the existing `hierarchy` selector and tree **unchanged inside**; it just gains the collapsible shell + summary + section queue controls. The Budget section is a flat list of campaign budget rows (campaign · current → recommended budget · reason).

### 3. Summary row content (per section)

Format: `<count> <unit> · <$ at stake> · <queued>/<count> queued`.

- 🎯 Top picks: `N picks · ~$X/wk opportunity · Q queued` — `$X` = Σ `opp` (existing `opportunityPerWeek`).
- 💰 Budget: `N campaigns · trim ~$X/day · Q queued` — `$X` = Σ `current_budget − recommended_budget` over decreases (increases shown as `+$`).
- 📋 All actions: `N actions · ~$X/wk at stake · Q queued` — `$X` from existing `SPEND_BUCKETS` weekly value.
- 🆕 New campaigns: `N launch kw · A reduce / B negate / C hold · Q queued`.

### 4. Section-scoped Queue all / Unqueue all

Helper in `ActionsPage.tsx` (or a small `sectionQueue.ts`):
- `queueAllInSection(rows)` → for each actionable row not already queued/done/uploaded, call the section's queue builder (`queueAction` for term/target; a new budget builder; the launch translator below).
- `unqueueAllInSection(rows)` → for each row currently queued (matched via `doQueue.items` by `campaign_id` + `action` + `search_term||targeting`), call `removeItem(id)`.

### 5. Per-item unqueue (standardize)

Every row/card uses one toggle component: `[+ queue]` when not queued → `addItem`; `[✓ ✕]` when queued → the `✕` calls `removeItem(id)`. Replaces today's add-only buttons (phrases) and unifies with the existing toggle (hot signals). Lookup of the queued item id reuses `doQueue.items.find(...)` by `campaign_id` + `action` + `search_term||targeting`.

### 6. Budget actions — queue + export

- Budget rows are queueable: extend the queue builder to populate a `DoQueueItem` carrying `campaign` / `campaign_id`, `action` (e.g. `GUARDIAN_BUDGET_DECREASE`), `current_budget`, `recommended_budget`. `search_term`/`targeting` stay empty.
- DoPage already has budget branches in `ACTION_ORDER` and emits a Campaign budget-update row from `recommended_budget` (~L989-996). Verify the queued budget item flows through that branch; adjust the branch to key off the queue item's `recommended_budget` if needed.

### 7. Launch → Do/bulksheet export wiring

Translate launch decisions to their base operations **at queue time** so DoPage's existing export branches handle them (no new export branch except target-type handling):

| `launch_decision` | Queued as | Bid / value |
|---|---|---|
| `LAUNCH_REDUCE_BID` | `REDUCE_BID` | `recommended_bid = launch_recommended_bid` |
| `LAUNCH_NEGATE` | `NEGATE_TERM` (keyword targets) / `STOP_TARGET` (auto-clause / product targets) | — |
| `LAUNCH_HOLD`, `LAUNCH_GRADUATE` | not queueable (no-op) | — |

- Tag the `DoQueueItem` with `source: 'launch'` (optional field) so the PPC change-log can record it as a launch action.
- **Auto-target nuance:** for SP Auto targets (`match_type = 'Automatic'`, `targeting` = loose-match/close-match/substitutes/complements), the reduce updates the auto-targeting **clause bid** (bulksheet Entity = `Product Targeting` with the clause expression) and the negate adds a **negative product target / negative keyword** rather than touching the clause. Confirm/extend the REDUCE_BID and NEGATE branches in `DoPage.tsx` to emit the correct row for this target type.

## Files touched

- **New:** `dashboard-react/src/components/Actions/CollapsibleSection.tsx`; optional `src/pages/sectionQueue.ts` (+ tests).
- **`ActionsPage.tsx`:** wrap the 4 blocks; add the 💰 Budget section; section summaries; section queue-all/unqueue-all; standardize the per-item toggle.
- **`DoPage.tsx`:** ensure budget queue items export; add launch translation handling + auto-target reduce/negate rows.
- **`useDoQueue.tsx`:** add optional `source` field to `DoQueueItem` if used (no API change otherwise).
- Possibly `types.ts` for the optional `DoQueueItem.source`.

## Out of scope (tracked separately)

- The launch decision **grain bug** (auto-targets under-read clicks/orders → wrongly HOLD). Export wiring here is correct regardless; the bug just means fewer REDUCE/NEGATE rows surface until it's fixed.
- Any BigQuery / Cube / engine change.
- Removing/replacing the existing `hideMonitor` toggle or `hierarchy` selector (kept as-is inside 📋 All actions).

## Testing

- Unit (vitest): summary calcs (`$ at stake` per section), section membership filters, launch→operation translation (REDUCE_BID uses `launch_recommended_bid`; NEGATE maps by target type; HOLD/GRADUATE excluded), queued-item id matching for unqueue.
- Component: `CollapsibleSection` collapse/expand + persistence; Queue all / Unqueue all enabled/disabled states.
- Manual (preview): each section collapses with summary; Queue all stages items (visible on Do page); per-item ✕ unqueues; budget decrease + launch reduce/negate produce bulksheet rows.

## Risks / notes

- Auto-target launch reduce/negate bulksheet shape is the trickiest correctness point — verify against a real Amazon SP Auto bulksheet before relying on it.
- Default-collapsed-all means the page opens compact; the summary rows must carry enough signal to decide whether to expand.
