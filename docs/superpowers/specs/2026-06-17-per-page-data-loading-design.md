# Per-Page On-Demand Data Loading + Idle Prefetch

## Problem

The dashboard loads **all data for all 21 pages on mount**. `useCubeData` (`src/hooks/useCubeData.ts`) fires ~54 Cube queries in one effect (7 critical + 4 deferred + 41 light + 2 heavy), regardless of which page is shown. Opening an API-only page like Research, Alerts, or Admin still triggers all ~54 cube queries for ~0 datasets it uses. Every page pays for every other page's data, hammering the Cube API + BigQuery and inflating total session load.

This is item #2 of the dashboard load-time work. #1 (code-splitting + progressive priority render) shipped 2026-06-17 on `feat/owned-negatives-coacher`.

## Goal

Load only the data the **current page** needs, then prefetch the remaining datasets in the background during idle time, caching everything so revisits and cross-page-shared datasets (e.g. `products`) load once. Pages keep reading `data.x` exactly as today — only *when* each dataset loads changes.

Success criteria:
- Navigating to a page fires only that page's (uncached) datasets, not all ~54.
- Opening Research / Alerts / Admin fires ~0 cube queries.
- Subsequent navigation feels instant once idle-prefetch has warmed datasets.
- Existing 220 unit tests stay green; no page regresses.

Non-goals: changing the home page's data needs (it legitimately uses ~20 datasets), persistent/cross-reload caching, query-result pagination.

## Architecture

Replace the single eager `useCubeData` mega-effect with a **dataset registry + cache provider**. The ~50 existing `load*FromCube` functions and their row mappers are reused unchanged; only orchestration changes.

```
navigate(page)
   └─ ensureDatasets(SHELL_CORE ∪ PAGE_DATASETS[page])
        └─ CubeDataProvider: load missing/idle via datasetRegistry  (dedupe in-flight, skip cached)
             └─ cache Map<DatasetName, {status, data}> updates → pages re-render from data.x
   └─ once isPageReady(page): requestIdleCallback → ensureDatasets(all remaining)
```

## Units (each independently testable)

1. **`src/hooks/data/datasetRegistry.ts`** — `Record<DatasetName, () => Promise<unknown>>` mapping each dataset to its existing loader (`loadSummaryFromCube`, etc.). Single source of truth for "how to load dataset X."
2. **`src/hooks/data/pageDatasets.ts`** —
   - `SHELL_CORE: DatasetName[]` = `['_meta','actions','weekly_trends','sqp_weekly','peak']` — exactly what Header + FilterBar read on every page. (Home's heavier essentials like `summary`/`products`/`monthly_trends`/`ads_7d_summary` are NOT here — they live in `PAGE_DATASETS[home]`, so they don't over-fetch on pages that don't use them.)
   - `PAGE_DATASETS: Record<PageId, DatasetName[]>` — see map below.
3. **`src/hooks/data/CubeDataProvider.tsx`** (context) — holds `Map<DatasetName,{status:'idle'|'loading'|'ready'|'error', data}>`. Exposes:
   - `data` — a `DashboardData`-shaped object assembled from ready datasets; not-yet-loaded keys default to `[]`/`{}` (preserves today's array-always-present contract).
   - `ensureDatasets(names[])` — loads only `idle` datasets; returns the in-flight promise for `loading` ones (dedupe); no-ops for `ready`.
   - `isPageReady(pageId)` — true once every dataset in `SHELL_CORE ∪ PAGE_DATASETS[pageId]` is `ready` or `error`.
4. **`src/hooks/useUnifiedData.ts`** — thin adapter reading provider `data`, still merging JSON `negative_keywords` + `_meta`.
5. **`src/App.tsx`** — `useEffect` on `page` → `ensureDatasets(...)`; render per-page skeleton until `isPageReady(page)`; idle-prefetch effect.

## Data flow & loading

- **First load** (home): shell renders once SHELL_CORE ready; existing `DashboardSkeleton` shows until then.
- **Per-page skeleton** gated on `isPageReady(page)`. Keep the empty-core auto-retry (Cube restart) on SHELL_CORE.
- **Idle prefetch**: after current page ready, `requestIdleCallback` (fallback `setTimeout`) → `ensureDatasets(remaining)` deprioritized.
- **Cache**: in-memory for the session. Full reload refetches (same freshness behavior as today). No TTL.

## Error handling

- Per-dataset `error` status with current fallback (`[]`/`{}`). `isPageReady` treats `error` as "done" so a failed query never blocks a page forever.
- Failures roll into `_meta.failed_queries` / `queries_failed` as today.
- Pages already tolerate empty arrays (verified during #1), so partial/late data renders safely.

## Page → dataset map (backbone)

Shell core (always loaded, every page): `_meta, actions, weekly_trends, sqp_weekly, peak`.

| Page | Datasets |
|------|----------|
| home | actions, ads_7d, ads_7d_summary, campaign_search_terms, change_log, experiment_campaigns, experiments, holidays, monthly_trends, monthly_trends_by_asin, peak, products, sqp_coverage_weeks, sqp_weekly, storage_costs, supply_chain, upcoming, weekly_trends, weekly_trends_by_asin, _meta |
| kpi | _meta, actions, ads_7d, ads_7d_summary, ads_focus_keywords, ads_focus_terms, campaign_launch_monthly, campaign_launch_perf, coach_campaigns, daily_trends, monthly_trends, monthly_trends_by_asin, peak, products, sqp_weekly, storage_costs, supply_chain, weekly_trends, weekly_trends_by_asin |
| peak | budget_health, campaign_search_terms, daily_trends, drivers, experiment_campaigns, experiments, holidays, keyword_product_map, negative_keywords, peak, peak_relevance, sqp_weekly, summary, weekly_trends |
| family | _meta, budget_health, drivers, experiments, hero_asins, holidays, keyword_product_map, monthly_trends, peak, sqp_coverage_weeks, sqp_weekly, summary, weekly_trends, weekly_trends_by_asin |
| actions | actions, ads_7d, asin_oos_days, coach_cross_sell, coach_decisions, coach_phrase_negatives, coach_strategy, daily_trends, hot_signals, keyword_predictions, negative_conflicts, plan_ads_targets, supply_chain |
| ads | _meta, ads_7d, campaign_search_terms, coach_decisions, experiment_campaigns, holidays, keyword_product_map, peak, sqp_volume_4w, sqp_weekly |
| do | actions, ads_7d, coach_campaigns, product_creatives, products, strategy_campaign_templates, supply_chain |
| experiment | budget_health, change_log, experiment_weekly, experiments, holidays, keyword_product_map, peak |
| strategies | _meta, experiment_campaigns, experiment_templates, experiment_weekly, holidays, keyword_product_map, peak |
| learn | actions, experiment_templates, experiment_weekly, learnings, peak_relevance |
| supply | supply_other_pos, supply_payments, supply_pos, supply_shipments |
| plan | monthly_trends, products, weekly_trends_by_asin |
| health | _meta, products, summary |
| kwds | keyword_product_map, products |
| log | change_log, negative_keywords |
| products | products |
| brand | brand_strength_weekly |
| admin, alerts, research | (none — API-only pages) |

The map is derived from `data.x` usage per page and lives co-located with a unit test that fails if a page references a dataset not in its list (guards drift). `sqp`/`coach_*` mapped via their existing loaders.

## Scope / phasing (ship & verify incrementally)

- **Phase 1** — Build `datasetRegistry`, `pageDatasets`, `CubeDataProvider`, cache; `useUnifiedData` reads from provider but still loads everything on mount. **No behavior change** — proves plumbing against the 220 tests + live app.
- **Phase 2** — App.tsx switches to per-page `ensureDatasets` + per-page skeleton. **The behavior change.**
- **Phase 3** — Idle prefetch of the remainder.

## Testing

- Registry/cache logic is pure → unit tests: dedupe in-flight, skip cached, error fallback, `isPageReady` transitions. No Cube needed.
- Existing 220 vitest tests must stay green.
- Live preview verification: Network panel shows only a page's queries fire on nav; Research fires ~0 cube queries; navigation after idle prefetch hits cache.

## Open questions / risks

- **Header depends on `sqp_weekly` (a heavy loader)** → it sits in SHELL_CORE and loads on every page. Kept in core for correctness now; "decouple Header from `sqp_weekly`" is a cheap follow-up (Header likely needs only a derived count).
- `useCubeData.ts` is 2630 lines; Phase 1 extracts loaders/mappers (kept) from orchestration (replaced). Keep mappers where they are to limit churn.
- StrictMode double-invoke + dedupe: `ensureDatasets` must dedupe so the dev double-mount doesn't double-fetch.
- `_meta.queries_run` accounting changes (fewer queries per load) — update or drop the counter; not load-bearing.
