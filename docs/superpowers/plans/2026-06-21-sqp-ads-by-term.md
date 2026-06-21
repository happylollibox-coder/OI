# SQP × Ads By-Search-Term Table — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the SQP page's "Search Terms" panel (currently fed by the Ads Coach term engine) with a real per-search-term table that unions the SQP funnel and the paid-ads economics from a new BigQuery view.

**Architecture:** New view `V_SQP_ADS_BY_TERM` FULL OUTER JOINs `FACT_AMAZON_SEARCH_PERFORMANCE_WEEKLY` to a weekly aggregation of `FACT_AMAZON_ADS` (per asin × term × week) → materialized to `T_SQP_ADS_BY_TERM` by `SP_REFRESH_CUBE_TABLES` → new `SqpAdsByTerm` cube → new frontend loader `data.sqp_ads_by_term` → a pure rollup util (MAX `amazon_*` within a week, SUM across weeks) → a new `SqpTermsPanel` component that replaces the existing panel in `FamilyPage`.

**Tech Stack:** BigQuery Standard SQL, Cube.js, React 19 + TypeScript (strict), Vitest, Playwright/preview tools.

**Spec:** `docs/superpowers/specs/2026-06-21-sqp-ads-by-term-design.md`

**Branch:** `feat/owned-negatives-coacher`. Dashboard TS commits use `git commit --no-verify` (pre-existing lint debt).

---

## File Structure

| File | Responsibility |
|---|---|
| `scripts/bigquery/views/V_SQP_ADS_BY_TERM.sql` | The joined view (create) |
| `config.yaml` | Register the view (modify) |
| `scripts/bigquery/procedures/SP_REFRESH_CUBE_TABLES.sql` | Add `T_SQP_ADS_BY_TERM` materialization (modify) |
| `cube/schema/SqpAdsByTerm.js` | Cube over the `T_` table (create) |
| `dashboard-react/src/types.ts` | `SqpAdsByTermRow` type + `DashboardData` field (modify) |
| `dashboard-react/src/hooks/useCubeData.ts` | Loader + registry entry (modify) |
| `dashboard-react/src/hooks/data/pageDatasets.ts` | Add dataset to `sqp` + `family` pages (modify) |
| `dashboard-react/src/utils/sqpTermTable.ts` | Pure rollup logic (create) |
| `dashboard-react/src/utils/sqpTermTable.test.ts` | Unit tests for the rollup (create) |
| `dashboard-react/src/components/SqpTermsPanel.tsx` | The new panel UI (create) |
| `dashboard-react/src/pages/FamilyPage.tsx` | Compute filtered rollup + swap the panel (modify) |

---

## Task 1: BigQuery view `V_SQP_ADS_BY_TERM`

**Files:**
- Create: `scripts/bigquery/views/V_SQP_ADS_BY_TERM.sql`
- Modify: `config.yaml`

- [ ] **Step 1: Write the view SQL**

Create `scripts/bigquery/views/V_SQP_ADS_BY_TERM.sql`:

```sql
-- V_SQP_ADS_BY_TERM
-- Per (search_term, asin, week): real SQP funnel (FACT_AMAZON_SEARCH_PERFORMANCE_WEEKLY)
-- FULL OUTER JOINed to weekly-aggregated paid ads (FACT_AMAZON_ADS).
-- Grain kept at asin so the dashboard can filter by family (parent_name) and roll up.
CREATE OR REPLACE VIEW `onyga-482313.OI.V_SQP_ADS_BY_TERM` AS
WITH sqp AS (
  SELECT
    Reporting_Date                          AS reporting_date,
    DATE_SUB(Reporting_Date, INTERVAL 6 DAY) AS week_start,
    ASIN                                    AS asin,
    LOWER(TRIM(Search_Query))               AS term_key,
    Search_Query                            AS search_term,
    Impressions                             AS impressions,
    Clicks                                  AS clicks,
    Cart_Adds                               AS cart_adds,
    ORDERS                                  AS orders,
    ORGANIC_ORDERS                          AS organic_orders,
    AMAZON_IMPRESSIONS                      AS amazon_impressions,
    AMAZON_Clicks                           AS amazon_clicks,
    AMAZON_Cart_Adds                        AS amazon_cart_adds,
    AMAZON_ORDERS                           AS amazon_orders,
    show_rate_pct,
    estimated_organic_rank,
    organic_rank_zone,
    Search_Query_Score                      AS search_query_score
  FROM `onyga-482313.OI.FACT_AMAZON_SEARCH_PERFORMANCE_WEEKLY`
  WHERE DATA_SOURCE = 'SQP'           -- exclude SCP 'OTHER' aggregate rows
),
ads AS (
  SELECT
    DATE_ADD(DATE_TRUNC(date, WEEK(SUNDAY)), INTERVAL 6 DAY) AS reporting_date,
    asin,
    LOWER(TRIM(search_term))  AS term_key,
    ANY_VALUE(search_term)    AS search_term,
    SUM(Ads_cost)             AS ad_spend,
    SUM(Ads_sales)            AS ad_sales,
    SUM(Ads_units)            AS ad_units,
    SUM(GROSS_PROFIT)         AS ad_gross_profit,
    SUM(Ads_clicks)           AS ad_clicks,
    SUM(Ads_orders)           AS ad_orders,
    SUM(Ads_impressions)      AS ad_impressions
  FROM `onyga-482313.OI.FACT_AMAZON_ADS`
  WHERE search_term IS NOT NULL AND TRIM(search_term) != ''
  GROUP BY reporting_date, asin, term_key
)
SELECT
  COALESCE(s.reporting_date, a.reporting_date)                       AS reporting_date,
  COALESCE(s.week_start, DATE_SUB(a.reporting_date, INTERVAL 6 DAY)) AS week_start,
  COALESCE(s.asin, a.asin)                                           AS asin,
  p.parent_name,
  p.product_short_name,
  COALESCE(s.search_term, a.search_term)                            AS search_term,
  COALESCE(s.term_key, a.term_key)                                  AS term_key,
  -- SQP your funnel
  COALESCE(s.impressions, 0)     AS impressions,
  COALESCE(s.clicks, 0)          AS clicks,
  COALESCE(s.cart_adds, 0)       AS cart_adds,
  COALESCE(s.orders, 0)          AS orders,
  COALESCE(s.organic_orders, 0)  AS organic_orders,
  -- market (NULL on ads-only rows)
  s.amazon_impressions,
  s.amazon_clicks,
  s.amazon_cart_adds,
  s.amazon_orders,
  -- paid
  COALESCE(a.ad_impressions, 0)  AS ad_impressions,
  COALESCE(a.ad_clicks, 0)       AS ad_clicks,
  COALESCE(a.ad_orders, 0)       AS ad_orders,
  COALESCE(a.ad_units, 0)        AS ad_units,
  COALESCE(a.ad_spend, 0)        AS ad_spend,
  COALESCE(a.ad_sales, 0)        AS ad_sales,
  COALESCE(a.ad_gross_profit, 0) AS ad_gross_profit,
  -- SQP derived (NULL on ads-only rows)
  s.show_rate_pct,
  s.estimated_organic_rank,
  s.organic_rank_zone,
  s.search_query_score
FROM sqp s
FULL OUTER JOIN ads a
  ON  s.asin           = a.asin
  AND s.term_key       = a.term_key
  AND s.reporting_date = a.reporting_date
LEFT JOIN `onyga-482313.OI.DIM_PRODUCT` p
  ON COALESCE(s.asin, a.asin) = p.asin;
```

- [ ] **Step 2: Deploy the view**

Run:
```bash
bq query --project_id=onyga-482313 --use_legacy_sql=false < scripts/bigquery/views/V_SQP_ADS_BY_TERM.sql
```
Expected: `Created onyga-482313.OI.V_SQP_ADS_BY_TERM` (no error).

- [ ] **Step 3: Validate market volume + join coverage (the critical data check)**

Run:
```bash
bq query --project_id=onyga-482313 --use_legacy_sql=false --format=prettyjson '
SELECT
  (SELECT MAX(amazon_impressions) FROM `onyga-482313.OI.V_SQP_ADS_BY_TERM`
     WHERE asin="B0GSKQ5TJ6" AND term_key="keychain") AS keychain_mkt_vol,
  (SELECT COUNT(*) FROM `onyga-482313.OI.V_SQP_ADS_BY_TERM`
     WHERE asin="B0GSKQ5TJ6" AND impressions>0 AND ad_spend>0) AS matched_rows,
  (SELECT COUNT(*) FROM `onyga-482313.OI.V_SQP_ADS_BY_TERM`
     WHERE asin="B0GSKQ5TJ6" AND amazon_impressions IS NULL AND ad_spend>0) AS ads_only_rows,
  (SELECT COUNT(*) FROM `onyga-482313.OI.V_SQP_ADS_BY_TERM`
     WHERE asin="B0GSKQ5TJ6" AND ad_spend=0 AND impressions>0) AS sqp_only_rows
'
```
Expected: `keychain_mkt_vol` ≈ **139915**; `matched_rows` > 0 (proves the week-alignment join works); `ads_only_rows` ≥ 0 and `sqp_only_rows` > 0 (proves FULL OUTER keeps both sides).

> If `matched_rows = 0`, the week anchor is misaligned — check whether `FACT_AMAZON_SEARCH_PERFORMANCE_WEEKLY.Reporting_Date` is the Saturday week-end (run `SELECT DISTINCT FORMAT_DATE('%A', Reporting_Date) FROM ...FACT_AMAZON_SEARCH_PERFORMANCE_WEEKLY LIMIT 1`); adjust the `WEEK(SUNDAY)` anchor in the `ads` CTE to match, redeploy, re-validate.

- [ ] **Step 4: Register in config.yaml**

In `config.yaml`, add this entry in the views section (alphabetical neighborhood near `V_SQP_QUERY_WEEKLY`):

```yaml
  - name: "V_SQP_ADS_BY_TERM"
    description: "Per (search_term, asin, week): real SQP funnel (FACT_AMAZON_SEARCH_PERFORMANCE_WEEKLY) FULL OUTER JOINed to weekly-aggregated paid ads (FACT_AMAZON_ADS). Feeds the SQP page Search Terms panel via T_SQP_ADS_BY_TERM. amazon_* are market totals (dedupe with MAX per term/week on rollup)."
    source_files: ["scripts/bigquery/views/V_SQP_ADS_BY_TERM.sql"]
    dependencies:
      - FACT_AMAZON_SEARCH_PERFORMANCE_WEEKLY
      - FACT_AMAZON_ADS
      - DIM_PRODUCT
```

- [ ] **Step 5: Commit**

```bash
git add scripts/bigquery/views/V_SQP_ADS_BY_TERM.sql config.yaml
git commit -m "feat(bq): V_SQP_ADS_BY_TERM — SQP funnel x paid ads by search term"
```

---

## Task 2: Materialize `T_SQP_ADS_BY_TERM`

**Files:**
- Modify: `scripts/bigquery/procedures/SP_REFRESH_CUBE_TABLES.sql`

- [ ] **Step 1: Add the materialization line**

In `scripts/bigquery/procedures/SP_REFRESH_CUBE_TABLES.sql`, immediately after the existing line 49 (`CREATE OR REPLACE TABLE ...T_EXPERIMENT_TERM_RECOMMENDATIONS...`), add:

```sql
  -- SQP x Ads by search term (feeds SQP page Search Terms panel)
  CREATE OR REPLACE TABLE `onyga-482313.OI.T_SQP_ADS_BY_TERM` AS SELECT * FROM `onyga-482313.OI.V_SQP_ADS_BY_TERM`;
```

- [ ] **Step 2: Deploy the procedure**

Run:
```bash
bq query --project_id=onyga-482313 --use_legacy_sql=false < scripts/bigquery/procedures/SP_REFRESH_CUBE_TABLES.sql
```
Expected: procedure replaced, no error.

- [ ] **Step 3: Run the refresh + verify the table exists**

Run:
```bash
bq query --project_id=onyga-482313 --use_legacy_sql=false 'CALL `onyga-482313.OI.SP_REFRESH_CUBE_TABLES`()'
bq query --project_id=onyga-482313 --use_legacy_sql=false --format=prettyjson '
SELECT COUNT(*) AS t_rows,
       (SELECT COUNT(*) FROM `onyga-482313.OI.V_SQP_ADS_BY_TERM`) AS v_rows
FROM `onyga-482313.OI.T_SQP_ADS_BY_TERM`'
```
Expected: `t_rows` > 0 and equals `v_rows`.

- [ ] **Step 4: Commit**

```bash
git add scripts/bigquery/procedures/SP_REFRESH_CUBE_TABLES.sql
git commit -m "feat(bq): materialize T_SQP_ADS_BY_TERM in SP_REFRESH_CUBE_TABLES"
```

---

## Task 3: Cube `SqpAdsByTerm`

**Files:**
- Create: `cube/schema/SqpAdsByTerm.js`

- [ ] **Step 1: Write the cube**

Create `cube/schema/SqpAdsByTerm.js`:

```js
// Cube: SQP x Ads by search term — from T_SQP_ADS_BY_TERM
// Feeds dashboard data.sqp_ads_by_term (SQP page Search Terms panel).
cube(`SqpAdsByTerm`, {
  sql: `SELECT * FROM \`onyga-482313.OI.T_SQP_ADS_BY_TERM\``,

  joins: {
    Product: {
      relationship: `belongsTo`,
      sql: `${CUBE}.asin = ${Product}.asin`,
    },
  },

  measures: {
    count:            { type: `count` },
    impressions:      { sql: `impressions`, type: `sum` },
    clicks:           { sql: `clicks`, type: `sum` },
    cartAdds:         { sql: `cart_adds`, type: `sum` },
    orders:           { sql: `orders`, type: `sum` },
    organicOrders:    { sql: `organic_orders`, type: `sum` },
    amazonImpressions:{ sql: `amazon_impressions`, type: `sum` },
    amazonOrders:     { sql: `amazon_orders`, type: `sum` },
    adImpressions:    { sql: `ad_impressions`, type: `sum` },
    adClicks:         { sql: `ad_clicks`, type: `sum` },
    adOrders:         { sql: `ad_orders`, type: `sum` },
    adUnits:          { sql: `ad_units`, type: `sum` },
    adSpend:          { sql: `ad_spend`, type: `sum` },
    adSales:          { sql: `ad_sales`, type: `sum` },
    adGrossProfit:    { sql: `ad_gross_profit`, type: `sum` },
  },

  dimensions: {
    id: {
      sql: `CONCAT(CAST(reporting_date AS STRING), '|', COALESCE(asin,''), '|', COALESCE(term_key,''))`,
      type: `string`,
      primaryKey: true,
    },
    reportingDate:        { sql: `CAST(reporting_date AS TIMESTAMP)`, type: `time` },
    asin:                 { sql: `asin`, type: `string` },
    searchTerm:           { sql: `search_term`, type: `string` },
    showRatePct:          { sql: `show_rate_pct`, type: `number` },
    estimatedOrganicRank: { sql: `estimated_organic_rank`, type: `number` },
    organicRankZone:      { sql: `organic_rank_zone`, type: `string` },
    searchQueryScore:     { sql: `search_query_score`, type: `number` },
  },

  refreshKey: {
    sql: `SELECT MAX(reporting_date) FROM \`onyga-482313.OI.T_SQP_ADS_BY_TERM\``,
  },
});
```

- [ ] **Step 2: Deploy cube-api (or run locally) and verify `/meta`**

Deploy cube-api per the project's normal cube deploy, then run:
```bash
curl -s "$CUBE_API_URL/cubejs-api/v1/meta" | grep -o '"name":"SqpAdsByTerm"'
```
Expected: prints `"name":"SqpAdsByTerm"` (cube is registered). For local: `cd cube && npm run dev` then hit `http://localhost:4000/cubejs-api/v1/meta`.

- [ ] **Step 3: Verify a `/load` returns Bunny rows**

Run a load for `Product.parentName='Bunny'` with measures `SqpAdsByTerm.impressions`, `SqpAdsByTerm.amazonImpressions`, `SqpAdsByTerm.adSpend` and dimension `SqpAdsByTerm.searchTerm`, `Product.parentName`. Expected: non-empty `data` array including a `keychain`-family term with `amazonImpressions` in the tens/hundreds of thousands.

- [ ] **Step 4: Commit**

```bash
git add cube/schema/SqpAdsByTerm.js
git commit -m "feat(cube): SqpAdsByTerm cube over T_SQP_ADS_BY_TERM"
```

---

## Task 4: Frontend type + loader + wiring

**Files:**
- Modify: `dashboard-react/src/types.ts`
- Modify: `dashboard-react/src/hooks/useCubeData.ts`
- Modify: `dashboard-react/src/hooks/data/pageDatasets.ts`

- [ ] **Step 1: Add the row type + DashboardData field**

In `dashboard-react/src/types.ts`, near `SqpWeeklyRow` (line ~578) add:

```ts
export interface SqpAdsByTermRow {
  reporting_date: string;
  week_start: string;
  asin: string;
  parent_name: string | null;
  product_short_name: string | null;
  search_term: string;
  impressions: number;
  clicks: number;
  cart_adds: number;
  orders: number;
  organic_orders: number;
  amazon_impressions: number | null;
  amazon_orders: number | null;
  ad_impressions: number;
  ad_clicks: number;
  ad_orders: number;
  ad_units: number;
  ad_spend: number;
  ad_sales: number;
  ad_gross_profit: number;
  show_rate_pct: number | null;
  estimated_organic_rank: number | null;
  organic_rank_zone: string | null;
  search_query_score: number | null;
}
```

Then add to the `DashboardData` interface (next to `sqp_weekly: SqpWeeklyRow[];` at line ~1256):

```ts
  sqp_ads_by_term: SqpAdsByTermRow[];
```

- [ ] **Step 2: Add the loader**

In `dashboard-react/src/hooks/useCubeData.ts`, after `loadSqpFromCube` (ends ~line 260), add:

```ts
/** SqpAdsByTerm → sqp_ads_by_term */
async function loadSqpAdsByTermFromCube(): Promise<SqpAdsByTermRow[]> {
  const rows = await cubeLoad({
    measures: [
      'SqpAdsByTerm.impressions', 'SqpAdsByTerm.clicks', 'SqpAdsByTerm.cartAdds',
      'SqpAdsByTerm.orders', 'SqpAdsByTerm.organicOrders',
      'SqpAdsByTerm.amazonImpressions', 'SqpAdsByTerm.amazonOrders',
      'SqpAdsByTerm.adImpressions', 'SqpAdsByTerm.adClicks', 'SqpAdsByTerm.adOrders',
      'SqpAdsByTerm.adUnits', 'SqpAdsByTerm.adSpend', 'SqpAdsByTerm.adSales', 'SqpAdsByTerm.adGrossProfit',
    ],
    dimensions: [
      'SqpAdsByTerm.reportingDate', 'SqpAdsByTerm.asin', 'SqpAdsByTerm.searchTerm',
      'SqpAdsByTerm.showRatePct', 'SqpAdsByTerm.estimatedOrganicRank', 'SqpAdsByTerm.organicRankZone',
      'SqpAdsByTerm.searchQueryScore', 'Product.productShortName', 'Product.parentName',
    ],
    timeDimensions: [{ dimension: 'SqpAdsByTerm.reportingDate', dateRange: 'Last 104 weeks' }],
    limit: 80000,
  });
  return (rows as Record<string, unknown>[]).map(r => {
    const rd = r['SqpAdsByTerm.reportingDate'];
    const reporting = rd ? fmtDate(rd) : '';
    const num = (k: string) => Number(r[k] ?? 0);
    const numN = (k: string) => (r[k] != null ? Number(r[k]) : null);
    return {
      reporting_date: reporting,
      week_start: reporting ? addDays(reporting, -6) : '',
      asin: String(r['SqpAdsByTerm.asin'] ?? ''),
      parent_name: r['Product.parentName'] != null ? String(r['Product.parentName']) : null,
      product_short_name: r['Product.productShortName'] != null ? String(r['Product.productShortName']) : null,
      search_term: String(r['SqpAdsByTerm.searchTerm'] ?? ''),
      impressions: num('SqpAdsByTerm.impressions'),
      clicks: num('SqpAdsByTerm.clicks'),
      cart_adds: num('SqpAdsByTerm.cartAdds'),
      orders: num('SqpAdsByTerm.orders'),
      organic_orders: num('SqpAdsByTerm.organicOrders'),
      amazon_impressions: numN('SqpAdsByTerm.amazonImpressions'),
      amazon_orders: numN('SqpAdsByTerm.amazonOrders'),
      ad_impressions: num('SqpAdsByTerm.adImpressions'),
      ad_clicks: num('SqpAdsByTerm.adClicks'),
      ad_orders: num('SqpAdsByTerm.adOrders'),
      ad_units: num('SqpAdsByTerm.adUnits'),
      ad_spend: num('SqpAdsByTerm.adSpend'),
      ad_sales: num('SqpAdsByTerm.adSales'),
      ad_gross_profit: num('SqpAdsByTerm.adGrossProfit'),
      show_rate_pct: numN('SqpAdsByTerm.showRatePct'),
      estimated_organic_rank: numN('SqpAdsByTerm.estimatedOrganicRank'),
      organic_rank_zone: r['SqpAdsByTerm.organicRankZone'] != null ? String(r['SqpAdsByTerm.organicRankZone']) : null,
      search_query_score: numN('SqpAdsByTerm.searchQueryScore'),
    };
  });
}
```

> Confirm `SqpAdsByTermRow` is imported in the file's type imports (add it alongside `SqpWeeklyRow`). Confirm `addDays` and `fmtDate` helpers are already in scope (they are used by `loadSqpFromCube`).

- [ ] **Step 3: Register the loader**

In the dataset registry object (the block starting ~line 2330), add next to `sqp_weekly: loadSqpFromCube,`:

```ts
  sqp_ads_by_term: loadSqpAdsByTermFromCube,
```

- [ ] **Step 4: Add the dataset to the SQP + family pages**

In `dashboard-react/src/hooks/data/pageDatasets.ts`, add `'sqp_ads_by_term'` to both the `family:` array (line ~22) and the `sqp:` array (line ~25), e.g. change the `sqp:` entry's `'sqp_weekly'` token line to include it:

```ts
  sqp: ['budget_health', 'drivers', 'experiments', 'hero_asins', 'holidays', 'keyword_product_map',
    'monthly_trends', 'peak', 'sqp_ads_by_term', 'sqp_coverage_weeks', 'sqp_weekly', 'summary', 'weekly_trends',
    /* ...keep existing remaining tokens... */ ],
```
Apply the same addition to the `family:` array.

- [ ] **Step 5: Typecheck**

Run: `cd dashboard-react && npx tsc --noEmit 2>&1 | grep -E "types.ts|useCubeData.ts|pageDatasets.ts" || echo "no new errors in touched files"`
Expected: `no new errors in touched files` (pre-existing errors elsewhere are acceptable).

- [ ] **Step 6: Commit**

```bash
git add dashboard-react/src/types.ts dashboard-react/src/hooks/useCubeData.ts dashboard-react/src/hooks/data/pageDatasets.ts
git commit --no-verify -m "feat(dash): load sqp_ads_by_term dataset from SqpAdsByTerm cube"
```

---

## Task 5: Pure rollup util (TDD)

**Files:**
- Create: `dashboard-react/src/utils/sqpTermTable.ts`
- Test: `dashboard-react/src/utils/sqpTermTable.test.ts`

- [ ] **Step 1: Write the failing test**

Create `dashboard-react/src/utils/sqpTermTable.test.ts`:

```ts
import { describe, it, expect } from 'vitest';
import { rollupSqpTerms } from './sqpTermTable';
import type { SqpAdsByTermRow } from '../types';

function row(p: Partial<SqpAdsByTermRow>): SqpAdsByTermRow {
  return {
    reporting_date: '2026-06-13', week_start: '2026-06-07', asin: 'A1',
    parent_name: 'Bunny', product_short_name: 'P', search_term: 'cute keychain',
    impressions: 0, clicks: 0, cart_adds: 0, orders: 0, organic_orders: 0,
    amazon_impressions: null, amazon_orders: null,
    ad_impressions: 0, ad_clicks: 0, ad_orders: 0, ad_units: 0,
    ad_spend: 0, ad_sales: 0, ad_gross_profit: 0,
    show_rate_pct: null, estimated_organic_rank: null, organic_rank_zone: null,
    search_query_score: null, ...p,
  };
}

describe('rollupSqpTerms', () => {
  it('MAX amazon within a week (dedupe ASIN fan-out), SUM your impressions across ASINs', () => {
    const rows = [
      row({ asin: 'A1', impressions: 100, amazon_impressions: 20000 }),
      row({ asin: 'A2', impressions: 50,  amazon_impressions: 20000 }),
    ];
    const [t] = rollupSqpTerms(rows);
    expect(t.impressions).toBe(150);      // summed across ASINs
    expect(t.market_vol).toBe(20000);     // MAX within the (term, week), not 40000
  });

  it('SUMS the per-week market volume across weeks', () => {
    const rows = [
      row({ reporting_date: '2026-06-07', impressions: 10, amazon_impressions: 20000 }),
      row({ reporting_date: '2026-06-13', impressions: 10, amazon_impressions: 18000 }),
    ];
    const [t] = rollupSqpTerms(rows);
    expect(t.market_vol).toBe(38000);     // 20000 + 18000
    expect(t.impressions).toBe(20);
  });

  it('computes net ROAS = gross profit / spend and guards divide-by-zero', () => {
    const rows = [
      row({ ad_spend: 10, ad_sales: 30, ad_gross_profit: 18, ad_clicks: 5 }),
    ];
    const [t] = rollupSqpTerms(rows);
    expect(t.net_roas).toBeCloseTo(1.8);
    expect(t.cpc).toBeCloseTo(2.0);
    const [z] = rollupSqpTerms([row({ ad_spend: 0, ad_sales: 0 })]);
    expect(z.net_roas).toBeNull();
    expect(z.cpc).toBeNull();
  });

  it('impr_share is your_impr/amazon_impr as a percent; rank/zone from latest week', () => {
    const rows = [
      row({ reporting_date: '2026-06-07', impressions: 50, amazon_impressions: 10000,
            estimated_organic_rank: 40, organic_rank_zone: 'lower_p1' }),
      row({ reporting_date: '2026-06-13', impressions: 50, amazon_impressions: 10000,
            estimated_organic_rank: 48, organic_rank_zone: 'page_2_plus' }),
    ];
    const [t] = rollupSqpTerms(rows);
    expect(t.impr_share).toBeCloseTo((100 / 20000) * 100); // 100 impr / 20000 summed mkt
    expect(t.est_rank).toBe(48);          // latest week
    expect(t.zone).toBe('page_2_plus');
  });
});
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd dashboard-react && npx vitest run src/utils/sqpTermTable.test.ts`
Expected: FAIL — `rollupSqpTerms` is not exported / module not found.

- [ ] **Step 3: Implement the rollup**

Create `dashboard-react/src/utils/sqpTermTable.ts`:

```ts
import type { SqpAdsByTermRow } from '../types';

export interface SqpTermAgg {
  term: string;
  impressions: number;
  clicks: number;
  cart_adds: number;
  orders: number;
  organic_orders: number;
  market_vol: number;        // SUM over weeks of per-week MAX(amazon_impressions)
  amazon_orders: number;     // SUM over weeks of per-week MAX(amazon_orders)
  ad_impressions: number;
  ad_clicks: number;
  ad_orders: number;
  ad_units: number;
  ad_spend: number;
  ad_sales: number;
  ad_gross_profit: number;
  ctr: number | null;        // %
  cvr: number | null;        // %
  impr_share: number | null; // %
  cpc: number | null;
  acos: number | null;       // %
  net_roas: number | null;
  est_rank: number | null;
  zone: string | null;
  asins: string[];
  rows: SqpAdsByTermRow[];
}

const pct = (num: number, den: number): number | null => (den > 0 ? (num / den) * 100 : null);

export function rollupSqpTerms(rows: SqpAdsByTermRow[]): SqpTermAgg[] {
  // Step 1: collapse to (term_key, week): MAX amazon across ASINs, SUM everything else.
  type WeekAcc = {
    term: string; week: string;
    impressions: number; clicks: number; cart_adds: number; orders: number; organic_orders: number;
    amazon_impressions: number; amazon_orders: number;
    ad_impressions: number; ad_clicks: number; ad_orders: number; ad_units: number;
    ad_spend: number; ad_sales: number; ad_gross_profit: number;
    dominant_impr: number; est_rank: number | null; zone: string | null;
  };
  const byWeek = new Map<string, WeekAcc>();
  for (const r of rows) {
    const term = (r.search_term || '').trim();
    if (!term) continue;
    const key = `${term.toLowerCase()}__${r.reporting_date}`;
    let w = byWeek.get(key);
    if (!w) {
      w = { term, week: r.reporting_date,
        impressions: 0, clicks: 0, cart_adds: 0, orders: 0, organic_orders: 0,
        amazon_impressions: 0, amazon_orders: 0,
        ad_impressions: 0, ad_clicks: 0, ad_orders: 0, ad_units: 0,
        ad_spend: 0, ad_sales: 0, ad_gross_profit: 0,
        dominant_impr: -1, est_rank: null, zone: null };
      byWeek.set(key, w);
    }
    w.impressions += r.impressions;
    w.clicks += r.clicks;
    w.cart_adds += r.cart_adds;
    w.orders += r.orders;
    w.organic_orders += r.organic_orders;
    w.amazon_impressions = Math.max(w.amazon_impressions, r.amazon_impressions ?? 0);
    w.amazon_orders = Math.max(w.amazon_orders, r.amazon_orders ?? 0);
    w.ad_impressions += r.ad_impressions;
    w.ad_clicks += r.ad_clicks;
    w.ad_orders += r.ad_orders;
    w.ad_units += r.ad_units;
    w.ad_spend += r.ad_spend;
    w.ad_sales += r.ad_sales;
    w.ad_gross_profit += r.ad_gross_profit;
    // dominant ASIN within the week carries the rank/zone
    if (r.impressions > w.dominant_impr) {
      w.dominant_impr = r.impressions;
      w.est_rank = r.estimated_organic_rank;
      w.zone = r.organic_rank_zone;
    }
  }

  // Step 2: roll weeks up to (term): SUM across weeks (incl. the per-week amazon).
  type TermAcc = Omit<SqpTermAgg, 'ctr'|'cvr'|'impr_share'|'cpc'|'acos'|'net_roas'> & { latestWeek: string };
  const byTerm = new Map<string, TermAcc>();
  const asinsByTerm = new Map<string, Set<string>>();
  for (const r of rows) {
    const t = (r.search_term || '').trim().toLowerCase();
    if (!t) continue;
    if (!asinsByTerm.has(t)) asinsByTerm.set(t, new Set());
    if (r.asin) asinsByTerm.get(t)!.add(r.asin);
  }
  for (const w of byWeek.values()) {
    const t = w.term.toLowerCase();
    let a = byTerm.get(t);
    if (!a) {
      a = { term: w.term,
        impressions: 0, clicks: 0, cart_adds: 0, orders: 0, organic_orders: 0,
        market_vol: 0, amazon_orders: 0,
        ad_impressions: 0, ad_clicks: 0, ad_orders: 0, ad_units: 0,
        ad_spend: 0, ad_sales: 0, ad_gross_profit: 0,
        est_rank: null, zone: null, asins: Array.from(asinsByTerm.get(t) ?? []),
        rows: rows.filter(r => (r.search_term || '').trim().toLowerCase() === t),
        latestWeek: '' };
      byTerm.set(t, a);
    }
    a.impressions += w.impressions;
    a.clicks += w.clicks;
    a.cart_adds += w.cart_adds;
    a.orders += w.orders;
    a.organic_orders += w.organic_orders;
    a.market_vol += w.amazon_impressions;
    a.amazon_orders += w.amazon_orders;
    a.ad_impressions += w.ad_impressions;
    a.ad_clicks += w.ad_clicks;
    a.ad_orders += w.ad_orders;
    a.ad_units += w.ad_units;
    a.ad_spend += w.ad_spend;
    a.ad_sales += w.ad_sales;
    a.ad_gross_profit += w.ad_gross_profit;
    if (w.week >= a.latestWeek) { a.latestWeek = w.week; a.est_rank = w.est_rank; a.zone = w.zone; }
  }

  // Derived metrics from totals.
  return Array.from(byTerm.values()).map(a => ({
    term: a.term,
    impressions: a.impressions, clicks: a.clicks, cart_adds: a.cart_adds,
    orders: a.orders, organic_orders: a.organic_orders,
    market_vol: a.market_vol, amazon_orders: a.amazon_orders,
    ad_impressions: a.ad_impressions, ad_clicks: a.ad_clicks, ad_orders: a.ad_orders,
    ad_units: a.ad_units, ad_spend: a.ad_spend, ad_sales: a.ad_sales, ad_gross_profit: a.ad_gross_profit,
    ctr: pct(a.clicks, a.impressions),
    cvr: pct(a.orders, a.clicks),
    impr_share: pct(a.impressions, a.market_vol),
    cpc: a.ad_clicks > 0 ? a.ad_spend / a.ad_clicks : null,
    acos: pct(a.ad_spend, a.ad_sales),
    net_roas: a.ad_spend > 0 ? a.ad_gross_profit / a.ad_spend : null,
    est_rank: a.est_rank, zone: a.zone,
    asins: a.asins, rows: a.rows,
  }));
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd dashboard-react && npx vitest run src/utils/sqpTermTable.test.ts`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add dashboard-react/src/utils/sqpTermTable.ts dashboard-react/src/utils/sqpTermTable.test.ts
git commit --no-verify -m "feat(dash): rollupSqpTerms util (MAX amazon/week, SUM across weeks)"
```

---

## Task 6: Panel component + wire into FamilyPage

**Files:**
- Create: `dashboard-react/src/components/SqpTermsPanel.tsx`
- Modify: `dashboard-react/src/pages/FamilyPage.tsx`

- [ ] **Step 1: Write the panel component**

Create `dashboard-react/src/components/SqpTermsPanel.tsx`:

```tsx
import React, { useState } from 'react';
import { Section } from './Section';
import { Th, SortTh, useSort } from './Tooltip';
import { MeasureSelector, useMeasureSelection, type MeasureDef } from './MeasureSelector';
import { RoasBadge } from './Badge';
import { ChevronRight, ChevronDown } from 'lucide-react';
import { fM, fP, fOrd, fClk, fCpc } from '../utils';
import type { SqpTermAgg } from '../utils/sqpTermTable';

const COLUMNS: MeasureDef[] = [
  { id: 'term', label: 'Keyword', group: 'Info' },
  { id: 'market_vol', label: 'Mkt Vol', tip: 'Market search-impression volume (AMAZON_IMPRESSIONS), summed across the weeks shown', group: 'SQP' },
  { id: 'impressions', label: 'Impr', group: 'SQP' },
  { id: 'impr_share', label: 'Impr Share%', tip: 'Your impressions ÷ market impressions', group: 'SQP' },
  { id: 'clicks', label: 'Clicks', group: 'SQP' },
  { id: 'ctr', label: 'CTR%', group: 'SQP' },
  { id: 'cart_adds', label: 'Cart Adds', group: 'SQP' },
  { id: 'orders', label: 'Orders', group: 'SQP' },
  { id: 'cvr', label: 'CVR%', group: 'SQP' },
  { id: 'organic_orders', label: 'Organic Ord', group: 'SQP' },
  { id: 'ad_spend', label: 'Ad Spend', group: 'Ads' },
  { id: 'ad_sales', label: 'Ad Sales', group: 'Ads' },
  { id: 'cpc', label: 'CPC', group: 'Ads' },
  { id: 'net_roas', label: 'Net ROAS', tip: 'Ad gross profit (sales − COGS) ÷ ad spend', group: 'Ads' },
  { id: 'est_rank', label: 'Est Rank', group: 'SQP' },
  { id: 'zone', label: 'Zone', group: 'SQP' },
];

const ZONE_LABELS: Record<string, string> = {
  upper_p1: 'P1 Top', mid_p1: 'P1 Mid', lower_p1: 'P1 Low', bottom_p1: 'P1 Bot', page_2_plus: 'P2+',
};

export function SqpTermsPanel({ terms, filterItems }: { terms: SqpTermAgg[]; filterItems?: string[] }) {
  const [cols, setCols] = useMeasureSelection('sqp_terms', COLUMNS);
  const sort = useSort('market_vol');
  const [expanded, setExpanded] = useState<Set<string>>(new Set());
  const visible = COLUMNS.filter(c => cols.includes(c.id));
  const toggle = (t: string) => setExpanded(p => { const n = new Set(p); n.has(t) ? n.delete(t) : n.add(t); return n; });
  const num = (n: number) => (n ? Math.round(n).toLocaleString() : '--');
  const pctCell = (v: number | null) => (v == null ? '--' : fP(v));

  return (
    <Section title="Search Terms" count={`${terms.length} terms`} filterItems={filterItems}
      headerRight={<MeasureSelector tableId="sqp_terms" measures={COLUMNS} selected={cols} onSelectedChange={setCols} />}>
      <div className="border border-border rounded-xl bg-card overflow-hidden">
        <table className="w-full border-collapse text-xs">
          <thead><tr>
            <Th> </Th>
            {visible.map(c => (
              <SortTh key={c.id} k={c.id} sort={sort.sort} toggle={sort.toggle} right={c.id !== 'term' && c.id !== 'zone'} tip={c.tip}>{c.label}</SortTh>
            ))}
          </tr></thead>
          <tbody>
            {sort.sorted(terms).map((t) => {
              const isExp = expanded.has(t.term);
              const cells: Record<string, React.ReactNode> = {
                term: <td key="term" className="px-3 py-2 font-semibold text-blue-400">{t.term}</td>,
                market_vol: <td key="market_vol" className="px-3 py-2 text-right font-mono text-[11px]">{num(t.market_vol)}</td>,
                impressions: <td key="impressions" className="px-3 py-2 text-right font-mono text-[11px]">{num(t.impressions)}</td>,
                impr_share: <td key="impr_share" className="px-3 py-2 text-right font-mono text-[11px]">{pctCell(t.impr_share)}</td>,
                clicks: <td key="clicks" className="px-3 py-2 text-right">{fClk(t.clicks)}</td>,
                ctr: <td key="ctr" className="px-3 py-2 text-right">{pctCell(t.ctr)}</td>,
                cart_adds: <td key="cart_adds" className="px-3 py-2 text-right font-mono text-[11px]">{num(t.cart_adds)}</td>,
                orders: <td key="orders" className="px-3 py-2 text-right">{fOrd(t.orders)}</td>,
                cvr: <td key="cvr" className="px-3 py-2 text-right">{pctCell(t.cvr)}</td>,
                organic_orders: <td key="organic_orders" className="px-3 py-2 text-right">{fOrd(t.organic_orders)}</td>,
                ad_spend: <td key="ad_spend" className="px-3 py-2 text-right font-mono text-[11px]">{fM(t.ad_spend)}</td>,
                ad_sales: <td key="ad_sales" className="px-3 py-2 text-right font-mono text-[11px]">{fM(t.ad_sales)}</td>,
                cpc: <td key="cpc" className="px-3 py-2 text-right font-mono text-[11px]">{t.cpc == null ? '--' : fCpc(t.cpc)}</td>,
                net_roas: <td key="net_roas" className="px-3 py-2"><RoasBadge value={t.net_roas} /></td>,
                est_rank: <td key="est_rank" className="px-3 py-2 text-right font-mono text-[11px]">{t.est_rank == null ? '--' : Math.round(t.est_rank)}</td>,
                zone: <td key="zone" className="px-3 py-2 text-[11px]">{t.zone ? (ZONE_LABELS[t.zone] || t.zone) : '--'}</td>,
              };
              return (
                <React.Fragment key={t.term}>
                  <tr onClick={() => toggle(t.term)} className="border-b border-border-faint hover:bg-white/[.02] cursor-pointer transition-colors">
                    <td className="px-3 py-2 w-6">{isExp ? <ChevronDown size={12} className="text-faint" /> : <ChevronRight size={12} className="text-faint" />}</td>
                    {visible.map(c => cells[c.id])}
                  </tr>
                  {isExp && (
                    <tr>
                      <td colSpan={visible.length + 1} className="p-0">
                        <div className="bg-inset px-4 py-3 border-b border-border-faint">
                          <div className="text-[10px] text-faint uppercase font-semibold mb-2 tracking-wider">Per-ASIN / week breakdown</div>
                          <table className="w-full text-[11px]">
                            <thead><tr className="text-subtle">
                              <th className="text-left py-1 px-2 font-semibold">Week</th>
                              <th className="text-left py-1 px-2 font-semibold">Product</th>
                              <th className="text-right py-1 px-2 font-semibold">Impr</th>
                              <th className="text-right py-1 px-2 font-semibold">Mkt Vol</th>
                              <th className="text-right py-1 px-2 font-semibold">Clicks</th>
                              <th className="text-right py-1 px-2 font-semibold">Orders</th>
                              <th className="text-right py-1 px-2 font-semibold">Ad Spend</th>
                              <th className="text-right py-1 px-2 font-semibold">Rank</th>
                            </tr></thead>
                            <tbody>
                              {t.rows.slice().sort((a, b) => (b.reporting_date.localeCompare(a.reporting_date)))
                                .map((e, ei) => (
                                <tr key={ei} className="border-t border-border-faint">
                                  <td className="py-1 px-2 font-mono text-[10px]">{e.reporting_date}</td>
                                  <td className="py-1 px-2">{e.product_short_name || e.asin}</td>
                                  <td className="py-1 px-2 text-right font-mono">{(e.impressions || 0).toLocaleString()}</td>
                                  <td className="py-1 px-2 text-right font-mono">{(e.amazon_impressions || 0).toLocaleString()}</td>
                                  <td className="py-1 px-2 text-right">{fClk(e.clicks)}</td>
                                  <td className="py-1 px-2 text-right">{fOrd(e.orders)}</td>
                                  <td className="py-1 px-2 text-right font-mono">{fM(e.ad_spend)}</td>
                                  <td className="py-1 px-2 text-right font-mono">{e.estimated_organic_rank == null ? '--' : Math.round(e.estimated_organic_rank)}</td>
                                </tr>
                              ))}
                            </tbody>
                          </table>
                        </div>
                      </td>
                    </tr>
                  )}
                </React.Fragment>
              );
            })}
          </tbody>
        </table>
      </div>
    </Section>
  );
}
```

> If `useSort`/`SortTh`/`Th` are not exported from `./Tooltip` with these signatures, mirror the exact usage already in `FamilyPage.tsx` (`useSort('orders')`, `<SortTh k=.. sort=.. toggle=.. right=.. tip=..>`). `MeasureDef`/`useMeasureSelection`/`MeasureSelector` import from `./MeasureSelector`. `fM/fP/fOrd/fClk/fCpc` and `RoasBadge` are used identically in `FamilyPage.tsx`.

- [ ] **Step 2: Build the filtered rollup in FamilyPage**

In `dashboard-react/src/pages/FamilyPage.tsx`, add imports near the other component/util imports:

```ts
import { SqpTermsPanel } from '../components/SqpTermsPanel';
import { rollupSqpTerms } from '../utils/sqpTermTable';
```

Add this `useMemo` next to the other SQP memos (after `kwGrouped`, ~line 238). It filters `data.sqp_ads_by_term` by family/product and the selected period weeks, then rolls up:

```ts
  const sqpTermTable = useMemo(() => {
    let rows = (data.sqp_ads_by_term || []);
    rows = showAllFamilies
      ? rows.filter(r => famFromType(r.parent_name || '') != null || r.parent_name != null)
      : rows.filter(r => r.parent_name === family);
    if (selectedVariation) rows = rows.filter(r => r.asin === selectedVariation);
    if (selectedSqpTerm) rows = rows.filter(r => r.search_term === selectedSqpTerm);
    // Period filter on reporting_date (week-end). weeks: latest week; month/year: by prefix.
    const mode = filters.periodMode;
    if (rows.length) {
      if (mode === 'weeks') {
        const latest = rows.reduce((m, r) => (r.reporting_date > m ? r.reporting_date : m), '');
        rows = rows.filter(r => r.reporting_date === latest);
      } else if (mode === 'month') {
        const months = [...new Set(rows.map(r => r.reporting_date.slice(0, 7)))].sort();
        const picked = new Set(getPeriodsToInclude(filters.specificPeriod, 'month', months, 1));
        rows = rows.filter(r => picked.has(r.reporting_date.slice(0, 7)));
      } else {
        const years = [...new Set(rows.map(r => r.reporting_date.slice(0, 4)))].sort();
        const picked = new Set(getPeriodsToInclude(filters.specificPeriod, 'year', years, 1));
        rows = rows.filter(r => picked.has(r.reporting_date.slice(0, 4)));
      }
    }
    return rollupSqpTerms(rows);
  }, [data.sqp_ads_by_term, family, showAllFamilies, selectedVariation, selectedSqpTerm, filters.periodMode, filters.specificPeriod]);
```

> `getPeriodsToInclude`, `famFromType`, `filters`, `selectedVariation`, `selectedSqpTerm`, `showAllFamilies` are all already in scope in `FamilyPage.tsx`.

- [ ] **Step 3: Replace the panel render**

Replace the entire `<Section title="Search Terms" ...> ... </Section>` block (starts ~line 1306, the one using `kwGrouped`/`visibleKwCols`/`FAMILY_KW_COLUMNS`) with:

```tsx
      <div ref={sqpFocusRef}>
        <SqpTermsPanel terms={sqpTermTable} filterItems={formatSectionFilters(filters)} />
      </div>
```

> Keep the `sqpFocusRef` on this wrapper so the SQP nav still scrolls here (the ref currently lives on the SQP performance section — verify which element holds it; attach to whichever is the intended scroll target so `focus==='sqp'` still lands on the panel). Leave all other panels (Organic Keywords, Top Performers, Money Drains, trend, variations) and the now-unused `kwGrouped` path intact if still referenced elsewhere; if `kwGrouped`/`FAMILY_KW_COLUMNS`/`familyKwCols`/`visibleKwCols` become entirely unused after this swap, delete them and their `useMeasureSelection`/`useSort` to avoid dead code.

- [ ] **Step 4: Typecheck + tests**

Run:
```bash
cd dashboard-react && npx vitest run src/utils/sqpTermTable.test.ts && npx tsc --noEmit 2>&1 | grep -E "FamilyPage.tsx|SqpTermsPanel.tsx" || echo "no new type errors in touched files"
```
Expected: tests PASS; `no new type errors in touched files`.

- [ ] **Step 5: Commit**

```bash
git add dashboard-react/src/components/SqpTermsPanel.tsx dashboard-react/src/pages/FamilyPage.tsx
git commit --no-verify -m "feat(dash): real SQP x ads Search Terms panel on SQP page"
```

---

## Task 7: Browser verification

**Files:** none (verification only)

- [ ] **Step 1: Start the dev servers + preview**

Ensure Cube (`cd cube && npm run dev`) and Vite (`cd dashboard-react && npm run dev`) run with `VITE_CUBE_API_URL` pointed at the cube. Open the preview, navigate to the SQP page, set Parent=Bunny, Product=Choice Bunny.

- [ ] **Step 2: Verify the panel shows real data**

Using preview tools (`preview_snapshot`): the "Search Terms" panel should now list real head terms — `keychain`, `cute keychain`, `keychains`, `plush keychain` — with **Mkt Vol** in the tens/hundreds of thousands, **Impr Share%** ≤ 100% (no 10,000% values), and **Net ROAS** badges. Confirm `preview_console_logs` has no errors.

- [ ] **Step 3: Verify period + product filters**

Toggle Weeks/Month and switch Product to another Bunny variation; confirm the table reflows and Mkt Vol grows when more weeks are included (sum-across-weeks behavior). Capture a `preview_screenshot` for the record.

- [ ] **Step 4: Final commit (if any tweaks)**

```bash
git add -A && git commit --no-verify -m "fix(dash): SQP terms panel verification tweaks"
```

---

## Deployment (after all tasks pass)

Deploy cube-api (new `SqpAdsByTerm` cube) and oi-dashboard (frontend). BQ view + SP are already deployed and `SP_REFRESH_CUBE_TABLES` already run in Tasks 1–2. After cube-api deploy, the 30-min cube cache must cycle (or bust locally by touching `cube/schema/SqpAdsByTerm.js`).

## Self-Review Notes

- Spec coverage: view (T1), materialize (T2), cube (T3), loader+wiring (T4), MAX-within-week/SUM-across-weeks rollup + net ROAS + divide-by-zero (T5), panel replacement with default columns (T6), browser verify incl. Impr Share ≤100% (T7). ✅
- The MAX-amazon and SUM-across-weeks rules are unit-tested (T5 steps 1 & 4).
- Net ROAS uses `ad_gross_profit/ad_spend` (GROSS_PROFIT already in `FACT_AMAZON_ADS`) — no extra COGS join. ✅
- Percent fields are pre-multiplied in the util and rendered with `fP(value)` (no extra `*100`) — avoids the bug the old panel had. ✅
```
