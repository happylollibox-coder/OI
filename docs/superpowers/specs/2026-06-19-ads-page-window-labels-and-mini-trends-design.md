# Ads Page — Window Labels + Per-Row Mini-Trends

**Date:** 2026-06-19
**Page:** `dashboard-react/src/pages/AdsPerformancePage.tsx`
**Status:** Approved design — ready for implementation plan

## Problem

The Ads page has four tables (Campaigns, Best Search Terms, Money Bleeders, Low
Conversion High Spend). Two issues:

1. **Hidden / inconsistent windows.** Each table's primary metrics use a different
   time window, and the window is not shown on the table itself:
   - **Campaigns**, **Best Search Terms**, **Low Conversion** → the **global period
     filter** (defaults to the latest single week).
   - **Money Bleeders** → fixed **4 weeks** (already labeled `(4w)`).

   So "Low Conversion · ≥$10 spend, ≥20 clicks" actually means *≥$10 in the last
   week* by default — surprising and unlabeled. The active period is shown once at
   the top of the page but never restated per table.

2. **No per-row trend.** A row shows a single snapshot number. The user can't tell
   whether a money-draining term is *still* draining or has already tapered off.

## Goals

- Show each table's real time window in its header (no behavior change to the
  windows themselves).
- Add a per-row mini-trend (sparkline) so movement over time is visible at a glance
  — e.g. a Money Bleeder whose weekly spend has dropped to zero.

## Non-Goals

- Changing what window any table computes over (decided: *label the real window*,
  not standardize).
- A per-table 1w/4w toggle (rejected as over-scoped).
- Any new Cube query or backend change.

## Data Reality (verified)

- `data.ads_7d` is loaded by `loadAdsFromCube` (`hooks/useCubeData.ts:188`) using the
  **daily** `Ads.date` dimension over the **last 180 days** (fallback 60 days), limit
  50000, `Ads.spend > 0`. The "campaign-week granularity" comment there is stale —
  rows are **daily** and carry both `date` (daily) and a derived `week_start`.
- Daily granularity is therefore **already in memory** for any window inside ~180
  days. The 4w and default-1w windows both qualify; **no new query is needed**.
- Daily rows only exist on days with `spend > 0`. Missing days are **gap-filled with
  0** when building a series — this is what makes "stopped draining" render as a line
  dropping to the floor.
- `MiniTrend` (`components/MiniTrend.tsx`) is the existing lightweight SVG sparkline:
  `values: number[]`, `color`, `width`, `height`, optional `baseline`. Reused as-is.

## Design

### Part 1 — Window label per table

Add a small window chip to each `Section` header (alongside the existing `count`).

| Table | Label |
|---|---|
| Campaigns | dynamic filter-period label, e.g. `week of Jun 8–14` (reuse existing `periodLabel`) |
| Best Search Terms | same dynamic filter-period label |
| Low Conversion, High Spend | same dynamic filter-period label |
| Money Bleeders | `4w` (unchanged) |

`periodLabel` already exists in `AdsPerformancePage` and resolves the active
filter window (`weekRangeLabelCapped` for weeks mode, etc.). For Money Bleeders the
label is the literal `4w`.

Implementation note: the cleanest insertion is to fold the window text into each
`Section`'s `count` prop (or a dedicated small chip element passed through). Keep
Money Bleeders' existing `(4w)` wording.

### Part 2 — Mini-trend column

A new toggleable **`Trend`** `MeasureDef` added to the column lists, default ON,
appearing in the existing Columns selector menu. Placed immediately **after each
row's name/label column** so it's visible without horizontal scrolling.

Per table (context-appropriate metric; window = the table's own window; **daily**
granularity):

| Table | Line measures | Window | Baseline | Color |
|---|---|---|---|---|
| Money Bleeders | spend / day | last 4w (28 pts) | none | red accent |
| Low Conversion | spend / day | filter period | none | amber accent |
| Best Search Terms | net profit / day (`gross_profit − spend`) | filter period | 0 | emerald accent |
| Campaigns | net profit / day | filter period | 0 | neutral accent |

Net profit per day is derived from existing per-row fields: `gross_profit`
(sales − COGS) minus `spend`.

### Data flow for the sparkline

The parent (`AdsPerformancePage`) owns the daily-series computation; table components
only render.

1. Build a memoized **daily index** from `rawRows` (already daily), keyed at the
   finest grain:
   - campaign level: `campaign_id`
   - term level: `campaign_id \0 search_term`
   Each entry holds per-day buckets of the needed measures (spend, gross_profit).
2. Provide a helper that, given a set of campaign ids (and optional search_term) plus
   a window (start/end dates) and a metric, returns a gap-filled daily `number[]`
   ordered oldest → newest.
3. Compute one `key → number[]` map **per table** with that table's window + metric,
   and pass it (plus color / baseline) into the corresponding table component.
4. Each component renders the `Trend` cell with `<MiniTrend values=... />` when the
   `trend` column is visible; renders nothing when the series is empty.

### Trickiest part — Campaigns dynamic hierarchy

`DynamicHierarchyCampaignsTable` builds nodes at arbitrary levels
(portfolio / family / product / campaign / search_term). A node can span many
campaigns, so its sparkline must sum the daily `rawRows` matching the node's
`campaignIds` (and `search_term` at term level).

- Each node already exposes `campaignIds?: Set<string>` and its `rows`; use those to
  look up daily series from the memoized daily index.
- Compute lazily for **rendered/expanded rows only** and rely on the memoized daily
  index so we never re-scan the ~100k-row `searchTerms` array per node (that array
  was previously a render-freeze source — see existing `termsByCampaign` memo).

## Edge Cases

- **Window older than ~180 days** (user widens global filter far back): daily rows
  may be absent. Fall back to whatever days are available; if none, render no
  sparkline.
- **Single-day / very short window** (default filter is 1 week → 7 daily points):
  acceptable per the agreed rule "sparkline window = table window". Money Bleeders
  (the primary drainer use case) is 4w and gets the full 28-day line.
- **Empty series** (no spend in window): render nothing in the Trend cell.
- **Net profit can be negative**: the 0 baseline makes profit/loss crossings legible;
  `MiniTrend` normalizes min/max so negatives display correctly.

## Performance

- One memoized daily index built per data change; O(rawRows) once.
- Sparklines are SVG (`MiniTrend`), only for visible rows. Hierarchy nodes computed
  lazily for rendered rows. No expected regression beyond current render cost.

## Testing

- Unit (Vitest): the daily-series helper — gap-fill with 0, correct window slicing,
  campaign vs term keying, net-profit derivation, empty-window handling.
- Manual / preview: verify each header shows the right window label; verify a known
  Money Bleeder shows a falling-to-zero spend line; verify Best Terms net-profit line
  with 0 baseline; verify the Trend column toggles via the Columns menu.

## Files Touched (anticipated)

- `dashboard-react/src/pages/AdsPerformancePage.tsx` — column defs (`trend`), window
  labels, daily-series helper + per-table trend maps, prop wiring.
- `dashboard-react/src/pages/AdsPerformancePage.tsx` table components
  (`DynamicHierarchyCampaignsTable`, `HierarchicalTermsTable`, `TermsTable`) — render
  the Trend cell.
- Possibly a small new helper module (e.g. `pages/adsTrend.helpers.ts`) for the
  daily-series builder, with a colocated `.test.ts`.
- Reuse `components/MiniTrend.tsx` (no change expected).
