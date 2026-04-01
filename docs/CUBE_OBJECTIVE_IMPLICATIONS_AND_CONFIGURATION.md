# Cube.js: Objective, Implications & Configuration

**Purpose of this document:** Provide a detailed explanation of the Cube.js layer in the OI Dashboard for second-opinion review, architecture decisions, or onboarding.

---

## 1. Objective

### What Cube Does

Cube.js is a **headless analytics API** that sits between the OI Dashboard (React) and BigQuery. It:

1. **Exposes a REST API** (`/cubejs-api/v1/load`) that accepts JSON queries (measures, dimensions, filters, time ranges).
2. **Translates those queries** into BigQuery SQL using schema definitions in `cube/schema/*.js`.
3. **Returns JSON** that the dashboard consumes.

### Why Cube Exists Here

- **Before Cube:** The dashboard used pre-generated JSON files from `refresh_data.py` (Python scripts that queried BigQuery and wrote `summary.json`, `ads.json`, etc.). Data was stale until the next refresh.
- **With Cube:** The dashboard queries BigQuery in real time via Cube. No intermediate JSON for Cube-backed fields. Data freshness follows BigQuery tables.

### What Cube Replaces

| Old (JSON) | New (Cube) |
|------------|------------|
| `summary.json` | Summary cube |
| `ads.json` | Ads cube |
| `weekly_trends.json` | WeeklyTrends cube |
| `actions.json` | ExperimentTermRecommendations cube |
| … (24 data keys) | 21 cubes |

**Still JSON-only:** `negative_keywords` (CSV), `_meta` (refresh metadata).

---

## 2. Architecture

```
┌─────────────────┐     POST /cubejs-api/v1/load     ┌─────────────┐     SQL     ┌───────────┐
│ Dashboard       │ ───────────────────────────────► │ Cube.js     │ ──────────► │ BigQuery  │
│ (React + Vite)  │ ◄─────────────────────────────── │ (Node.js)   │ ◄────────── │ (OI)      │
└─────────────────┘     JSON response               └─────────────┘             └───────────┘
```

- **Dashboard** builds queries (e.g. `{ measures: ['Ads.spend'], dimensions: ['Ads.date'], timeDimensions: [...] }`) and sends them to Cube.
- **Cube** uses `cube/schema/*.js` to generate BigQuery SQL, executes it, and returns rows.
- **No caching layer** by default: each dashboard load triggers multiple Cube queries (24 loaders in parallel via `Promise.allSettled`).

---

## 3. Configuration

### 3.1 Cube Server (`cube/`)

| File | Role |
|------|------|
| `cube.js` | Main config. Only sets `schemaPath: 'schema'`. |
| `schema/*.js` | One file per cube (Ads, Summary, Sqp, etc.). Each defines `sql`, `measures`, `dimensions`, `joins`. |
| `package.json` | `@cubejs-backend/server` + `@cubejs-backend/bigquery-driver`. No pre-aggregations. |

### 3.2 Environment Variables

| Variable | Purpose | Required |
|----------|---------|----------|
| `CUBEJS_DB_TYPE` | `bigquery` | Yes |
| `CUBEJS_DB_BQ_PROJECT_ID` | BigQuery project (e.g. `onyga-482313`) | Yes |
| `CUBEJS_DB_BQ_KEY_FILE` | Path to service account JSON (e.g. `./bq-key.json`) | Local |
| `CUBEJS_DB_BQ_CREDENTIALS` | Base64 of service account JSON | Cloud Run |
| `CUBEJS_DB_BQ_LOCATION` | Dataset region (e.g. `US`) | Yes |
| `CUBESTORE_DATA_DIR` | Override Cube Store dir (e.g. `/tmp/cube-oi-cubestore`) | OneDrive fix |

### 3.3 Dashboard (`dashboard-react/`)

| Config | Purpose |
|--------|---------|
| `VITE_CUBE_API_URL` | Cube API base URL. Empty = no Cube; dashboard shows empty data for Cube-backed fields. |
| `vite.config.ts` | Proxies `/cubejs-api` → `http://localhost:4000` in dev. |
| Build-time | `VITE_CUBE_API_URL` is baked into the bundle. Production builds need the Cloud Run URL. |

### 3.4 Deployment

- **Local:** `cd cube && npm run dev` → Cube on port 4000.
- **Cloud Run:** `gcloud builds submit --config=cloudbuild.yaml .` → deploys Cube as a container. `--allow-unauthenticated` for public access.
- **Dashboard:** Must be built with `VITE_CUBE_API_URL=https://cube-xxx.run.app` (or similar) to hit production Cube.

---

## 4. Current Cubes (21)

| Cube | BigQuery Source | Dashboard Use |
|------|-----------------|---------------|
| Ads | FACT_AMAZON_ADS | ads_7d, campaign_search_terms |
| Summary | FACT_AMAZON_PERFORMANCE_DAILY + FACT_AMAZON_ADS | summary (rolling 7d by family) |
| WeeklyTrends | FACT_AMAZON_PERFORMANCE_DAILY + FACT_AMAZON_ADS | weekly_trends |
| MonthlyTrends | Same | monthly_trends |
| WeeklyTrendsByAsin | Same | weekly_trends_by_asin |
| MonthlyTrendsByAsin | Same | monthly_trends_by_asin |
| Sqp | FACT_AMAZON_SEARCH_PERFORMANCE_WEEKLY | sqp_weekly, sqp_volume_4w |
| ExperimentTermRecommendations | V_EXPERIMENT_TERM_RECOMMENDATIONS | actions, drivers, keyword_product_map |
| ExperimentTemplates | DIM_EXPERIMENT + FACT_AMAZON_ADS | experiment_templates |
| Experiment | DIM_EXPERIMENT | experiments |
| ExperimentDaily | FACT_EXPERIMENT_DAILY | experiment_weekly |
| ExperimentCampaign | DIM_EXPERIMENT_CAMPAIGN | experiment_campaigns |
| ExperimentBudgetHealth | V_EXPERIMENT_BUDGET_HEALTH | budget_health |
| ExperimentLearnings | V_EXPERIMENT_LEARNINGS | learnings |
| ParentHeroAsin | V_PARENT_HERO_ASIN | hero_asins |
| Product | DIM_PRODUCT | products (with CostsHistory) |
| CostsHistory | DIM_COSTS_HISTORY | products (COGS) |
| FactlessBridge | FACT_FACTLESS_BRIDGE | Join for CostsHistory |
| ChangeLog | DIM_EXPERIMENT_CHANGE_LOG | change_log |
| Holidays | DIM_US_HOLIDAYS | upcoming, peak |
| DataFreshness | Custom query | data_freshness |

**Removed (unused):** ExperimentSummary, Performance, StrategyTemplate, BusinessConclusions, Time, SalesTrafficDaily.

> **Note:** `cloudbuild.yaml` and `cube/README.md` mention a prerequisite migration for `DIM_BUSINESS_CONCLUSIONS`. The BusinessConclusions cube was removed; that migration may no longer be required for Cube. Verify if other systems still depend on it.

---

## 5. Implications

### 5.1 Data Freshness

- **Pro:** Data is as fresh as BigQuery. No refresh job delay.
- **Con:** BigQuery tables must be updated by your orchestration (e.g. `SP_ORCHESTRATE_DAILY_REFRESH`). Cube does not trigger refreshes.

### 5.2 Query Load

- **24 parallel loaders** on each dashboard load. Each loader = 1+ BigQuery query.
- **No pre-aggregations** configured. Every request hits BigQuery.
- **Implication:** High traffic or heavy dashboards can increase BigQuery cost and latency. Consider pre-aggregations or caching if needed.

### 5.3 Single Point of Failure

- If Cube is down or unreachable, all Cube-backed fields are empty. Dashboard shows "No summary data" / "Ensure Cube is running".
- No fallback to JSON when Cube fails. `useUnifiedData` returns empty arrays for Cube fields.

### 5.4 Build-Time Coupling

- `VITE_CUBE_API_URL` is embedded at build time. Changing the Cube URL requires a rebuild.
- Dev defaults to `http://localhost:4000` when env is unset.

### 5.5 OneDrive / File Locking

- Cube Store (used for pre-aggregations, which we don't use) cannot lock files in OneDrive sync folders.
- **Workaround:** `CUBESTORE_DATA_DIR=/tmp/cube-oi-cubestore` in `.env`.

### 5.6 Security

- Cloud Run deployment uses `--allow-unauthenticated`. Anyone with the URL can query Cube.
- No row-level security in Cube. BigQuery permissions apply to the service account Cube uses.
- **Recommendation:** Add authentication (e.g. IAP, API key) for production if the dashboard is sensitive.

### 5.7 Schema Maintenance

- Each cube has hand-written SQL. Changes to BigQuery tables require schema updates.
- Joins (e.g. Ads → Product, CostsHistory → FactlessBridge) are defined in schema files. Complex joins can be brittle.

---

## 6. Limitations

### 6.1 No Caching

- Every dashboard visit triggers full BigQuery queries.
- No Redis, no in-memory cache, no pre-aggregations.

### 6.2 Fixed Query Shapes

- The dashboard sends fixed queries per loader. No ad-hoc exploration UI.
- Adding a new measure/dimension requires code changes in both Cube schema and `useCubeData.ts`.

### 6.3 Error Handling

- `cubeLoad` returns `[]` on fetch failure or non-OK response. Errors are logged in dev but not surfaced to the user.
- Individual loader failures (e.g. one cube times out) don't block others (`Promise.allSettled`).

### 6.4 No Incremental Loading

- All 24 loaders run at once. No lazy loading or pagination at the Cube layer.
- Large result sets (e.g. Sqp with `limit: 5000`) are fully loaded.

### 6.5 Date/Time Semantics

- **Summary** uses rolling 7 days from `MAX(DATE)` in BigQuery.
- **WeeklyTrends** uses calendar weeks (Sunday–Saturday) via `DIM_TIME`.
- These are different windows. Summary cannot be replaced by WeeklyTrends without changing semantics.

---

## 7. Recommendations for Second Opinion

1. **Pre-aggregations:** Evaluate whether high-traffic cubes (e.g. Summary, WeeklyTrends, Ads) should use Cube pre-aggregations to reduce BigQuery load.
2. **Authentication:** If the dashboard is internal or sensitive, add auth (IAP, API key, or Cube's own auth) before exposing Cube publicly.
3. **Fallback:** Consider a fallback to JSON when Cube is unavailable, if stale data is preferable to empty screens.
4. **Monitoring:** Add health checks and alerting for Cube/Cloud Run availability.
5. **Cost:** Monitor BigQuery usage and cost as dashboard usage grows.

---

## 8. References

- [Cube.js docs](https://cube.dev/docs)
- [Cube BigQuery driver](https://cube.dev/docs/backend/bigquery)
- Project: `cube/README.md`, `docs/DATA_SOURCES.md`, `docs/CUBE_FIELDS_TO_PAGE_LABEL_MAPPING.md`
