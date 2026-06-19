# Ads Page — Window Labels + Per-Row Mini-Trends Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** On the Ads page, label each table's real time window and add a per-row mini-trend sparkline (daily for the Campaigns table, weekly for the search-term tables).

**Architecture:** Pure data-shaping logic lives in a new, fully unit-tested helper module (`pages/adsTrend.helpers.ts`). The Campaigns sparkline reuses the already-daily `ads_7d` (campaign-level) data. The three search-term tables need a new weekly Cube dataset (`campaign_search_terms_weekly`) because the existing `campaign_search_terms` collapses all history into one lump per term. The parent page builds per-table `key → number[]` series maps and passes them into the three existing table components, which render the existing `MiniTrend` SVG sparkline. Sparkline window = each table's own window (Campaigns/Best/Low-Conv = global filter period; Money Bleeders = fixed 4w); single-point series render as a flat dot.

**Tech Stack:** React 19 + TypeScript + Vite, Cube.js (`cube/schema/Ads.js`), Vitest for unit tests, Playwright + Claude Preview for visual verification. Reuses `components/MiniTrend.tsx`.

---

## Decisions locked in (from brainstorming)

- **Window labels:** show the real window per table, no behavior change. Filter-driven tables (Campaigns, Best Search Terms, Low Conversion) show the active filter-period label; Money Bleeders keeps `4w`.
- **Sparkline metric (context per table):** Campaigns + Best Terms = **net profit/period**; Money Bleeders + Low Conversion = **spend/period**.
- **Granularity:** Campaigns = **daily** (from `ads_7d`); term tables = **weekly** (new fetch).
- **Window = the table's own window:** Campaigns/Best/Low-Conv follow the global filter (default = latest 1 week); Money Bleeders = fixed 4w. Single-point series are expected at the default 1-week setting for the term tables and must render gracefully.
- **Baseline:** net-profit sparklines draw a 0 baseline; spend sparklines do not.
- **Colors (CSS vars, theme-safe):** drain `var(--color-negative)`, low-conv `var(--color-warning)`, best `var(--color-positive)`, campaigns `var(--color-muted)`.

## File Structure

| File | Responsibility | Change |
|---|---|---|
| `dashboard-react/src/pages/adsTrend.helpers.ts` | Pure window/axis + series-fill + index builders | **Create** |
| `dashboard-react/src/pages/adsTrend.helpers.test.ts` | Unit tests for the above | **Create** |
| `dashboard-react/src/types.ts` | `CampaignSearchTermWeeklyRow` + `DashboardData` field | Modify |
| `dashboard-react/src/hooks/data/datasetTypes.ts` | Add `campaign_search_terms_weekly` to `DatasetName` | Modify |
| `dashboard-react/src/hooks/data/CubeDataProvider.tsx` | Default `[]` for new dataset | Modify |
| `dashboard-react/src/hooks/data/pageDatasets.ts` | Add new dataset to `ads` page list | Modify |
| `dashboard-react/src/hooks/useCubeData.ts` | `loadCampaignSearchTermsWeeklyFromCube` + register loader | Modify |
| `dashboard-react/src/pages/AdsPerformancePage.tsx` | Window labels, `trend` column defs, trend maps, prop wiring | Modify |
| `dashboard-react/src/pages/AdsPerformancePage.tsx` (`TermsTable`, `HierarchicalTermsTable`, `DynamicHierarchyCampaignsTable`) | Render the trend cell | Modify |

All commands run from `dashboard-react/`. Node is at `/Users/ori/.nvm/versions/node/v22.22.1/bin` — prefix with that path or ensure it's on `PATH`.

---

## Task 1: Window label per table header

**Files:**
- Create: `dashboard-react/src/pages/adsTrend.helpers.ts`
- Test: `dashboard-react/src/pages/adsTrend.helpers.test.ts`
- Modify: `dashboard-react/src/pages/AdsPerformancePage.tsx` (Section `count` props at lines ~665, ~741, ~755, ~770)

- [ ] **Step 1: Write the failing test**

Create `dashboard-react/src/pages/adsTrend.helpers.test.ts`:

```ts
import { describe, it, expect } from 'vitest';
import { withWindow } from './adsTrend.helpers';

describe('withWindow', () => {
  it('appends the window label to a count string', () => {
    expect(withWindow('82 active', 'week of Jun 8–14')).toBe('82 active · week of Jun 8–14');
  });
  it('returns the count unchanged when window is empty', () => {
    expect(withWindow('30 terms', '')).toBe('30 terms');
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npx vitest run src/pages/adsTrend.helpers.test.ts`
Expected: FAIL — `withWindow is not a function` / module not found.

- [ ] **Step 3: Write minimal implementation**

Create `dashboard-react/src/pages/adsTrend.helpers.ts`:

```ts
/** Append a window label to a Section count string (e.g. "82 active · week of Jun 8–14"). */
export function withWindow(count: string, windowLabel: string): string {
  return windowLabel ? `${count} · ${windowLabel}` : count;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `npx vitest run src/pages/adsTrend.helpers.test.ts`
Expected: PASS.

- [ ] **Step 5: Wire window labels into the four Section headers**

In `AdsPerformancePage.tsx`, import the helper near the other `./` imports:

```ts
import { withWindow } from './adsTrend.helpers';
```

`periodLabel` already exists in the component (computed ~line 584) and resolves the active filter window. Update each Section's `count`:

- Campaigns (~line 665): `count={withWindow(`${campaigns.length} active`, periodLabel)}`
- Best Search Terms (~line 741): `count={withWindow(`Top ${bestTerms.length} · min ${fM(bestMinSpend)} spend`, periodLabel)}`
- Low Conversion (~line 770): `count={withWindow(`${lowConvHighSpend.length} terms · ≥$10 spend, ≥20 clicks, <3% conv`, periodLabel)}`
- Money Bleeders (~line 755): leave unchanged — it already reads `… spend (4w)`.

- [ ] **Step 6: Verify build + commit**

Run: `npx tsc --noEmit && npx vitest run src/pages/adsTrend.helpers.test.ts`
Expected: no type errors, test PASS.

```bash
git add src/pages/adsTrend.helpers.ts src/pages/adsTrend.helpers.test.ts src/pages/AdsPerformancePage.tsx
git commit -m "feat(ads): label each table's real time window"
```

---

## Task 2: Trend axis + series-fill primitives

**Files:**
- Modify: `dashboard-react/src/pages/adsTrend.helpers.ts`
- Modify: `dashboard-react/src/pages/adsTrend.helpers.test.ts`

- [ ] **Step 1: Write the failing tests**

Append to `adsTrend.helpers.test.ts`:

```ts
import { daysBetween, weeksBetween, fillSeries } from './adsTrend.helpers';

describe('daysBetween', () => {
  it('returns inclusive calendar days oldest→newest', () => {
    expect(daysBetween('2026-06-08', '2026-06-11')).toEqual(
      ['2026-06-08', '2026-06-09', '2026-06-10', '2026-06-11']
    );
  });
  it('returns a single day when start === end', () => {
    expect(daysBetween('2026-06-08', '2026-06-08')).toEqual(['2026-06-08']);
  });
  it('returns [] when start is after end', () => {
    expect(daysBetween('2026-06-10', '2026-06-08')).toEqual([]);
  });
});

describe('weeksBetween', () => {
  it('steps by 7 days inclusive', () => {
    expect(weeksBetween('2026-05-24', '2026-06-14')).toEqual(
      ['2026-05-24', '2026-05-31', '2026-06-07', '2026-06-14']
    );
  });
  it('returns a single week when start === end', () => {
    expect(weeksBetween('2026-06-14', '2026-06-14')).toEqual(['2026-06-14']);
  });
});

describe('fillSeries', () => {
  it('maps each axis key to its bucket value, 0 for gaps', () => {
    const buckets = new Map<string, number>([
      ['2026-06-08', 5],
      ['2026-06-10', 2],
    ]);
    expect(fillSeries(buckets, ['2026-06-08', '2026-06-09', '2026-06-10'])).toEqual([5, 0, 2]);
  });
  it('returns all zeros when buckets is undefined', () => {
    expect(fillSeries(undefined, ['2026-06-08', '2026-06-09'])).toEqual([0, 0]);
  });
});
```

- [ ] **Step 2: Run to verify it fails**

Run: `npx vitest run src/pages/adsTrend.helpers.test.ts`
Expected: FAIL — `daysBetween`/`weeksBetween`/`fillSeries` not exported.

- [ ] **Step 3: Implement**

Append to `adsTrend.helpers.ts`:

```ts
import { addDays } from '../utils';

/** Inclusive list of calendar day ISO strings, oldest→newest. [] if start > end. */
export function daysBetween(startISO: string, endISO: string): string[] {
  const out: string[] = [];
  let d = startISO;
  let guard = 0;
  while (d <= endISO && guard++ < 2000) {
    out.push(d);
    d = addDays(d, 1);
  }
  return out;
}

/** Inclusive list of week-start ISO strings stepping by 7 days, oldest→newest. */
export function weeksBetween(startISO: string, endISO: string): string[] {
  const out: string[] = [];
  let d = startISO;
  let guard = 0;
  while (d <= endISO && guard++ < 520) {
    out.push(d);
    d = addDays(d, 7);
  }
  return out;
}

/** For each axis key, return its bucket value (0 when missing). */
export function fillSeries(
  buckets: Map<string, number> | undefined,
  axis: string[]
): number[] {
  if (!buckets) return axis.map(() => 0);
  return axis.map(k => buckets.get(k) ?? 0);
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `npx vitest run src/pages/adsTrend.helpers.test.ts`
Expected: PASS (all describes).

- [ ] **Step 5: Commit**

```bash
git add src/pages/adsTrend.helpers.ts src/pages/adsTrend.helpers.test.ts
git commit -m "feat(ads): add daysBetween/weeksBetween/fillSeries trend primitives"
```

---

## Task 3: Trend index builders + per-key series

**Files:**
- Modify: `dashboard-react/src/pages/adsTrend.helpers.ts`
- Modify: `dashboard-react/src/pages/adsTrend.helpers.test.ts`

Builds two indexes:
- **Campaign daily** from `ads_7d` rows (campaign-level), keyed by `campaign_id`, bucketed by `date`, holding `{ spend, net }` where `net = (gross_profit ?? sales − cogs) − spend`.
- **Term weekly** from the new `campaign_search_terms_weekly` rows, keyed by `${campaign_id}\0${search_term}`, bucketed by `week_start`, holding `{ spend, net }`.

- [ ] **Step 1: Write the failing tests**

Append to `adsTrend.helpers.test.ts`:

```ts
import { buildCampaignDailyIndex, buildTermWeeklyIndex, seriesFor, TERM_KEY } from './adsTrend.helpers';
import type { Ads7dRow, CampaignSearchTermWeeklyRow } from '../types';

const campRow = (over: Partial<Ads7dRow>): Ads7dRow => ({
  row_type: 'campaign', campaign_id: 'C1', campaign_name: 'c', campaign_type: null,
  search_term: null, spend: 0, orders: 0, clicks: 0, impressions: 0, sales: 0,
  gross_profit: null, cpc: 0, conv_rate: 0, roas: 0, search_terms_count: null, ...over,
});

describe('buildCampaignDailyIndex', () => {
  it('buckets spend and net (gross_profit − spend) by campaign and date', () => {
    const idx = buildCampaignDailyIndex([
      campRow({ campaign_id: 'C1', date: '2026-06-08', spend: 10, gross_profit: 30 }),
      campRow({ campaign_id: 'C1', date: '2026-06-08', spend: 5, gross_profit: 5 }),
      campRow({ campaign_id: 'C2', date: '2026-06-09', spend: 2, gross_profit: 1 }),
    ]);
    expect(idx.get('C1')!.get('2026-06-08')).toEqual({ spend: 15, net: 20 }); // (30-10)+(5-5)=20
    expect(idx.get('C2')!.get('2026-06-09')).toEqual({ spend: 2, net: -1 });
  });
  it('falls back to sales − cogs when gross_profit is null', () => {
    const idx = buildCampaignDailyIndex([
      campRow({ campaign_id: 'C1', date: '2026-06-08', spend: 4, sales: 10, cogs: 3, gross_profit: null }),
    ]);
    expect(idx.get('C1')!.get('2026-06-08')).toEqual({ spend: 4, net: 3 }); // (10-3)-4
  });
});

describe('buildTermWeeklyIndex', () => {
  it('keys by campaign+term and buckets by week_start', () => {
    const rows: CampaignSearchTermWeeklyRow[] = [
      { campaign_id: 'C1', search_term: 'gift', week_start: '2026-06-07', spend: 8, gross_profit: 20 },
      { campaign_id: 'C1', search_term: 'gift', week_start: '2026-06-14', spend: 3, gross_profit: 2 },
    ];
    const idx = buildTermWeeklyIndex(rows);
    const k = TERM_KEY('C1', 'gift');
    expect(idx.get(k)!.get('2026-06-07')).toEqual({ spend: 8, net: 12 });
    expect(idx.get(k)!.get('2026-06-14')).toEqual({ spend: 3, net: -1 });
  });
});

describe('seriesFor', () => {
  it('extracts the spend metric across an axis, gap-filled with 0', () => {
    const idx = buildCampaignDailyIndex([
      campRow({ campaign_id: 'C1', date: '2026-06-08', spend: 10, gross_profit: 30 }),
      campRow({ campaign_id: 'C1', date: '2026-06-10', spend: 4, gross_profit: 0 }),
    ]);
    expect(seriesFor(idx.get('C1'), ['2026-06-08', '2026-06-09', '2026-06-10'], 'spend'))
      .toEqual([10, 0, 4]);
    expect(seriesFor(idx.get('C1'), ['2026-06-08', '2026-06-09', '2026-06-10'], 'net'))
      .toEqual([20, 0, -4]);
  });
  it('returns all zeros for an unknown key', () => {
    expect(seriesFor(undefined, ['2026-06-08'], 'spend')).toEqual([0]);
  });
});
```

- [ ] **Step 2: Run to verify it fails**

Run: `npx vitest run src/pages/adsTrend.helpers.test.ts`
Expected: FAIL — new exports not defined (and `CampaignSearchTermWeeklyRow` type missing — that is added in Task 4; for now the test import will fail to compile, which is the expected failing state).

- [ ] **Step 3: Implement**

Append to `adsTrend.helpers.ts`:

```ts
import type { Ads7dRow, CampaignSearchTermWeeklyRow } from '../types';

export type TrendMetric = 'spend' | 'net';
export interface TrendBucket { spend: number; net: number; }
export type TrendBuckets = Map<string, TrendBucket>;        // dateISO|weekISO -> bucket
export type TrendIndex = Map<string, TrendBuckets>;          // entity key -> buckets

/** Stable key for a (campaign, term) pair. */
export const TERM_KEY = (campaignId: string, searchTerm: string): string =>
  `${campaignId} ${searchTerm}`;

const netOf = (spend: number, grossProfit: number | null | undefined, sales: number, cogs: number): number =>
  (grossProfit != null ? grossProfit : sales - cogs) - spend;

function add(into: TrendBuckets, bucketKey: string, spend: number, net: number): void {
  const cur = into.get(bucketKey) ?? { spend: 0, net: 0 };
  cur.spend += spend;
  cur.net += net;
  into.set(bucketKey, cur);
}

/** Campaign-level daily index from ads_7d rows (rows with a `date`). */
export function buildCampaignDailyIndex(rows: Ads7dRow[]): TrendIndex {
  const idx: TrendIndex = new Map();
  for (const r of rows) {
    if (!r.date || !r.campaign_id) continue;
    let buckets = idx.get(r.campaign_id);
    if (!buckets) { buckets = new Map(); idx.set(r.campaign_id, buckets); }
    add(buckets, r.date, r.spend, netOf(r.spend, r.gross_profit, r.sales, r.cogs ?? 0));
  }
  return idx;
}

/** Term-level weekly index from the campaign_search_terms_weekly dataset. */
export function buildTermWeeklyIndex(rows: CampaignSearchTermWeeklyRow[]): TrendIndex {
  const idx: TrendIndex = new Map();
  for (const r of rows) {
    if (!r.week_start) continue;
    const key = TERM_KEY(r.campaign_id, r.search_term);
    let buckets = idx.get(key);
    if (!buckets) { buckets = new Map(); idx.set(key, buckets); }
    add(buckets, r.week_start, r.spend, (r.gross_profit ?? 0) - r.spend);
  }
  return idx;
}

/** Extract one metric's series across an axis, gap-filled with 0. */
export function seriesFor(buckets: TrendBuckets | undefined, axis: string[], metric: TrendMetric): number[] {
  if (!buckets) return axis.map(() => 0);
  return axis.map(k => buckets.get(k)?.[metric] ?? 0);
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `npx vitest run src/pages/adsTrend.helpers.test.ts`
Expected: still FAILS to compile until Task 4 adds `CampaignSearchTermWeeklyRow`. That is acceptable mid-task — proceed to Task 4, then re-run. (If you prefer green-between-tasks, do Task 4 Step 3 first, then return here.)

- [ ] **Step 5: Commit (after Task 4 makes the type exist and tests pass)**

```bash
git add src/pages/adsTrend.helpers.ts src/pages/adsTrend.helpers.test.ts
git commit -m "feat(ads): add daily/weekly trend index builders + seriesFor"
```

---

## Task 4: New `campaign_search_terms_weekly` Cube dataset

**Files:**
- Modify: `dashboard-react/src/types.ts` (after `CampaignSearchTermRow`, ~line 602; and `DashboardData`, ~line 1214)
- Modify: `dashboard-react/src/hooks/data/datasetTypes.ts` (`DatasetName` union)
- Modify: `dashboard-react/src/hooks/data/CubeDataProvider.tsx` (defaults block, ~line 18)
- Modify: `dashboard-react/src/hooks/data/pageDatasets.ts` (`ads` list, ~line 31)
- Modify: `dashboard-react/src/hooks/useCubeData.ts` (new loader near line 1292; register in `DATASET_LOADERS` near line 2248)
- Modify: `dashboard-react/src/hooks/data/pageDatasets.test.ts`

- [ ] **Step 1: Write the failing test**

Append to `dashboard-react/src/hooks/data/pageDatasets.test.ts` (mirror existing test style in that file):

```ts
import { PAGE_DATASETS } from './pageDatasets';

it('ads page requests the weekly term trend dataset', () => {
  expect(PAGE_DATASETS.ads).toContain('campaign_search_terms_weekly');
});
```

- [ ] **Step 2: Run to verify it fails**

Run: `npx vitest run src/hooks/data/pageDatasets.test.ts`
Expected: FAIL — `ads` list does not contain `campaign_search_terms_weekly`.

- [ ] **Step 3a: Add the row type + DashboardData field** (`types.ts`)

After the `CampaignSearchTermRow` interface (ends ~line 602) add:

```ts
export interface CampaignSearchTermWeeklyRow {
  campaign_id: string;
  search_term: string;
  week_start: string;   // Sunday-aligned ISO date
  spend: number;
  gross_profit: number;  // sales − COGS for that term-week
}
```

In `DashboardData`, next to `campaign_search_terms` (~line 1214):

```ts
  campaign_search_terms_weekly: CampaignSearchTermWeeklyRow[];
```

- [ ] **Step 3b: Extend the `DatasetName` union** (`datasetTypes.ts`)

Add `'campaign_search_terms_weekly'` to the union (e.g. on the `… 'campaign_search_terms'` line):

```ts
  | 'experiment_weekly' | 'experiment_campaigns' | 'campaign_search_terms' | 'campaign_search_terms_weekly'
```

(The default `fallbackFor` returns `[]` for unrecognized names — no change needed there.)

- [ ] **Step 3c: Add the provider default** (`CubeDataProvider.tsx`, ~line 18)

On the line that sets `campaign_search_terms: []` add:

```ts
  campaign_search_terms: [], campaign_search_terms_weekly: [], ads_7d: [], ads_7d_summary: [], holidays: [], experiment_templates: [],
```

- [ ] **Step 3d: Add to the `ads` page dataset list** (`pageDatasets.ts`, ~line 31)

```ts
  ads: ['ads_7d', 'campaign_search_terms', 'campaign_search_terms_weekly', 'coach_decisions', 'experiment_campaigns', 'holidays',
    'keyword_product_map', 'peak', 'sqp_volume_4w', 'sqp_weekly'],
```

- [ ] **Step 3e: Add the loader + register it** (`useCubeData.ts`)

After `loadCampaignSearchTermsFromCube` (ends ~line 1325) add:

```ts
/** Ads → campaign_search_terms_weekly (term-level weekly buckets for sparklines). */
async function loadCampaignSearchTermsWeeklyFromCube(): Promise<CampaignSearchTermWeeklyRow[]> {
  const rows = await cubeLoad({
    measures: ['Ads.spend', 'Ads.grossProfit'],
    dimensions: ['Ads.campaignId', 'Ads.searchTerm'],
    timeDimensions: [{ dimension: 'Ads.date', dateRange: 'Last 90 days', granularity: 'week' }],
    filters: [{ member: 'Ads.spend', operator: 'gt', values: ['0'] }],
    limit: 100000,
  });
  return (rows as Record<string, unknown>[]).map(r => {
    const wk = r['Ads.date.week'] ?? r['Ads.date'];
    return {
      campaign_id: String(r['Ads.campaignId'] ?? ''),
      search_term: r['Ads.searchTerm'] ? String(r['Ads.searchTerm']) : '',
      week_start: wk ? fmtDate(wk) : '',
      spend: Number(r['Ads.spend'] ?? 0),
      gross_profit: r['Ads.grossProfit'] != null ? Number(r['Ads.grossProfit']) : 0,
    };
  });
}
```

Import the new type at the top of `useCubeData.ts` (the type-import block that already imports `CampaignSearchTermRow`, ~line 18):

```ts
  CampaignSearchTermRow,
  CampaignSearchTermWeeklyRow,
```

Register in `DATASET_LOADERS` next to `campaign_search_terms` (~line 2248):

```ts
  campaign_search_terms: loadCampaignSearchTermsFromCube,
  campaign_search_terms_weekly: loadCampaignSearchTermsWeeklyFromCube,
```

> Note: `fmtDate` and `cubeLoad` are existing helpers in this file (used by `mapAdsRow` / `loadCampaignSearchTermsFromCube`). Reuse them; do not redefine.

- [ ] **Step 4: Run tests + typecheck**

Run: `npx vitest run src/hooks/data/pageDatasets.test.ts src/pages/adsTrend.helpers.test.ts && npx tsc --noEmit`
Expected: both test files PASS (Task 3's tests now compile because the type exists), no type errors.

- [ ] **Step 5: Commit (covers Task 3 + Task 4)**

```bash
git add src/types.ts src/hooks/data/datasetTypes.ts src/hooks/data/CubeDataProvider.tsx src/hooks/data/pageDatasets.ts src/hooks/data/pageDatasets.test.ts src/hooks/useCubeData.ts src/pages/adsTrend.helpers.ts src/pages/adsTrend.helpers.test.ts
git commit -m "feat(ads): add campaign_search_terms_weekly dataset + trend index builders"
```

---

## Task 5: Parent wiring — trend column defs, indexes, windows, and per-table series maps

**Files:**
- Modify: `dashboard-react/src/pages/AdsPerformancePage.tsx`

This task adds the data; Tasks 6–8 render it. No new test (logic is the already-tested helpers; output verified in preview at Task 9).

- [ ] **Step 1: Import the helpers + MiniTrend**

Near the top imports of `AdsPerformancePage.tsx`:

```ts
import { withWindow, buildCampaignDailyIndex, buildTermWeeklyIndex, seriesFor, TERM_KEY, daysBetween, weeksBetween } from './adsTrend.helpers';
import { MiniTrend } from '../components/MiniTrend';
```

(`withWindow` is already imported from Task 1 — merge into one import line, don't duplicate.)

- [ ] **Step 2: Add the `trend` column to the three column defs**

Insert a `trend` `MeasureDef` immediately after the identifier column in each array:

- `ADS_TERMS_COLUMNS` (after `{ id: 'search_term', … }`, ~line 42):
  `{ id: 'trend', label: 'Trend', tip: 'Weekly trend over this table’s window', group: 'Info', defaultVisible: true },`
- `ADS_HIER_COLUMNS` (after `{ id: 'label', … }`, ~line 71):
  `{ id: 'trend', label: 'Trend', tip: 'Weekly net-profit trend over this table’s window', group: 'Info', defaultVisible: true },`
- `ADS_CAMP_COLUMNS` (after `{ id: 'label', … }`, ~line 100):
  `{ id: 'trend', label: 'Trend', tip: 'Daily net-profit trend over this table’s window', group: 'Info', defaultVisible: true },`

- [ ] **Step 3: Build indexes (memoized)**

After `rawRows` / `weeks4w` are defined (~line 208) add:

```ts
const campaignDailyIndex = useMemo(() => buildCampaignDailyIndex(rawRows), [rawRows]);
const termWeeklyIndex = useMemo(
  () => buildTermWeeklyIndex(data.campaign_search_terms_weekly || []),
  [data.campaign_search_terms_weekly]
);
```

- [ ] **Step 4: Compute the per-table window axes**

After `filteredRawRows` is defined (~line 252) add:

```ts
// Daily axis for the Campaigns table = the filtered period's calendar days.
const campaignDayAxis = useMemo(() => {
  const dates = [...new Set(filteredRawRows.map(r => r.date || '').filter(Boolean))].sort();
  if (!dates.length) return [];
  return daysBetween(dates[0], dates[dates.length - 1]);
}, [filteredRawRows]);

// Weekly axis for filter-driven term tables = the weeks spanned by the filtered period.
const termFilterWeekAxis = useMemo(() => {
  const ws = [...new Set(filteredRawRows.map(r => r.week_start || '').filter(Boolean))].sort();
  if (!ws.length) return [];
  return weeksBetween(ws[0], ws[ws.length - 1]);
}, [filteredRawRows]);

// Weekly axis for Money Bleeders = the fixed 4-week window.
const drainerWeekAxis = useMemo(() => {
  const ws = [...weeks4w].sort();
  if (!ws.length) return [];
  return weeksBetween(ws[0], ws[ws.length - 1]);
}, [weeks4w]);
```

- [ ] **Step 5: Build per-campaign daily series map (for the Campaigns table)**

```ts
// campaign_id -> daily net-profit series across the campaign day axis.
const campaignTrendByCampaignId = useMemo(() => {
  const m = new Map<string, number[]>();
  if (!campaignDayAxis.length) return m;
  for (const [cid, buckets] of campaignDailyIndex) {
    m.set(cid, seriesFor(buckets, campaignDayAxis, 'net'));
  }
  return m;
}, [campaignDailyIndex, campaignDayAxis]);
```

- [ ] **Step 6: Build per-term weekly series maps (Best / Bleeders / Low-Conv)**

```ts
const bestTrendByKey = useMemo(() => {
  const m = new Map<string, number[]>();
  for (const t of bestTerms) {
    const k = TERM_KEY(t.campaign_id, t.search_term || '');
    m.set(k, seriesFor(termWeeklyIndex.get(k), termFilterWeekAxis, 'net'));
  }
  return m;
}, [bestTerms, termWeeklyIndex, termFilterWeekAxis]);

const drainerTrendByKey = useMemo(() => {
  const m = new Map<string, number[]>();
  for (const t of drainers) {
    const k = TERM_KEY(t.campaign_id, t.search_term || '');
    m.set(k, seriesFor(termWeeklyIndex.get(k), drainerWeekAxis, 'spend'));
  }
  return m;
}, [drainers, termWeeklyIndex, drainerWeekAxis]);

const lowConvTrendByKey = useMemo(() => {
  const m = new Map<string, number[]>();
  for (const t of lowConvHighSpend) {
    const k = TERM_KEY(t.campaign_id, t.search_term || '');
    m.set(k, seriesFor(termWeeklyIndex.get(k), termFilterWeekAxis, 'spend'));
  }
  return m;
}, [lowConvHighSpend, termWeeklyIndex, termFilterWeekAxis]);
```

(These reference `bestTerms`, `drainers`, `lowConvHighSpend`, defined earlier ~lines 502–520, so place this block after them.)

- [ ] **Step 7: Typecheck + commit**

Run: `npx tsc --noEmit`
Expected: no errors. (`MiniTrend` import is unused until Tasks 6–8 — if your TS config flags unused imports, add it in Task 6 instead. The plan assumes standard Vite config which does not error on unused imports during `tsc --noEmit`; if it does, move the `MiniTrend` import to Task 6 Step 1.)

```bash
git add src/pages/AdsPerformancePage.tsx
git commit -m "feat(ads): build trend column defs, indexes, window axes, and series maps"
```

---

## Task 6: Render the trend cell in `TermsTable` (Money Bleeders + Low Conversion)

**Files:**
- Modify: `dashboard-react/src/pages/AdsPerformancePage.tsx` (`TermsTable`, ~line 1487; its two call sites ~lines 765 and 778)

`TermsTable` is shared by Money Bleeders (`highlight='drain'`, spend metric, 4w axis, red) and Low Conversion (`highlight='warn'`, spend metric, filter axis, amber). The parent passes the right `trendByKey` + color per call site.

- [ ] **Step 1: Add a small shared trend-cell component**

Just above `function TermsTable(` add:

```tsx
/** Renders a row's mini-trend, handling empty/single-point series. */
function TrendCell({ series, color, baseline }: { series?: number[]; color: string; baseline?: number }) {
  if (!series || series.length === 0) {
    return <td className="px-3 py-2 text-faint text-[10px]">—</td>;
  }
  const vals = series.length === 1 ? [series[0], series[0]] : series;
  return (
    <td className="px-3 py-2">
      <MiniTrend values={vals} color={color} width={64} height={22} baseline={baseline} />
    </td>
  );
}
```

- [ ] **Step 2: Extend the `TermsTable` signature + non-sortable header**

Update the props (~line 1487) to add `trendByKey`, `trendColor`, `trendBaseline`:

```ts
function TermsTable({ terms, highlight, visibleCols, sqpVolume = {}, sqpDetails = {}, getSignal, trendByKey, trendColor, trendBaseline }: { terms: Ads7dRow[]; highlight: 'best' | 'drain' | 'warn'; visibleCols: MeasureDef[]; sqpVolume?: Record<string, number>; sqpDetails?: Record<string, any>; getSignal: (m: any, node?: any) => { type: keyof typeof ACTION_META; reason: string }[]; trendByKey?: Map<string, number[]>; trendColor?: string; trendBaseline?: number }) {
```

In the header map (~line 1497), special-case `trend` so it is not a sort button:

```tsx
{cols.map(c => (
  c.id === 'trend'
    ? <Th key="trend" right={false} tip={c.tip}>{c.label}</Th>
    : <SortTh key={c.id} k={c.id} sort={s.sort} toggle={s.toggle} right={!['search_term', 'campaign_name', 'action'].includes(c.id)} tip={c.tip || (c.id === 'sqp_volume' ? volTip : undefined)}>{c.label}</SortTh>
))}
```

- [ ] **Step 3: Add the `trend` cell to the `cells` record**

Inside the row map, where `cells` is built (~line 1507), add a `trend` entry (anywhere in the object literal):

```tsx
trend: <TrendCell key="trend" series={trendByKey?.get(TERM_KEY(t.campaign_id, t.search_term || ''))} color={trendColor || 'var(--color-muted)'} baseline={trendBaseline} />,
```

- [ ] **Step 4: Pass props at both call sites**

Money Bleeders (~line 765):

```tsx
<TermsTable terms={drainers} highlight="drain" visibleCols={visibleAdsTermsCols} sqpVolume={sqpVolumeByTerm} sqpDetails={sqpDetailsByTerm} getSignal={getSignal} trendByKey={drainerTrendByKey} trendColor="var(--color-negative)" />
```

Low Conversion (~line 778):

```tsx
<TermsTable terms={lowConvHighSpend} highlight="warn" visibleCols={visibleAdsTermsCols} sqpVolume={sqpVolumeByTerm} sqpDetails={sqpDetailsByTerm} getSignal={getSignal} trendByKey={lowConvTrendByKey} trendColor="var(--color-warning)" />
```

- [ ] **Step 5: Typecheck + verify in preview**

Run: `npx tsc --noEmit`
Then start the dev server (Cube on :4000 + Vite) and verify per the project's run skill. With Claude Preview: load the Ads page, `preview_snapshot` to confirm a `Trend` column appears in Money Bleeders and Low Conversion, and `preview_screenshot` to confirm sparklines render (4 weekly points on a drainer; spend dropping where it stopped).

- [ ] **Step 6: Commit**

```bash
git add src/pages/AdsPerformancePage.tsx
git commit -m "feat(ads): render mini-trend in Money Bleeders + Low Conversion tables"
```

---

## Task 7: Render the trend cell in `HierarchicalTermsTable` (Best Search Terms)

**Files:**
- Modify: `dashboard-react/src/pages/AdsPerformancePage.tsx` (`HierarchicalTermsTable`, ~line 1268; call site ~line 751)

Best Terms uses net profit, the filter week axis, emerald, with a 0 baseline. The leaf rows are search terms (`t`); intermediate group rows (product / campaign) should leave the trend cell blank (no single term key).

- [ ] **Step 1: Extend the signature + header**

Add `trendByKey`, `trendColor`, `trendBaseline` to the props (~line 1268), mirroring Task 6's prop block.

In the header map (~line 1339), special-case `trend` to a non-sortable `Th` (same pattern as Task 6 Step 2; `right={false}`).

- [ ] **Step 2: Render the cell only at the term (leaf) level**

In the leaf-term row's `cols.map(c => { … })` (the deepest level, ~line 1462), add a branch that returns a `TrendCell` for `c.id === 'trend'`:

```tsx
if (c.id === 'trend') return (
  <TrendCell key="trend" series={trendByKey?.get(TERM_KEY(t.campaign_id, t.search_term || ''))} color={trendColor || 'var(--color-positive)'} baseline={trendBaseline} />
);
```

For the intermediate group levels (total row ~line 1383, product row ~line 1425), add a blank cell so columns stay aligned:

```tsx
if (c.id === 'trend') return <td key="trend" className="px-3 py-1" />;
```

- [ ] **Step 3: Pass props at the call site** (~line 751)

```tsx
<HierarchicalTermsTable terms={bestTerms} highlight="best" sqpVolume={sqpVolumeByTerm} sqpDetails={sqpDetailsByTerm} sqpWeekly={data.sqp_weekly || []} keywordProductMap={data.keyword_product_map || []} visibleCols={visibleAdsHierCols} getSignal={getSignal} trendByKey={bestTrendByKey} trendColor="var(--color-positive)" trendBaseline={0} />
```

- [ ] **Step 4: Typecheck + verify in preview**

Run: `npx tsc --noEmit`
In Claude Preview: confirm the `Trend` column shows on Best Search Terms leaf rows with a net-profit line + 0 baseline, and group rows show a blank trend cell (no misalignment). `preview_screenshot`.

- [ ] **Step 5: Commit**

```bash
git add src/pages/AdsPerformancePage.tsx
git commit -m "feat(ads): render net-profit mini-trend in Best Search Terms table"
```

---

## Task 8: Render the trend cell in `DynamicHierarchyCampaignsTable` (Campaigns)

**Files:**
- Modify: `dashboard-react/src/pages/AdsPerformancePage.tsx` (`DynamicHierarchyCampaignsTable`, ~line 786; call site is the Campaigns Section body ~line 705+)

Campaigns is a dynamic tree. Each node aggregates one or more campaigns via `campaignIds`. The trend = elementwise sum of each campaign's daily net series (all share `campaignDayAxis`, so arrays are equal length). Search-term-level nodes get a blank trend cell (no per-term daily data — that grain lives in the term tables).

- [ ] **Step 1: Extend the signature + header**

Add to the props block (~line 801): `trendByCampaignId?: Map<string, number[]>; trendAxisLen?: number; trendColor?: string;`

In the header render (~line 1173), special-case `trend` to a non-sortable `Th`:

```tsx
{visibleCols.map(c => (
  c.id === 'trend'
    ? <Th key="trend" right={false} tip={c.tip}>{c.label}</Th>
    : (/* existing Th/SortTh for other columns */)
))}
```

(Preserve the existing label logic for `c.id === 'label'`.)

- [ ] **Step 2: Add a node→series helper inside the component**

After `termsByCampaign` memo (~line 853) add:

```tsx
const nodeTrend = (node: Node): number[] | undefined => {
  if (node.level === 'search_term') return undefined; // per-term daily not available
  if (!trendAxisLen || !trendByCampaignId) return undefined;
  const cids = node.campaignIds ?? new Set(node.rows.map(r => r.campaign_id));
  const sum = new Array(trendAxisLen).fill(0);
  let any = false;
  for (const cid of cids) {
    const s = trendByCampaignId.get(cid);
    if (!s) continue;
    any = true;
    for (let i = 0; i < sum.length && i < s.length; i++) sum[i] += s[i];
  }
  return any ? sum : undefined;
};
```

- [ ] **Step 3: Render the trend cell in each node row**

In the node-row `visibleCols.map(c => { … })` blocks (parent row ~line 1044, and the nested rows ~line 1101 and ~line 1147), add a `trend` branch before the default `<td>` return. Example for the main block (~line 1044):

```tsx
if (c.id === 'trend') {
  const s = nodeTrend(node);
  return <TrendCell key="trend" series={s} color={trendColor || 'var(--color-muted)'} baseline={0} />;
}
```

For the nested term rows (~line 1147) where the entity is a search term, render a blank cell:

```tsx
if (col.id === 'trend') return <td key="trend" className="px-3 py-1" />;
```

(`TrendCell` is defined in Task 6 Step 1 in the same file — reuse it.)

- [ ] **Step 4: Pass props at the call site**

Find where `DynamicHierarchyCampaignsTable` is rendered (inside the Campaigns Section, after the hierarchy chips ~line 705+) and add:

```tsx
trendByCampaignId={campaignTrendByCampaignId}
trendAxisLen={campaignDayAxis.length}
trendColor="var(--color-muted)"
```

- [ ] **Step 5: Typecheck + verify in preview**

Run: `npx tsc --noEmit`
In Claude Preview: confirm Campaigns rows (portfolio/campaign/product) show a daily net-profit sparkline with a 0 baseline; expanded search-term sub-rows show a blank trend cell; no console errors; the table still scrolls/expands smoothly (no render freeze).

- [ ] **Step 6: Commit**

```bash
git add src/pages/AdsPerformancePage.tsx
git commit -m "feat(ads): render daily net-profit mini-trend in Campaigns hierarchy table"
```

---

## Task 9: Full verification + column-persistence check

**Files:** none (verification only) — small follow-up edit only if needed.

- [ ] **Step 1: Run the full unit + type suite**

Run: `npx vitest run && npx tsc --noEmit`
Expected: all green.

- [ ] **Step 2: Confirm the new `Trend` column is visible for existing users**

Open the Columns menu on each table in preview. The `trend` `MeasureDef` has `defaultVisible: true`, but `useMeasureSelection` persists prior selections in localStorage. Verify that a returning user (existing localStorage without `trend`) still sees the option in the Columns menu and that it can be enabled. If `useMeasureSelection` does NOT auto-include new `defaultVisible` columns, note it — the column is still reachable via the menu, which satisfies the requirement; no code change required unless the user wants it ON by default for everyone (out of scope here).

- [ ] **Step 3: End-to-end visual proof**

In Claude Preview on the Ads page:
- Each Section header shows its window (`week of …` for Campaigns/Best/Low-Conv; `(4w)` for Money Bleeders).
- Money Bleeders: a known drainer shows a 4-point weekly spend line dropping toward 0 where it stopped.
- Best Terms: net-profit weekly line with 0 baseline.
- Campaigns: daily net-profit line over the filtered period.
- `preview_console_logs` shows no new errors; `preview_network` shows the `campaign_search_terms_weekly` Cube request returning rows.
Capture `preview_screenshot`s for the user.

- [ ] **Step 4: Final commit (if any verification fixes were needed)**

```bash
git add -A
git commit -m "test(ads): verify window labels + mini-trends end-to-end"
```

---

## Self-Review

**Spec coverage:**
- Window label per table → Task 1. ✔
- Mini-trend column, context metric per table → Tasks 5–8 (Campaigns net/daily, Best net/weekly, Money Bleeders spend/weekly, Low-Conv spend/weekly). ✔
- Window = table window → axes in Task 5 Step 4 (filter days/weeks; 4w for bleeders). ✔
- Daily campaigns / weekly terms; new weekly fetch → Task 4. ✔
- Single-point graceful render → `TrendCell` (Task 6 Step 1). ✔
- 0 baseline for net-profit lines → Tasks 7–8. ✔
- Theme-safe colors → CSS vars at call sites. ✔
- Performance (no node rescans / lazy node trend) → Task 8 `nodeTrend` uses memoized `campaignTrendByCampaignId` + `node.campaignIds`. ✔

**Placeholder scan:** No TBD/TODO; every code step shows real code. ✔

**Type consistency:** `TERM_KEY`, `TrendIndex`, `TrendBuckets`, `seriesFor`, `buildCampaignDailyIndex`, `buildTermWeeklyIndex`, `CampaignSearchTermWeeklyRow`, `TrendCell` names are used identically across tasks. The `trend` `MeasureDef` id is `'trend'` everywhere. ✔

**Known ordering note:** Task 3's tests depend on the `CampaignSearchTermWeeklyRow` type added in Task 4 Step 3a; the plan calls this out and commits them together (Task 4 Step 5). If you want green-between-commits, do Task 4 Step 3a before Task 3 Step 4.
