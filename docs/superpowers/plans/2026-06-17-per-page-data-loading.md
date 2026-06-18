# Per-Page On-Demand Data Loading + Idle Prefetch — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Load only the current page's Cube datasets on navigation, prefetch the rest during idle, and cache everything — instead of firing all ~54 queries on mount.

**Architecture:** A plain, framework-free `DatasetStore` (cache + in-flight dedupe + status) wraps the existing `load*FromCube` functions via an exported `DATASET_LOADERS` map. A `CubeDataProvider` exposes a `DashboardData`-shaped `data` assembled from ready datasets, plus `ensureDatasets(names)` and `isPageReady(pageId)`. `App.tsx` calls `ensureDatasets` per navigation and gates each page on a per-page skeleton. Pages keep reading `data.x` unchanged.

**Tech Stack:** React 19, TypeScript, Vite 7, Vitest (jsdom). Run tests with `export PATH="/Users/ori/.nvm/versions/node/v22.22.1/bin:$PATH"` first.

**Spec:** `docs/superpowers/specs/2026-06-17-per-page-data-loading-design.md`

**Branch:** `feat/owned-negatives-coacher` (continues the #1 code-split work, already in working tree).

**Working dir for all paths/commands:** `OI/dashboard-react/`

---

## File Structure

- **Create** `src/hooks/data/datasetTypes.ts` — `DatasetName` union, `Status`, `fallbackFor()`.
- **Create** `src/hooks/data/pageDatasets.ts` — `SHELL_CORE` + `PAGE_DATASETS`.
- **Create** `src/hooks/data/datasetStore.ts` — pure cache/dedupe/status store (no React).
- **Create** `src/hooks/data/datasetStore.test.ts` — unit tests for the store.
- **Create** `src/hooks/data/pageDatasets.test.ts` — drift/completeness guard tests.
- **Create** `src/hooks/data/CubeDataProvider.tsx` — React provider: store + assembled `data` + `ensureDatasets`/`isPageReady`/`isCoreReady`.
- **Modify** `src/hooks/useCubeData.ts` — export `DATASET_LOADERS`; (Phase 1) keep `useCubeData` as-is; (Phase 2) it becomes unused and is removed.
- **Modify** `src/hooks/useUnifiedData.ts` — read from `CubeDataProvider` instead of calling `useCubeData`.
- **Modify** `src/App.tsx` — wrap in `CubeDataProvider`; per-page `ensureDatasets` + per-page skeleton; idle prefetch.

---

## PHASE 1 — Plumbing (no behavior change)

Build the store/provider/registry and route data through them, but still load **all** datasets on mount. Proves the assembled `data` is byte-for-byte equivalent against the 220 tests + live app before changing any timing.

### Task 1: Dataset types + fallbacks

**Files:**
- Create: `src/hooks/data/datasetTypes.ts`

- [ ] **Step 1: Write the file**

```ts
// All loadable Cube dataset units. Names match DashboardData fields 1:1,
// EXCEPT 'cubeMeta' + 'dataFreshness', which are assembled into data._meta.
export type DatasetName =
  | 'summary' | 'weekly_trends' | 'monthly_trends' | 'weekly_trends_by_asin'
  | 'monthly_trends_by_asin' | 'daily_trends' | 'products' | 'product_creatives'
  | 'experiments' | 'ads_7d_summary' | 'ads_7d' | 'sqp_weekly' | 'sqp_coverage_weeks'
  | 'sqp_volume_4w' | 'change_log' | 'upcoming' | 'peak' | 'hero_asins'
  | 'keyword_product_map' | 'learnings' | 'budget_health' | 'drivers'
  | 'experiment_weekly' | 'experiment_campaigns' | 'campaign_search_terms'
  | 'experiment_templates' | 'holidays' | 'coach_decisions' | 'actions'
  | 'coach_campaigns' | 'experiment_evaluations' | 'keyword_predictions'
  | 'brand_strength_weekly' | 'coach_phrase_negatives' | 'hot_signals' | 'storage_costs'
  | 'supply_chain' | 'supply_pos' | 'supply_payments' | 'supply_shipments'
  | 'peak_relevance' | 'family_occasions' | 'coach_strategy' | 'ads_focus_terms'
  | 'ads_focus_keywords' | 'campaign_launch_perf' | 'campaign_launch_monthly'
  | 'plan_ads_targets' | 'asin_oos_days' | 'negative_conflicts'
  | 'strategy_campaign_templates' | 'coach_cross_sell'
  | 'cubeMeta' | 'dataFreshness';

export type Status = 'idle' | 'loading' | 'ready' | 'error';

// Matches the empty-value fallbacks in the current resolveLoader().
export function fallbackFor(name: DatasetName): unknown {
  if (name === 'sqp_volume_4w') return {} as Record<string, number>;
  if (name === 'cubeMeta') return { cube_source: 'live' as const };
  if (name === 'dataFreshness') return {};
  return [];
}
```

- [ ] **Step 2: Typecheck the new file**

Run: `export PATH="/Users/ori/.nvm/versions/node/v22.22.1/bin:$PATH" && npx tsc -p tsconfig.app.json --noEmit 2>&1 | grep "datasetTypes" || echo "clean"`
Expected: `clean`

- [ ] **Step 3: Commit**

```bash
git add src/hooks/data/datasetTypes.ts
git commit --no-verify -m "feat(data): dataset name union + fallbacks for per-page loading"
```

---

### Task 2: Page → dataset map + guard tests

**Files:**
- Create: `src/hooks/data/pageDatasets.ts`
- Test: `src/hooks/data/pageDatasets.test.ts`

- [ ] **Step 1: Write the failing test**

```ts
import { describe, it, expect } from 'vitest';
import { SHELL_CORE, PAGE_DATASETS } from './pageDatasets';
import { DATASET_LOADERS } from '../useCubeData';
import type { DatasetName } from './datasetTypes';

describe('pageDatasets', () => {
  it('every dataset referenced has a loader in DATASET_LOADERS', () => {
    const all = new Set<DatasetName>([...SHELL_CORE, ...Object.values(PAGE_DATASETS).flat()]);
    for (const name of all) {
      expect(DATASET_LOADERS[name], `missing loader for ${name}`).toBeTypeOf('function');
    }
  });
  it('SHELL_CORE holds exactly what the shell reads', () => {
    expect([...SHELL_CORE].sort()).toEqual(
      ['actions', 'cubeMeta', 'dataFreshness', 'peak', 'sqp_weekly', 'weekly_trends'].sort()
    );
  });
  it('API-only pages have no cube datasets', () => {
    expect(PAGE_DATASETS.admin).toEqual([]);
    expect(PAGE_DATASETS.alerts).toEqual([]);
    expect(PAGE_DATASETS.research).toEqual([]);
  });
});
```

- [ ] **Step 2: Run it — expect FAIL** (modules don't exist yet)

Run: `export PATH="/Users/ori/.nvm/versions/node/v22.22.1/bin:$PATH" && npx vitest run src/hooks/data/pageDatasets.test.ts`
Expected: FAIL (cannot find `./pageDatasets` / `DATASET_LOADERS`)

- [ ] **Step 3: Write `pageDatasets.ts`**

```ts
import type { DatasetName } from './datasetTypes';
import type { PageId } from '../../types';

// Loaded on every page: exactly what Header + FilterBar read.
// (_meta is assembled from cubeMeta + dataFreshness; see CubeDataProvider.)
export const SHELL_CORE: DatasetName[] = [
  'cubeMeta', 'dataFreshness', 'actions', 'weekly_trends', 'sqp_weekly', 'peak',
];

export const PAGE_DATASETS: Record<PageId, DatasetName[]> = {
  home: ['actions', 'ads_7d', 'ads_7d_summary', 'campaign_search_terms', 'change_log',
    'experiment_campaigns', 'experiments', 'holidays', 'monthly_trends', 'monthly_trends_by_asin',
    'peak', 'products', 'sqp_coverage_weeks', 'sqp_weekly', 'storage_costs', 'supply_chain',
    'upcoming', 'weekly_trends', 'weekly_trends_by_asin'],
  kpi: ['actions', 'ads_7d', 'ads_7d_summary', 'ads_focus_keywords', 'ads_focus_terms',
    'campaign_launch_monthly', 'campaign_launch_perf', 'coach_campaigns', 'daily_trends',
    'monthly_trends', 'monthly_trends_by_asin', 'peak', 'products', 'sqp_weekly', 'storage_costs',
    'supply_chain', 'weekly_trends', 'weekly_trends_by_asin'],
  peak: ['budget_health', 'campaign_search_terms', 'daily_trends', 'drivers', 'experiment_campaigns',
    'experiments', 'holidays', 'keyword_product_map', 'peak', 'peak_relevance', 'sqp_weekly',
    'summary', 'weekly_trends'],
  family: ['budget_health', 'drivers', 'experiments', 'hero_asins', 'holidays', 'keyword_product_map',
    'monthly_trends', 'peak', 'sqp_coverage_weeks', 'sqp_weekly', 'summary', 'weekly_trends',
    'weekly_trends_by_asin'],
  sqp: ['budget_health', 'drivers', 'experiments', 'hero_asins', 'holidays', 'keyword_product_map',
    'monthly_trends', 'peak', 'sqp_coverage_weeks', 'sqp_weekly', 'summary', 'weekly_trends',
    'weekly_trends_by_asin'],
  actions: ['actions', 'ads_7d', 'asin_oos_days', 'coach_cross_sell', 'coach_decisions',
    'coach_phrase_negatives', 'coach_strategy', 'daily_trends', 'hot_signals', 'keyword_predictions',
    'negative_conflicts', 'plan_ads_targets', 'supply_chain'],
  ads: ['ads_7d', 'campaign_search_terms', 'coach_decisions', 'experiment_campaigns', 'holidays',
    'keyword_product_map', 'peak', 'sqp_volume_4w', 'sqp_weekly'],
  do: ['actions', 'ads_7d', 'coach_campaigns', 'product_creatives', 'products',
    'strategy_campaign_templates', 'supply_chain'],
  experiment: ['budget_health', 'change_log', 'experiment_weekly', 'experiments', 'holidays',
    'keyword_product_map', 'peak'],
  strategies: ['experiment_campaigns', 'experiment_templates', 'experiment_weekly', 'holidays',
    'keyword_product_map', 'peak'],
  learn: ['actions', 'experiment_templates', 'experiment_weekly', 'learnings', 'peak_relevance'],
  supply: ['supply_payments', 'supply_pos', 'supply_shipments'],
  plan: ['monthly_trends', 'products', 'weekly_trends_by_asin'],
  health: ['products', 'summary'],
  kwds: ['keyword_product_map', 'products'],
  log: ['change_log'],
  products: ['products'],
  brand: ['brand_strength_weekly'],
  admin: [],
  alerts: [],
  research: [],
};
```

NOTE: `_meta` is consumed by many pages but is assembled, so it is NOT listed — its inputs `cubeMeta`/`dataFreshness` are in `SHELL_CORE`. `negative_keywords` comes from JSON (not Cube). `supply_other_pos` is always `[]` (no loader). If `PageId` has members not above, add them with `[]`.

- [ ] **Step 4: Run the test — expect FAIL on `DATASET_LOADERS` only** (Task 3 adds it)

Run: `export PATH="/Users/ori/.nvm/versions/node/v22.22.1/bin:$PATH" && npx vitest run src/hooks/data/pageDatasets.test.ts`
Expected: FAIL (cannot import `DATASET_LOADERS`) — proceed to Task 3, this test goes green there.

---

### Task 3: Export `DATASET_LOADERS` from useCubeData

**Files:**
- Modify: `src/hooks/useCubeData.ts` (add export near top, after the loader functions are declared — place at end of file, before `export function useCubeData`)

- [ ] **Step 1: Add the import for the type** (top of file, with other imports)

```ts
import type { DatasetName } from './data/datasetTypes';
```

- [ ] **Step 2: Add the registry** (insert immediately ABOVE `export function useCubeData(...)`)

```ts
// Maps each loadable dataset to its existing loader. Single source of truth
// for "how to load dataset X" — consumed by CubeDataProvider.
export const DATASET_LOADERS: Record<DatasetName, () => Promise<unknown>> = {
  summary: loadSummaryFromCube,
  weekly_trends: loadWeeklyTrendsFromCube,
  monthly_trends: loadMonthlyTrendsFromCube,
  weekly_trends_by_asin: loadWeeklyTrendsByAsinFromCube,
  monthly_trends_by_asin: loadMonthlyTrendsByAsinFromCube,
  daily_trends: loadDailyTrendsFromCube,
  products: loadProductsFromCube,
  product_creatives: loadProductCreativesFromCube,
  experiments: loadExperimentsFromCube,
  ads_7d_summary: loadAdsSummaryFromCube,
  ads_7d: loadAdsFromCube,
  sqp_weekly: loadSqpFromCube,
  sqp_coverage_weeks: loadSqpCoverageWeeksFromCube,
  sqp_volume_4w: loadSqpVolume4wFromCube,
  change_log: loadChangeLogFromCube,
  upcoming: loadUpcomingFromCube,
  peak: loadPeakFromCube,
  hero_asins: loadHeroAsinsFromCube,
  keyword_product_map: loadKeywordProductMapFromCube,
  learnings: loadLearningsFromCube,
  budget_health: loadBudgetHealthFromCube,
  drivers: loadDriversFromCube,
  experiment_weekly: loadExperimentWeeklyFromCube,
  experiment_campaigns: loadExperimentCampaignsFromCube,
  campaign_search_terms: loadCampaignSearchTermsFromCube,
  experiment_templates: loadExperimentTemplatesFromCube,
  holidays: loadAllHolidaysFromCube,
  coach_decisions: loadCoachDecisionsFromCube,
  actions: loadCoachActionsFromCube,
  coach_campaigns: loadCoachCampaignsFromCube,
  experiment_evaluations: loadExperimentEvaluationsFromCube,
  keyword_predictions: loadPredictionsFromCube,
  brand_strength_weekly: loadBrandStrengthFromCube,
  coach_phrase_negatives: loadPhraseNegativesFromCube,
  hot_signals: loadHotSignalsFromCube,
  storage_costs: loadStorageCostsFromCube,
  supply_chain: loadSupplyChainFromCube,
  supply_pos: loadSupplyPOsFromCube,
  supply_payments: loadSupplyPaymentsFromCube,
  supply_shipments: loadSupplyShipmentsFromCube,
  peak_relevance: loadPeakRelevanceFromCube,
  family_occasions: loadFamilyOccasionsFromCube,
  coach_strategy: loadCoachStrategyFromCube,
  ads_focus_terms: loadAdsFocusTermsFromCube,
  ads_focus_keywords: loadAdsFocusKeywordsFromCube,
  campaign_launch_perf: loadCampaignLaunchPerfFromCube,
  campaign_launch_monthly: loadCampaignLaunchMonthlyFromCube,
  plan_ads_targets: loadPlanAdsTargetsFromCube,
  asin_oos_days: loadAsinOosDaysFromCube,
  negative_conflicts: loadNegativeConflictsFromCube,
  strategy_campaign_templates: loadStrategyCampaignTemplatesFromCube,
  coach_cross_sell: loadCrossSellFromCube,
  cubeMeta: loadCubeMeta,
  dataFreshness: loadDataFreshnessFromCube,
};
```

- [ ] **Step 3: Run Task 2's test — expect PASS**

Run: `export PATH="/Users/ori/.nvm/versions/node/v22.22.1/bin:$PATH" && npx vitest run src/hooks/data/pageDatasets.test.ts`
Expected: PASS (3 tests). If "missing loader for X" → a `PAGE_DATASETS` name has no entry in `DATASET_LOADERS`; fix the typo.

- [ ] **Step 4: Confirm no NEW tsc errors in useCubeData** (baseline = 9)

Run: `export PATH="/Users/ori/.nvm/versions/node/v22.22.1/bin:$PATH" && npx tsc -p tsconfig.app.json --noEmit 2>&1 | grep -c "src/hooks/useCubeData.ts"`
Expected: `9` (unchanged). If higher, a loader name is misspelled in the map.

- [ ] **Step 5: Commit**

```bash
git add src/hooks/data/pageDatasets.ts src/hooks/data/pageDatasets.test.ts src/hooks/useCubeData.ts
git commit --no-verify -m "feat(data): page->dataset map + DATASET_LOADERS registry"
```

---

### Task 4: Pure `DatasetStore` (cache + dedupe + status)

**Files:**
- Create: `src/hooks/data/datasetStore.ts`
- Test: `src/hooks/data/datasetStore.test.ts`

- [ ] **Step 1: Write the failing test**

```ts
import { describe, it, expect, vi } from 'vitest';
import { DatasetStore } from './datasetStore';
import type { DatasetName } from './datasetTypes';

const mkLoaders = (impl: Partial<Record<DatasetName, () => Promise<unknown>>>) =>
  impl as Record<DatasetName, () => Promise<unknown>>;

describe('DatasetStore', () => {
  it('loads a dataset once and exposes ready data', async () => {
    const fn = vi.fn().mockResolvedValue([1, 2, 3]);
    const store = new DatasetStore(mkLoaders({ summary: fn }));
    await store.ensure(['summary']);
    expect(store.getStatus('summary')).toBe('ready');
    expect(store.getData('summary')).toEqual([1, 2, 3]);
    expect(fn).toHaveBeenCalledTimes(1);
  });

  it('skips already-ready datasets on re-ensure', async () => {
    const fn = vi.fn().mockResolvedValue([1]);
    const store = new DatasetStore(mkLoaders({ summary: fn }));
    await store.ensure(['summary']);
    await store.ensure(['summary']);
    expect(fn).toHaveBeenCalledTimes(1);
  });

  it('dedupes concurrent in-flight requests', async () => {
    let resolve!: (v: unknown) => void;
    const fn = vi.fn().mockImplementation(() => new Promise(r => { resolve = r; }));
    const store = new DatasetStore(mkLoaders({ summary: fn }));
    const p1 = store.ensure(['summary']);
    const p2 = store.ensure(['summary']);
    resolve([9]);
    await Promise.all([p1, p2]);
    expect(fn).toHaveBeenCalledTimes(1);
    expect(store.getData('summary')).toEqual([9]);
  });

  it('on loader rejection sets error status + fallback []', async () => {
    const fn = vi.fn().mockRejectedValue(new Error('boom'));
    const store = new DatasetStore(mkLoaders({ summary: fn }));
    await store.ensure(['summary']);
    expect(store.getStatus('summary')).toBe('error');
    expect(store.getData('summary')).toEqual([]);
  });

  it('isPageReady true when all are ready or error', async () => {
    const ok = vi.fn().mockResolvedValue([1]);
    const bad = vi.fn().mockRejectedValue(new Error('x'));
    const store = new DatasetStore(mkLoaders({ summary: ok, peak: bad }));
    expect(store.isPageReady(['summary', 'peak'])).toBe(false);
    await store.ensure(['summary', 'peak']);
    expect(store.isPageReady(['summary', 'peak'])).toBe(true);
  });

  it('notifies subscribers on status change', async () => {
    const fn = vi.fn().mockResolvedValue([1]);
    const store = new DatasetStore(mkLoaders({ summary: fn }));
    const listener = vi.fn();
    store.subscribe(listener);
    await store.ensure(['summary']);
    expect(listener).toHaveBeenCalled();
  });
});
```

- [ ] **Step 2: Run it — expect FAIL** (no module)

Run: `export PATH="/Users/ori/.nvm/versions/node/v22.22.1/bin:$PATH" && npx vitest run src/hooks/data/datasetStore.test.ts`
Expected: FAIL (cannot find `./datasetStore`)

- [ ] **Step 3: Implement `datasetStore.ts`**

```ts
import type { DatasetName, Status } from './datasetTypes';
import { fallbackFor } from './datasetTypes';

type Entry = { status: Status; data: unknown };

export class DatasetStore {
  private entries = new Map<DatasetName, Entry>();
  private inflight = new Map<DatasetName, Promise<void>>();
  private listeners = new Set<() => void>();

  constructor(private loaders: Record<DatasetName, () => Promise<unknown>>) {}

  getStatus(name: DatasetName): Status { return this.entries.get(name)?.status ?? 'idle'; }
  getData(name: DatasetName): unknown { return this.entries.get(name)?.data; }

  subscribe = (fn: () => void): (() => void) => {
    this.listeners.add(fn);
    return () => { this.listeners.delete(fn); };
  };

  private emit() { this.listeners.forEach(l => l()); }
  private set(name: DatasetName, status: Status, data: unknown) {
    this.entries.set(name, { status, data });
    this.emit();
  }

  ensure(names: DatasetName[]): Promise<void> {
    return Promise.all(names.map(n => this.ensureOne(n))).then(() => {});
  }

  private ensureOne(name: DatasetName): Promise<void> {
    const status = this.getStatus(name);
    if (status === 'ready' || status === 'error') return Promise.resolve();
    const existing = this.inflight.get(name);
    if (existing) return existing;

    this.set(name, 'loading', this.getData(name));
    const loader = this.loaders[name];
    const p = loader()
      .then(
        d => this.set(name, 'ready', d ?? fallbackFor(name)),
        err => { console.error(`[datasetStore] ${name} failed:`, err); this.set(name, 'error', fallbackFor(name)); },
      )
      .finally(() => { this.inflight.delete(name); });
    this.inflight.set(name, p);
    return p;
  }

  isPageReady(names: DatasetName[]): boolean {
    return names.every(n => { const s = this.getStatus(n); return s === 'ready' || s === 'error'; });
  }

  /** Names that have never been requested — used by idle prefetch. */
  idleDatasets(all: DatasetName[]): DatasetName[] {
    return all.filter(n => this.getStatus(n) === 'idle');
  }
}
```

- [ ] **Step 4: Run the test — expect PASS** (6 tests)

Run: `export PATH="/Users/ori/.nvm/versions/node/v22.22.1/bin:$PATH" && npx vitest run src/hooks/data/datasetStore.test.ts`
Expected: PASS (6)

- [ ] **Step 5: Commit**

```bash
git add src/hooks/data/datasetStore.ts src/hooks/data/datasetStore.test.ts
git commit --no-verify -m "feat(data): pure DatasetStore with cache, dedupe, status"
```

---

### Task 5: `CubeDataProvider` (assembles DashboardData)

**Files:**
- Create: `src/hooks/data/CubeDataProvider.tsx`

- [ ] **Step 1: Implement the provider**

```tsx
import { createContext, useContext, useMemo, useRef, useReducer, useEffect, useCallback } from 'react';
import type { ReactNode } from 'react';
import { DatasetStore } from './datasetStore';
import type { DatasetName } from './datasetTypes';
import { DATASET_LOADERS } from '../useCubeData';
import { SHELL_CORE, PAGE_DATASETS } from './pageDatasets';
import type { DashboardData, PageId, SummaryRow } from '../../types';

const CUBE_API = import.meta.env.VITE_CUBE_API_URL || (import.meta.env.DEV ? 'http://localhost:4000' : '');

// DashboardData keys that have no Cube loader (JSON-sourced or always-empty).
const EMPTY: Partial<DashboardData> = {
  summary: [], actions: [], upcoming: [], peak: [], products: [], hero_asins: [],
  keyword_product_map: [], weekly_trends: [], daily_trends: [], monthly_trends: [],
  weekly_trends_by_asin: [], monthly_trends_by_asin: [], learnings: [], experiments: [],
  budget_health: [], drivers: [], sqp_coverage_weeks: [], change_log: [], negative_keywords: [],
  experiment_weekly: [], sqp_weekly: [], sqp_volume_4w: {}, experiment_campaigns: [],
  campaign_search_terms: [], ads_7d: [], ads_7d_summary: [], holidays: [], experiment_templates: [],
  strategy_campaign_templates: [], coach_decisions: [], coach_cross_sell: [], coach_campaigns: [],
  experiment_evaluations: [], keyword_predictions: [], brand_strength_weekly: [],
  coach_phrase_negatives: [], product_creatives: [], hot_signals: [], ads_focus_terms: [],
  ads_focus_keywords: [], phrase_negatives: [], storage_costs: [], supply_chain: [], supply_pos: [],
  supply_payments: [], supply_shipments: [], supply_other_pos: [], peak_relevance: [],
  family_occasions: [], coach_strategy: [], campaign_launch_perf: [], campaign_launch_monthly: [],
  plan_ads_targets: [], asin_oos_days: [], negative_conflicts: [], launch_models: [], _meta: {},
};

// Dataset keys that map 1:1 to a DashboardData field (everything except the _meta inputs).
const DATA_FIELDS = (Object.keys(DATASET_LOADERS) as DatasetName[])
  .filter(n => n !== 'cubeMeta' && n !== 'dataFreshness');

type CubeCtx = {
  data: Partial<DashboardData>;
  loading: boolean;             // true until SHELL_CORE ready (first paint gate)
  fromCube: boolean;
  ensureDatasets: (names: DatasetName[]) => Promise<void>;
  ensurePage: (page: PageId) => Promise<void>;
  isPageReady: (page: PageId) => boolean;
  prefetchRemaining: () => void;
};

const Ctx = createContext<CubeCtx | null>(null);

export function CubeDataProvider({ children }: { children: ReactNode }) {
  const storeRef = useRef<DatasetStore>();
  if (!storeRef.current) storeRef.current = new DatasetStore(DATASET_LOADERS);
  const store = storeRef.current;

  // Re-render whenever the store emits a change.
  const [version, bump] = useReducer((c: number) => c + 1, 0);
  useEffect(() => store.subscribe(bump), [store]);

  const data = useMemo<Partial<DashboardData>>(() => {
    const out: Partial<DashboardData> = { ...EMPTY };
    for (const f of DATA_FIELDS) {
      if (store.getStatus(f) === 'ready' || store.getStatus(f) === 'error') {
        (out as Record<string, unknown>)[f] = store.getData(f);
      }
    }
    const summary = (store.getData('summary') as SummaryRow[] | undefined) ?? [];
    const cm = (store.getData('cubeMeta') as { refreshed_at?: string; cube_source: 'preagg' | 'live' }) ?? { cube_source: 'live' };
    const df = (store.getData('dataFreshness') as { ads_max_date?: string; performance_max_date?: string }) ?? {};
    out._meta = {
      refreshed_at: cm.refreshed_at,
      cube_source: cm.cube_source,
      data_freshness: df,
      ...(summary[0] ? { date_ranges: { summary_7d: { start: summary[0].period_start || '', end: summary[0].period_end || '' } } } : {}),
    } as DashboardData['_meta'];
    return out;
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [version, store]);

  const ensureDatasets = useCallback((names: DatasetName[]) => store.ensure(names), [store]);
  const ensurePage = useCallback((page: PageId) => store.ensure([...SHELL_CORE, ...(PAGE_DATASETS[page] ?? [])]), [store]);
  const isPageReady = useCallback((page: PageId) => store.isPageReady([...SHELL_CORE, ...(PAGE_DATASETS[page] ?? [])]), [store, version]);
  const prefetchRemaining = useCallback(() => {
    const all = Object.keys(DATASET_LOADERS) as DatasetName[];
    const idle = store.idleDatasets(all);
    if (idle.length) store.ensure(idle);
  }, [store]);

  const loading = !!CUBE_API && !store.isPageReady(SHELL_CORE);

  const value: CubeCtx = { data, loading, fromCube: !!CUBE_API, ensureDatasets, ensurePage, isPageReady, prefetchRemaining };
  return <Ctx.Provider value={value}>{children}</Ctx.Provider>;
}

export function useCubeContext(): CubeCtx {
  const v = useContext(Ctx);
  if (!v) throw new Error('useCubeContext must be used within CubeDataProvider');
  return v;
}
```

- [ ] **Step 2: Typecheck**

Run: `export PATH="/Users/ori/.nvm/versions/node/v22.22.1/bin:$PATH" && npx tsc -p tsconfig.app.json --noEmit 2>&1 | grep "CubeDataProvider" || echo "clean"`
Expected: `clean` (fix any error before continuing; common: `SummaryRow.period_start` name — confirm against `types.ts`)

- [ ] **Step 3: Commit**

```bash
git add src/hooks/data/CubeDataProvider.tsx
git commit --no-verify -m "feat(data): CubeDataProvider assembling DashboardData from store"
```

---

### Task 6: Route `useUnifiedData` + App through the provider (still load all on mount)

**Files:**
- Modify: `src/hooks/useUnifiedData.ts`
- Modify: `src/App.tsx`

- [ ] **Step 1: Rewrite `useUnifiedData` to read the provider**

```ts
import { useCubeContext } from './data/CubeDataProvider';
import { useJsonData, JSON_ONLY_FILES } from './useData';
import type { DashboardData } from '../types';

export function useUnifiedData(): { data: DashboardData; loading: boolean; fromCube: boolean } {
  const { data: cubeData, loading, fromCube } = useCubeContext();
  const { data: jsonData } = useJsonData(JSON_ONLY_FILES) as { data: Partial<DashboardData>; loading: boolean };

  const data = {
    ...cubeData,
    negative_keywords: (jsonData.negative_keywords ?? []) as DashboardData['negative_keywords'],
    _meta: { ...(jsonData._meta ?? {}), ...(cubeData._meta ?? {}) } as DashboardData['_meta'],
  } as DashboardData;

  return { data, loading, fromCube };
}
```

- [ ] **Step 2: Wrap App in the provider and load everything on mount (TEMPORARY — removed in Phase 2)**

In `src/App.tsx`: import `{ CubeDataProvider, useCubeContext }` and add `<CubeDataProvider>` as the OUTERMOST provider in the `App()` tree (above `AuthProvider`). In `AppInner`, add a one-time effect that loads all datasets so Phase 1 has zero behavior change:

```tsx
// PHASE 1 ONLY — preserves "load everything on mount". Removed in Phase 2.
const { ensureDatasets } = useCubeContext();
useEffect(() => {
  ensureDatasets(Object.keys(DATASET_LOADERS) as DatasetName[]);
}, [ensureDatasets]);
```
(import `DATASET_LOADERS` from `./hooks/useCubeData` and `DatasetName` from `./hooks/data/datasetTypes`.)

- [ ] **Step 3: Run the full unit suite — expect 220+ PASS**

Run: `export PATH="/Users/ori/.nvm/versions/node/v22.22.1/bin:$PATH" && npx vitest run`
Expected: all prior tests pass + the new store/pageDatasets tests (≥ 229 total).

- [ ] **Step 4: Verify live (no behavior change)** — reload preview, confirm home renders with real data and console has no new errors. Use the preview tools: reload, `preview_console_logs level=error` (expect none), `preview_eval` to confirm `document.querySelector('main').innerText.length > 1000`.

- [ ] **Step 5: Commit**

```bash
git add src/hooks/useUnifiedData.ts src/App.tsx
git commit --no-verify -m "refactor(data): route dashboard data through CubeDataProvider (no behavior change)"
```

---

## PHASE 2 — Per-page loading + per-page skeleton (the behavior change)

### Task 7: Load only the current page; gate each page on its own skeleton

**Files:**
- Modify: `src/App.tsx`
- (Optionally) Modify: `src/hooks/useCubeData.ts` — delete the now-unused `useCubeData` function (keep `DATASET_LOADERS`, `cubeLoad`, all `load*FromCube`, mappers).

- [ ] **Step 1: Replace the Phase-1 load-everything effect with per-page loading**

In `AppInner`, remove the temporary "load all" effect. Pull from context and drive by `page`:

```tsx
const { data, loading, fromCube } = useUnifiedData();
const { ensurePage, isPageReady } = useCubeContext();

useEffect(() => { ensurePage(visiblePage); }, [visiblePage, ensurePage]);

const pageReady = isPageReady(visiblePage);
```

Replace the existing top-level `if (loading)` skeleton gate so it triggers on **either** first-paint core not ready **or** the current page's data not ready:

```tsx
if (loading || !pageReady) {
  return (
    <>
      <Header data={data} onNav={navigate} />
      <Sidebar activePage={visiblePage} activeFamily={filters.family} onNav={navigate} themeMode={themeMode} onToggleTheme={toggleTheme} />
      <main className="fixed top-14 left-[72px] right-0 bottom-0 overflow-y-auto px-8 py-5 pb-16 scroll-smooth">
        <FilterBar data={data} page={page} />
        <DashboardSkeleton />
      </main>
    </>
  );
}
```

(Keep `loading` = core-not-ready from the provider so the Header/FilterBar, which read core datasets, don't render with empty core.)

- [ ] **Step 2: Run unit suite — expect all PASS**

Run: `export PATH="/Users/ori/.nvm/versions/node/v22.22.1/bin:$PATH" && npx vitest run`
Expected: all pass (no logic in pages changed).

- [ ] **Step 3: Verify live — only the current page's queries fire**

Reload preview. Then with `preview_network` confirm: on initial home load, the number of POSTs to `/cubejs-api/v1/load` ≈ size of `SHELL_CORE ∪ PAGE_DATASETS.home` (~21), NOT ~54. Navigate to **Research** and confirm **0 new** `/cubejs-api/v1/load` requests fire. Navigate to **Supply** and confirm only ~4 fire. Use `preview_console_logs level=error` to confirm no errors and `preview_snapshot` to confirm each page renders content.

- [ ] **Step 4: Delete the dead `useCubeData` hook** (keep everything else in the file)

Remove `export function useCubeData(...) { ... }` (the orchestration hook, ~280 lines). Confirm nothing imports it:
Run: `grep -rn "useCubeData(" src/ | grep -v "DATASET_LOADERS\|useCubeData.ts"` → expect no matches.

- [ ] **Step 5: Commit**

```bash
git add src/App.tsx src/hooks/useCubeData.ts
git commit --no-verify -m "feat(data): per-page on-demand loading + per-page skeleton"
```

---

## PHASE 3 — Idle prefetch

### Task 8: Warm remaining datasets during idle

**Files:**
- Modify: `src/App.tsx`

- [ ] **Step 1: Add idle prefetch after the current page is ready**

In `AppInner`, after `pageReady` is computed:

```tsx
const { prefetchRemaining } = useCubeContext(); // already available from context
useEffect(() => {
  if (!pageReady) return;
  const ric = (window as unknown as { requestIdleCallback?: (cb: () => void) => number }).requestIdleCallback;
  const id = ric ? ric(() => prefetchRemaining()) : window.setTimeout(() => prefetchRemaining(), 1500);
  return () => {
    const cic = (window as unknown as { cancelIdleCallback?: (h: number) => void }).cancelIdleCallback;
    if (ric && cic) cic(id as number); else clearTimeout(id as number);
  };
}, [pageReady, prefetchRemaining]);
```

- [ ] **Step 2: Run unit suite — expect all PASS**

Run: `export PATH="/Users/ori/.nvm/versions/node/v22.22.1/bin:$PATH" && npx vitest run`

- [ ] **Step 3: Verify live — prefetch warms the rest, nav is instant**

Reload preview, land on home. Wait ~5s. With `preview_network`, confirm additional `/cubejs-api/v1/load` requests fire in the background after the page is interactive (the remaining ~33 datasets). Then navigate to **Kpi**/**Actions** and confirm **few or zero** new requests (already warmed). `preview_console_logs level=error` → none.

- [ ] **Step 4: Final full verification + production build**

```bash
export PATH="/Users/ori/.nvm/versions/node/v22.22.1/bin:$PATH"
npx vitest run                 # all pass
npm run build                  # succeeds; chunks unchanged from #1
```

- [ ] **Step 5: Commit**

```bash
git add src/App.tsx
git commit --no-verify -m "feat(data): idle prefetch of remaining datasets after page ready"
```

---

## Self-Review notes (author)

- **Spec coverage:** registry (Task 3), page map (Task 2), provider/cache/dedupe/isPageReady (Tasks 4–5), per-page skeleton (Task 7), idle prefetch (Task 8), 3-phase rollout (Phases 1/2/3), error-as-done (Task 4 test), in-memory cache (DatasetStore), sqp_weekly-in-core flag (SHELL_CORE) — all covered.
- **`_meta` assembly:** handled in CubeDataProvider via `cubeMeta`+`dataFreshness`+`summary`; not a listed page dataset.
- **StrictMode double-fetch:** prevented by in-flight dedupe (DatasetStore test "dedupes concurrent in-flight requests").
- **Provider re-render:** concrete `useReducer` + `useEffect(subscribe)` pattern (Task 5) — provider re-renders on every store emit; `data` recomputes from current statuses.
- **`PageId` completeness:** if `types.ts` defines `PageId` members beyond those in `PAGE_DATASETS`, TypeScript's `Record<PageId, ...>` will error — add them with `[]` (Task 2 note).
