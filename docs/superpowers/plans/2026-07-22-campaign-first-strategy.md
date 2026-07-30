# Campaign-First Strategy Page — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the Strategy page group **live campaigns directly by strategy** (campaign→strategy), removing the experiment layer from the Strategy path, so every spending campaign is visible under its strategy (including a populated AUTO card and an Unclassified catch-all).

**Architecture:** Strategy becomes a resolved property of each current campaign via precedence: (1) `DE_CAMPAIGN_STRATEGY` manual override → (2) existing experiment mapping (`V_CAMPAIGN_MAPPING_STATUS.current_strategy_id`) → (3) `targeting_type='Automatic'` ⇒ AUTO → (4) campaign-name pattern (`suggested_strategy`) → (5) `UNCLASSIFIED`. A new perf view aggregates `FACT_AMAZON_ADS` at campaign grain with the resolved strategy attached; two thin cubes expose classification+lifetime perf and weekly perf. The React page is rewritten to read these instead of `experiment_templates` / `experiment_campaigns` / `experiment_weekly`. Experiments, lifecycle, and learnings stay in the DB and on the Learn page untouched.

**Tech Stack:** BigQuery Standard SQL (views + one DE_ table), Cube.js schema, React 19 + TS + Tailwind (dashboard-react), Flask (`data-entry-app/app.py`) for the override write endpoint.

---

## Context the executor must know

- **Reuse, don't rebuild the classifier.** `V_CAMPAIGN_MAPPING_STATUS` already returns per current campaign: `campaign_id, campaign_name, spend_60d, current_experiment_id, current_experiment_name, current_strategy_id, suggested_family, suggested_strategy, suggested_experiment_id, confidence, source`. (Its live DDL is not checked into `scripts/` — locate it with `bq show --view onyga-482313:OI.V_CAMPAIGN_MAPPING_STATUS` before extending; if the file is missing, add the reverse-engineered DDL to `scripts/bigquery/views/` as part of Task 1.)
- **The auto→INTENT fold is deliberate** in `SP_AUTO_ASSIGN_CAMPAIGNS.sql` (`... 'SP/AUTO\b|AUTO.*DISCOVERY|DISCOVERY' ... THEN 'INTENT'`). We do NOT change that procedure. AUTO is separated in the new resolution view via `targeting_type`, so the experiment/mapping subsystem is left intact.
- **Current campaign dimension:** `DIM_CAMPAIGN` (`is_current = TRUE`) — one row per `campaign_id`, survives renames. Columns include `campaign_id, campaign_name, campaign_type, state, is_current`.
- **Family attaches** via `FACT_AMAZON_ADS.most_advertised_asin_impressions → DIM_PRODUCT.asin → parent_name`. Use `parent_name IS NOT NULL` for own products (see [[fact_oi_dim_product_holds_competitor_asins]]).
- **Perf columns** on `FACT_AMAZON_ADS`: `date, campaign_id, campaign_name, campaign_type, targeting_type, most_advertised_asin_impressions, Ads_cost, Ads_orders, Ads_clicks, Ads_impressions, Ads_sales, search_term`. Net ROAS uses `FN_NET_ROAS(sales, 0, cost)`.
- **Strategies enum:** `AUTO, BRAND_DEFENSE, COMPETITOR, EXACT_BOOST, INTENT, PRODUCT_DEFENSE` (`MAPPING_STRATEGIES` in `app.py:7173`), plus synthetic `UNCLASSIFIED`.
- **Cube reads materialized `T_*`, not `V_*`** for stamped prod ([[fact_oi_cube_reads_t_tables]]). In local dev the cubes read the views directly; after schema edits, force a refresh by touching `cube/schema/<Cube>.js` and verify on the PAGE, not the cube API ([[feedback_refresh_cube_cache_after_fix]]).
- **`/api` endpoints must NOT use `@login_required`** (session cookie → 302 HTML → JSON parse error). Copy the `/api/coverage` auth pattern ([[fact_oi_api_auth_decorator]]).
- **Register every new BQ object in `config.yaml`**; deploy ships the working tree ([[fact_oi_dashboard_deploy_ships_working_tree]]).
- **Verification reality:** this stack has no unit harness for SQL/cube; "tests" here are BQ dry-runs, direct cube queries, and in-browser checks via the Browser pane. Pure TS helpers (the resolution/format helpers extracted in Task 6) get vitest tests.

---

## File Structure

**Backend (BigQuery):**
- Create `scripts/bigquery/tables/DE/DE_CAMPAIGN_STRATEGY.sql` — manual override table.
- Create `scripts/bigquery/views/V_CAMPAIGN_STRATEGY_RESOLVED.sql` — per current campaign → resolved `strategy_id` + family + metadata.
- Create `scripts/bigquery/views/V_STRATEGY_CAMPAIGN_PERF.sql` — per campaign lifetime perf + resolved strategy + active flag.
- Create `scripts/bigquery/views/V_STRATEGY_CAMPAIGN_WEEKLY.sql` — campaign×week perf + resolved strategy (for trend/phase).
- Modify `config.yaml` — register the four objects.

**Cube:**
- Create `cube/schema/StrategyCampaign.js` — on `V_STRATEGY_CAMPAIGN_PERF`.
- Create `cube/schema/StrategyCampaignWeekly.js` — on `V_STRATEGY_CAMPAIGN_WEEKLY`.

**Frontend (dashboard-react):**
- Modify `src/hooks/useCubeData.ts` — add `loadStrategyCampaignsFromCube`, `loadStrategyCampaignWeeklyFromCube`, register in the loader map.
- Modify `src/hooks/data/datasetTypes.ts`, `src/hooks/data/CubeDataProvider.tsx`, `src/hooks/data/pageDatasets.ts` — new datasets.
- Modify `src/types.ts` — `StrategyCampaignRow`, `StrategyCampaignWeeklyRow`.
- Create `src/pages/strategiesData.ts` — pure grouping/resolution/format helpers (unit-tested).
- Create `src/pages/strategiesData.test.ts` — vitest for the helpers.
- Modify `src/pages/StrategiesPage.tsx` — rewrite to campaign-first.
- Modify `src/strategies/index.ts` (or wherever `STRATEGY_META` lives) — add `UNCLASSIFIED` meta.

**Admin override (Phase 4 — ships after MVP):**
- Modify `data-entry-app/app.py` — `GET/POST /api/admin/campaign-strategy`.
- Create `src/components/CampaignStrategyOverride.tsx` — Admin panel (mirrors `CampaignMapping.tsx`).
- Modify the Admin page to mount it.

---

## Phase 1 — Backend classification + perf views

### Task 1: `DE_CAMPAIGN_STRATEGY` override table

**Files:**
- Create: `scripts/bigquery/tables/DE/DE_CAMPAIGN_STRATEGY.sql`
- Modify: `config.yaml`

- [ ] **Step 1: Write the DDL**

```sql
-- DE_CAMPAIGN_STRATEGY: manual per-campaign strategy override (highest precedence).
-- Written by the Admin "Campaign Strategy" panel. One row per campaign_id.
CREATE TABLE IF NOT EXISTS `onyga-482313.OI.DE_CAMPAIGN_STRATEGY` (
  campaign_id STRING NOT NULL,
  strategy_id STRING NOT NULL,   -- AUTO|BRAND_DEFENSE|COMPETITOR|EXACT_BOOST|INTENT|PRODUCT_DEFENSE|UNCLASSIFIED
  notes STRING,
  updated_by STRING,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP(),
  PRIMARY KEY (campaign_id) NOT ENFORCED
)
OPTIONS (description = "Manual per-campaign strategy override. Highest precedence in V_CAMPAIGN_STRATEGY_RESOLVED.");
```

- [ ] **Step 2: Create it in BigQuery**

Run: `bq query --use_legacy_sql=false < scripts/bigquery/tables/DE/DE_CAMPAIGN_STRATEGY.sql`
Expected: `Created onyga-482313.OI.DE_CAMPAIGN_STRATEGY` (or no error if it already exists).

- [ ] **Step 3: Register in config.yaml**

Add under the tables section (alongside other `DE_` entries):

```yaml
  - name: "DE_CAMPAIGN_STRATEGY"
    type: table
    layer: data_entry
    source_files: ["scripts/bigquery/tables/DE/DE_CAMPAIGN_STRATEGY.sql"]
    description: "Manual per-campaign strategy override (Admin Campaign Strategy panel)."
```

- [ ] **Step 4: Commit**

```bash
git add scripts/bigquery/tables/DE/DE_CAMPAIGN_STRATEGY.sql config.yaml
git commit -m "feat(strategy): add DE_CAMPAIGN_STRATEGY override table"
```

### Task 2: `V_CAMPAIGN_STRATEGY_RESOLVED` resolution view

**Files:**
- Create: `scripts/bigquery/views/V_CAMPAIGN_STRATEGY_RESOLVED.sql`
- Modify: `config.yaml`

- [ ] **Step 1: Write the view**

```sql
-- V_CAMPAIGN_STRATEGY_RESOLVED: one row per CURRENT campaign with a resolved strategy_id.
-- Precedence: manual override > experiment mapping > Automatic targeting > name pattern > UNCLASSIFIED.
-- Grain: one row per campaign_id (is_current).
CREATE OR REPLACE VIEW `onyga-482313.OI.V_CAMPAIGN_STRATEGY_RESOLVED` AS
WITH
-- Spend-weighted share of Automatic-targeted rows per campaign (last 120d).
auto_share AS (
  SELECT
    campaign_id,
    SAFE_DIVIDE(
      SUM(IF(UPPER(targeting_type) = 'AUTOMATIC', Ads_cost, 0)),
      NULLIF(SUM(Ads_cost), 0)
    ) AS auto_spend_share
  FROM `onyga-482313.OI.FACT_AMAZON_ADS`
  WHERE date >= DATE_SUB(CURRENT_DATE(), INTERVAL 120 DAY)
  GROUP BY campaign_id
),
-- Dominant own-product family per campaign (by ad spend, last 120d).
fam AS (
  SELECT campaign_id, parent_name FROM (
    SELECT
      a.campaign_id,
      p.parent_name,
      ROW_NUMBER() OVER (PARTITION BY a.campaign_id ORDER BY SUM(a.Ads_cost) DESC) AS rn
    FROM `onyga-482313.OI.FACT_AMAZON_ADS` a
    JOIN `onyga-482313.OI.DIM_PRODUCT` p
      ON p.asin = a.most_advertised_asin_impressions
    WHERE p.parent_name IS NOT NULL
      AND a.date >= DATE_SUB(CURRENT_DATE(), INTERVAL 120 DAY)
    GROUP BY a.campaign_id, p.parent_name
  ) WHERE rn = 1
)
SELECT
  c.campaign_id,
  c.campaign_name,
  c.campaign_type,
  fam.parent_name,
  ms.suggested_strategy,
  ms.current_strategy_id,
  ovr.strategy_id AS override_strategy_id,
  aus.auto_spend_share,
  -- Resolution precedence
  COALESCE(
    ovr.strategy_id,
    ms.current_strategy_id,
    IF(aus.auto_spend_share >= 0.5, 'AUTO', NULL),
    ms.suggested_strategy,
    'UNCLASSIFIED'
  ) AS strategy_id,
  CASE
    WHEN ovr.strategy_id IS NOT NULL THEN 'override'
    WHEN ms.current_strategy_id IS NOT NULL THEN 'mapping'
    WHEN aus.auto_spend_share >= 0.5 THEN 'targeting'
    WHEN ms.suggested_strategy IS NOT NULL THEN 'name'
    ELSE 'unclassified'
  END AS strategy_source
FROM `onyga-482313.OI.DIM_CAMPAIGN` c
LEFT JOIN `onyga-482313.OI.V_CAMPAIGN_MAPPING_STATUS` ms USING (campaign_id)
LEFT JOIN `onyga-482313.OI.DE_CAMPAIGN_STRATEGY` ovr USING (campaign_id)
LEFT JOIN auto_share aus USING (campaign_id)
LEFT JOIN fam USING (campaign_id)
WHERE c.is_current = TRUE;
```

- [ ] **Step 2: Dry-run + create**

Run: `bq query --use_legacy_sql=false --dry_run < scripts/bigquery/views/V_CAMPAIGN_STRATEGY_RESOLVED.sql`
Expected: valid, no error. Then create without `--dry_run`.

- [ ] **Step 3: Verify AUTO is now populated and nothing vanished**

Run:
```bash
bq query --use_legacy_sql=false \
'SELECT strategy_id, strategy_source, COUNT(*) n FROM `onyga-482313.OI.V_CAMPAIGN_STRATEGY_RESOLVED` GROUP BY 1,2 ORDER BY 1,2'
```
Expected: an `AUTO` group with a meaningful count (the `*/AUTO` campaigns), and a small/zero `UNCLASSIFIED`. Every current campaign appears exactly once.

- [ ] **Step 4: Register in config.yaml + commit**

```yaml
  - name: "V_CAMPAIGN_STRATEGY_RESOLVED"
    type: view
    layer: analytics
    source_files: ["scripts/bigquery/views/V_CAMPAIGN_STRATEGY_RESOLVED.sql"]
    depends_on: [DIM_CAMPAIGN, V_CAMPAIGN_MAPPING_STATUS, DE_CAMPAIGN_STRATEGY, FACT_AMAZON_ADS, DIM_PRODUCT]
    description: "Per current campaign resolved strategy_id (override>mapping>Automatic>name>UNCLASSIFIED)."
```
```bash
git add scripts/bigquery/views/V_CAMPAIGN_STRATEGY_RESOLVED.sql config.yaml
git commit -m "feat(strategy): resolve strategy per campaign (autos → AUTO, unclassified bucket)"
```

### Task 3: perf views (lifetime + weekly)

**Files:**
- Create: `scripts/bigquery/views/V_STRATEGY_CAMPAIGN_PERF.sql`
- Create: `scripts/bigquery/views/V_STRATEGY_CAMPAIGN_WEEKLY.sql`
- Modify: `config.yaml`

- [ ] **Step 1: Write lifetime perf view**

```sql
-- V_STRATEGY_CAMPAIGN_PERF: per current campaign, resolved strategy + lifetime ads perf.
-- Grain: one row per campaign_id. active = had spend in the last 30 days.
CREATE OR REPLACE VIEW `onyga-482313.OI.V_STRATEGY_CAMPAIGN_PERF` AS
WITH perf AS (
  SELECT
    campaign_id,
    ROUND(SUM(Ads_cost), 2) AS spend,
    SUM(Ads_orders) AS orders,
    SUM(Ads_clicks) AS clicks,
    SUM(Ads_impressions) AS impressions,
    ROUND(SUM(Ads_sales), 2) AS sales,
    ROUND(`onyga-482313.OI.FN_NET_ROAS`(SUM(Ads_sales), 0, SUM(Ads_cost)), 2) AS net_roas,
    ROUND(SAFE_DIVIDE(SUM(Ads_orders) * 100.0, NULLIF(SUM(Ads_clicks), 0)), 2) AS conv_rate,
    ROUND(SAFE_DIVIDE(SUM(Ads_cost), NULLIF(SUM(Ads_clicks), 0)), 2) AS cpc,
    MAX(date) AS last_date,
    COUNTIF(date >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY) AND Ads_cost > 0) > 0 AS is_active
  FROM `onyga-482313.OI.FACT_AMAZON_ADS`
  GROUP BY campaign_id
)
SELECT
  r.campaign_id, r.campaign_name, r.campaign_type, r.parent_name,
  r.strategy_id, r.strategy_source,
  COALESCE(p.spend, 0) AS spend,
  COALESCE(p.orders, 0) AS orders,
  COALESCE(p.clicks, 0) AS clicks,
  COALESCE(p.impressions, 0) AS impressions,
  COALESCE(p.sales, 0) AS sales,
  p.net_roas, p.conv_rate, p.cpc, p.last_date,
  COALESCE(p.is_active, FALSE) AS is_active
FROM `onyga-482313.OI.V_CAMPAIGN_STRATEGY_RESOLVED` r
LEFT JOIN perf p USING (campaign_id);
```

- [ ] **Step 2: Write weekly perf view**

```sql
-- V_STRATEGY_CAMPAIGN_WEEKLY: campaign×week ads perf with resolved strategy (Sunday weeks).
CREATE OR REPLACE VIEW `onyga-482313.OI.V_STRATEGY_CAMPAIGN_WEEKLY` AS
SELECT
  DATE_TRUNC(a.date, WEEK(SUNDAY)) AS week_start,
  a.campaign_id,
  r.campaign_name,
  r.parent_name,
  r.strategy_id,
  ROUND(SUM(a.Ads_cost), 2) AS spend,
  SUM(a.Ads_orders) AS orders,
  SUM(a.Ads_clicks) AS clicks,
  SUM(a.Ads_impressions) AS impressions,
  ROUND(SUM(a.Ads_sales), 2) AS sales,
  ROUND(`onyga-482313.OI.FN_NET_ROAS`(SUM(a.Ads_sales), 0, SUM(a.Ads_cost)), 2) AS net_roas
FROM `onyga-482313.OI.FACT_AMAZON_ADS` a
JOIN `onyga-482313.OI.V_CAMPAIGN_STRATEGY_RESOLVED` r USING (campaign_id)
WHERE a.Ads_cost > 0 OR a.Ads_impressions > 0
GROUP BY 1,2,3,4,5;
```

- [ ] **Step 3: Dry-run, create, sanity-check totals vs Ads**

Create both, then:
```bash
bq query --use_legacy_sql=false \
'SELECT strategy_id, ROUND(SUM(spend)) spend, COUNT(*) campaigns, COUNTIF(is_active) active
 FROM `onyga-482313.OI.V_STRATEGY_CAMPAIGN_PERF` GROUP BY 1 ORDER BY spend DESC'
```
Expected: AUTO row with real spend (~$30k range from Automatic campaigns); INTENT correspondingly lower than before; total spend ≈ all-time `SUM(Ads_cost)`.

- [ ] **Step 4: Register both in config.yaml + commit**

```yaml
  - name: "V_STRATEGY_CAMPAIGN_PERF"
    type: view
    layer: analytics
    source_files: ["scripts/bigquery/views/V_STRATEGY_CAMPAIGN_PERF.sql"]
    depends_on: [V_CAMPAIGN_STRATEGY_RESOLVED, FACT_AMAZON_ADS]
    description: "Per current campaign: resolved strategy + lifetime ads perf + active flag."
  - name: "V_STRATEGY_CAMPAIGN_WEEKLY"
    type: view
    layer: analytics
    source_files: ["scripts/bigquery/views/V_STRATEGY_CAMPAIGN_WEEKLY.sql"]
    depends_on: [V_CAMPAIGN_STRATEGY_RESOLVED, FACT_AMAZON_ADS]
    description: "Campaign×week ads perf with resolved strategy (Sunday weeks)."
```
```bash
git add scripts/bigquery/views/V_STRATEGY_CAMPAIGN_PERF.sql scripts/bigquery/views/V_STRATEGY_CAMPAIGN_WEEKLY.sql config.yaml
git commit -m "feat(strategy): campaign-grain perf views (lifetime + weekly)"
```

---

## Phase 2 — Cubes

### Task 4: `StrategyCampaign` + `StrategyCampaignWeekly` cubes

**Files:**
- Create: `cube/schema/StrategyCampaign.js`
- Create: `cube/schema/StrategyCampaignWeekly.js`

- [ ] **Step 1: Write StrategyCampaign.js**

```js
// Cube: StrategyCampaign — one row per current campaign with resolved strategy + lifetime perf.
// Backed by V_STRATEGY_CAMPAIGN_PERF.
cube(`StrategyCampaign`, {
  sql_table: `\`onyga-482313.OI.V_STRATEGY_CAMPAIGN_PERF\``,
  refreshKey: { every: `30 minutes` },
  measures: {
    count: { type: `count` },
    spend: { sql: `spend`, type: `sum`, format: `currency` },
    orders: { sql: `orders`, type: `sum` },
    clicks: { sql: `clicks`, type: `sum` },
    impressions: { sql: `impressions`, type: `sum` },
    sales: { sql: `sales`, type: `sum`, format: `currency` },
  },
  dimensions: {
    campaignId: { sql: `campaign_id`, type: `string`, primaryKey: true },
    campaignName: { sql: `campaign_name`, type: `string` },
    campaignType: { sql: `campaign_type`, type: `string` },
    parentName: { sql: `parent_name`, type: `string` },
    strategyId: { sql: `strategy_id`, type: `string` },
    strategySource: { sql: `strategy_source`, type: `string` },
    isActive: { sql: `is_active`, type: `boolean` },
    netRoas: { sql: `net_roas`, type: `number` },
    convRate: { sql: `conv_rate`, type: `number` },
    cpc: { sql: `cpc`, type: `number` },
    lastDate: { sql: `last_date`, type: `string` },
  },
});
```

- [ ] **Step 2: Write StrategyCampaignWeekly.js**

```js
// Cube: StrategyCampaignWeekly — campaign×week ads perf with resolved strategy.
// Backed by V_STRATEGY_CAMPAIGN_WEEKLY.
cube(`StrategyCampaignWeekly`, {
  sql_table: `\`onyga-482313.OI.V_STRATEGY_CAMPAIGN_WEEKLY\``,
  refreshKey: { every: `30 minutes` },
  measures: {
    spend: { sql: `spend`, type: `sum`, format: `currency` },
    orders: { sql: `orders`, type: `sum` },
    clicks: { sql: `clicks`, type: `sum` },
    impressions: { sql: `impressions`, type: `sum` },
    sales: { sql: `sales`, type: `sum`, format: `currency` },
  },
  dimensions: {
    id: { sql: `CONCAT(CAST(week_start AS STRING), '|', campaign_id)`, type: `string`, primaryKey: true },
    weekStart: { sql: `CAST(week_start AS TIMESTAMP)`, type: `time` },
    campaignId: { sql: `campaign_id`, type: `string` },
    campaignName: { sql: `campaign_name`, type: `string` },
    parentName: { sql: `parent_name`, type: `string` },
    strategyId: { sql: `strategy_id`, type: `string` },
  },
});
```

- [ ] **Step 3: Verify via cube query**

With local Cube running (`cd cube && npm run dev`), from the dashboard tab run the token'd `cubeLoad` helper (see Browser-pane debugging) against:
`{ dimensions:['StrategyCampaign.strategyId'], measures:['StrategyCampaign.spend','StrategyCampaign.count'] }`
Expected: rows per strategy incl. `AUTO` and `UNCLASSIFIED`, spend matching the Task 3 BQ check.

- [ ] **Step 4: Commit**

```bash
git add cube/schema/StrategyCampaign.js cube/schema/StrategyCampaignWeekly.js
git commit -m "feat(strategy): StrategyCampaign + StrategyCampaignWeekly cubes"
```

---

## Phase 3 — Frontend campaign-first page

### Task 5: types + dataset wiring

**Files:**
- Modify: `src/types.ts`, `src/hooks/data/datasetTypes.ts`, `src/hooks/data/CubeDataProvider.tsx`, `src/hooks/data/pageDatasets.ts`

- [ ] **Step 1: Add row types to `src/types.ts`**

```ts
export interface StrategyCampaignRow {
  campaign_id: string;
  campaign_name: string;
  campaign_type: string | null;
  parent_name: string | null;
  strategy_id: string;
  strategy_source: string;
  is_active: boolean;
  spend: number; orders: number; clicks: number; impressions: number; sales: number;
  net_roas: number | null; conv_rate: number | null; cpc: number | null;
  last_date: string | null;
}
export interface StrategyCampaignWeeklyRow {
  week_start: string;
  campaign_id: string;
  campaign_name: string | null;
  parent_name: string | null;
  strategy_id: string;
  spend: number; orders: number; clicks: number; impressions: number; sales: number;
  net_roas: number | null;
}
```

- [ ] **Step 2: Add dataset keys + defaults + page mapping**

In `datasetTypes.ts` add `'strategy_campaigns' | 'strategy_campaign_weekly'` to the dataset union.
In `CubeDataProvider.tsx` initial state add `strategy_campaigns: [], strategy_campaign_weekly: [],`.
In `pageDatasets.ts` set the `strategies` page datasets to include `'strategy_campaigns', 'strategy_campaign_weekly'` (keep `holidays`; the experiment datasets can be removed from the strategies entry once Task 7 lands).

- [ ] **Step 3: Typecheck**

Run: `cd dashboard-react && npx tsc --noEmit`
Expected: no new errors from these files (pre-existing errors elsewhere are known — commit with `--no-verify` if the hook blocks; see [[project_actions_collapsible_sections]]).

- [ ] **Step 4: Commit**

```bash
git add dashboard-react/src/types.ts dashboard-react/src/hooks/data/
git commit -m "feat(strategy): dataset wiring + row types for campaign-first"
```

### Task 6: cube loaders

**Files:**
- Modify: `src/hooks/useCubeData.ts`

- [ ] **Step 1: Add the two loaders**

```ts
/** V_STRATEGY_CAMPAIGN_PERF → strategy_campaigns */
async function loadStrategyCampaignsFromCube(): Promise<StrategyCampaignRow[]> {
  const rows = await cubeLoad({
    dimensions: ['StrategyCampaign.campaignId','StrategyCampaign.campaignName','StrategyCampaign.campaignType',
      'StrategyCampaign.parentName','StrategyCampaign.strategyId','StrategyCampaign.strategySource',
      'StrategyCampaign.isActive','StrategyCampaign.netRoas','StrategyCampaign.convRate','StrategyCampaign.cpc','StrategyCampaign.lastDate'],
    measures: ['StrategyCampaign.spend','StrategyCampaign.orders','StrategyCampaign.clicks','StrategyCampaign.impressions','StrategyCampaign.sales'],
    limit: 1000,
  });
  return (rows as Record<string, unknown>[]).map(r => ({
    campaign_id: String(r['StrategyCampaign.campaignId'] ?? ''),
    campaign_name: String(r['StrategyCampaign.campaignName'] ?? ''),
    campaign_type: r['StrategyCampaign.campaignType'] ? String(r['StrategyCampaign.campaignType']) : null,
    parent_name: r['StrategyCampaign.parentName'] ? String(r['StrategyCampaign.parentName']) : null,
    strategy_id: String(r['StrategyCampaign.strategyId'] ?? 'UNCLASSIFIED'),
    strategy_source: String(r['StrategyCampaign.strategySource'] ?? ''),
    is_active: r['StrategyCampaign.isActive'] === true || r['StrategyCampaign.isActive'] === 'true',
    spend: Number(r['StrategyCampaign.spend'] ?? 0),
    orders: Number(r['StrategyCampaign.orders'] ?? 0),
    clicks: Number(r['StrategyCampaign.clicks'] ?? 0),
    impressions: Number(r['StrategyCampaign.impressions'] ?? 0),
    sales: Number(r['StrategyCampaign.sales'] ?? 0),
    net_roas: r['StrategyCampaign.netRoas'] != null ? Number(r['StrategyCampaign.netRoas']) : null,
    conv_rate: r['StrategyCampaign.convRate'] != null ? Number(r['StrategyCampaign.convRate']) : null,
    cpc: r['StrategyCampaign.cpc'] != null ? Number(r['StrategyCampaign.cpc']) : null,
    last_date: r['StrategyCampaign.lastDate'] ? String(r['StrategyCampaign.lastDate']) : null,
  }));
}

/** V_STRATEGY_CAMPAIGN_WEEKLY → strategy_campaign_weekly */
async function loadStrategyCampaignWeeklyFromCube(): Promise<StrategyCampaignWeeklyRow[]> {
  const rows = await cubeLoad({
    dimensions: ['StrategyCampaignWeekly.weekStart','StrategyCampaignWeekly.campaignId','StrategyCampaignWeekly.campaignName',
      'StrategyCampaignWeekly.parentName','StrategyCampaignWeekly.strategyId'],
    measures: ['StrategyCampaignWeekly.spend','StrategyCampaignWeekly.orders','StrategyCampaignWeekly.clicks','StrategyCampaignWeekly.impressions','StrategyCampaignWeekly.sales'],
    limit: 50000,
  });
  return (rows as Record<string, unknown>[]).map(r => ({
    week_start: r['StrategyCampaignWeekly.weekStart'] ? fmtDate(r['StrategyCampaignWeekly.weekStart']) : '',
    campaign_id: String(r['StrategyCampaignWeekly.campaignId'] ?? ''),
    campaign_name: r['StrategyCampaignWeekly.campaignName'] ? String(r['StrategyCampaignWeekly.campaignName']) : null,
    parent_name: r['StrategyCampaignWeekly.parentName'] ? String(r['StrategyCampaignWeekly.parentName']) : null,
    strategy_id: String(r['StrategyCampaignWeekly.strategyId'] ?? 'UNCLASSIFIED'),
    spend: Number(r['StrategyCampaignWeekly.spend'] ?? 0),
    orders: Number(r['StrategyCampaignWeekly.orders'] ?? 0),
    clicks: Number(r['StrategyCampaignWeekly.clicks'] ?? 0),
    impressions: Number(r['StrategyCampaignWeekly.impressions'] ?? 0),
    sales: Number(r['StrategyCampaignWeekly.sales'] ?? 0),
    net_roas: null,
  }));
}
```

- [ ] **Step 2: Register in the loader map** (near `experiment_campaigns: loadExperimentCampaignsFromCube,`)

```ts
  strategy_campaigns: loadStrategyCampaignsFromCube,
  strategy_campaign_weekly: loadStrategyCampaignWeeklyFromCube,
```
Import the new row types at the top. Leave the existing experiment loaders in place (Learn page still uses them).

- [ ] **Step 3: Typecheck + commit**

Run: `cd dashboard-react && npx tsc --noEmit` (expect no new errors).
```bash
git add dashboard-react/src/hooks/useCubeData.ts
git commit -m "feat(strategy): cube loaders for strategy_campaigns + weekly"
```

### Task 7: pure grouping/format helpers (unit-tested)

**Files:**
- Create: `src/pages/strategiesData.ts`
- Create: `src/pages/strategiesData.test.ts`

- [ ] **Step 1: Write the failing test**

```ts
import { describe, it, expect } from 'vitest';
import { groupByStrategy, STRATEGY_ORDER } from './strategiesData';
import type { StrategyCampaignRow } from '../types';

const mk = (id: string, strat: string, spend: number, sales: number, active = true): StrategyCampaignRow => ({
  campaign_id: id, campaign_name: id, campaign_type: 'SP', parent_name: 'Fresh',
  strategy_id: strat, strategy_source: 'mapping', is_active: active,
  spend, orders: 1, clicks: 10, impressions: 100, sales,
  net_roas: null, conv_rate: null, cpc: null, last_date: '2026-07-20',
});

describe('groupByStrategy', () => {
  it('aggregates spend + net ROAS per strategy and counts active campaigns', () => {
    const g = groupByStrategy([mk('a','AUTO',100,150), mk('b','AUTO',50,0,false), mk('c','INTENT',200,400)]);
    const auto = g.find(s => s.id === 'AUTO')!;
    expect(auto.totalSpend).toBe(150);
    expect(auto.activeCount).toBe(1);
    expect(auto.avgRoas).toBeCloseTo((150 - 150) / 150); // (sales-spend)/spend = 0
    expect(g.map(s => s.id)).toContain('INTENT');
  });
  it('places UNCLASSIFIED last regardless of spend', () => {
    const g = groupByStrategy([mk('u','UNCLASSIFIED',9999,0), mk('c','INTENT',1,0)]);
    expect(g[g.length - 1].id).toBe('UNCLASSIFIED');
  });
});
```

- [ ] **Step 2: Run it — expect failure**

Run: `cd dashboard-react && npx vitest run src/pages/strategiesData.test.ts`
Expected: FAIL (module not found / `groupByStrategy` undefined).

- [ ] **Step 3: Implement `strategiesData.ts`**

```ts
import type { StrategyCampaignRow } from '../types';

export const STRATEGY_ORDER = ['EXACT_BOOST','INTENT','COMPETITOR','BRAND_DEFENSE','PRODUCT_DEFENSE','AUTO','UNCLASSIFIED'];

export interface StrategyGroup {
  id: string;
  campaigns: StrategyCampaignRow[];
  activeCount: number;
  totalSpend: number;
  totalSales: number;
  avgRoas: number;
}

export function groupByStrategy(rows: StrategyCampaignRow[]): StrategyGroup[] {
  const by: Record<string, StrategyCampaignRow[]> = {};
  rows.forEach(r => { (by[r.strategy_id] = by[r.strategy_id] || []).push(r); });
  const groups = Object.entries(by).map(([id, campaigns]) => {
    const totalSpend = campaigns.reduce((s, c) => s + (c.spend || 0), 0);
    const totalSales = campaigns.reduce((s, c) => s + (c.sales || 0), 0);
    return {
      id, campaigns,
      activeCount: campaigns.filter(c => c.is_active).length,
      totalSpend, totalSales,
      avgRoas: totalSpend > 0 ? (totalSales - totalSpend) / totalSpend : 0,
    };
  });
  const rank = (id: string) => { const i = STRATEGY_ORDER.indexOf(id); return i === -1 ? STRATEGY_ORDER.length : i; };
  return groups.sort((a, b) => rank(a.id) - rank(b.id) || b.totalSpend - a.totalSpend);
}
```

- [ ] **Step 4: Run tests — expect pass**

Run: `cd dashboard-react && npx vitest run src/pages/strategiesData.test.ts`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add dashboard-react/src/pages/strategiesData.ts dashboard-react/src/pages/strategiesData.test.ts
git commit -m "feat(strategy): campaign grouping helpers + tests"
```

### Task 8: rewrite `StrategiesPage.tsx` (campaign-first)

**Files:**
- Modify: `src/pages/StrategiesPage.tsx`
- Modify: `src/strategies/index.ts` (add `UNCLASSIFIED` to `STRATEGY_META`)

- [ ] **Step 1: Add UNCLASSIFIED strategy meta**

In the file exporting `STRATEGY_META`/`DEFAULT_STRATEGY`, add an `UNCLASSIFIED` entry (grey color, label "Unclassified", goal "Live campaigns not yet assigned a strategy — assign them in Admin ▸ Campaign Strategy."). Keep `chartMeasureIds`/`kpiColumns`/`keyMetrics` minimal.

- [ ] **Step 2: Rewrite the page body to consume `strategy_campaigns` + `strategy_campaign_weekly`**

Replace the `templates`/`strategies`/`periodFilteredByExp`/experiment tables with:
- `const groups = useMemo(() => groupByStrategy(applyFilters(data.strategy_campaigns || [])), [...])` where `applyFilters` respects `filters.family` (match `parent_name`) and `filters.product`.
- **Strategy cards grid:** one card per group — `activeCount`, `totalSpend` (`fM`), `avgRoas` (`fR`), keep the per-phase ROAS mini-row driven by `strategy_campaign_weekly` filtered to the group's campaign_ids + `classifyPhase`.
- **Selected strategy detail:** replace the experiment table with a **Campaigns table** — columns Campaign / Type / Family / Ads Spend / Orders / Clicks / CPC / Conv% / Net ROAS / Active — rendered from the group's campaigns (real numbers; fixes the hardcoded-zero bug by construction). Keep the "Trend by Period" chart driven by `strategy_campaign_weekly` aggregated over the group's campaigns (reuse the existing `getPeriodsToInclude`/`weekRangeLabelCapped`/phase-filter logic).
- **Remove** the "Questions to Answer", "Approved Business Learnings", and experiment expand/detail sections from this page (they remain on the Learn page). Keep the Expected Outcome / Key Metrics cards fed from `STRATEGY_META`.
- Keep `usePageSummary`, filters header, and the `Empty` fallbacks (`No campaigns for this strategy`).

Preserve existing imports actually still used (`fM,fP,fOrd,fR,fCpc,fClk`, `filterByPhase`, `classifyPhase`, `PHASE_META`, `ALL_PHASES`, recharts, `Card`, `Empty`). Delete now-unused imports to keep `tsc` clean.

- [ ] **Step 3: Typecheck**

Run: `cd dashboard-react && npx tsc --noEmit`
Expected: no new errors in `StrategiesPage.tsx` / `strategies/index.ts`.

- [ ] **Step 4: Verify in the browser** (Browser pane)

Start the dev server (`Vite Dashboard`), open the Strategy page. Confirm:
- AUTO card shows real active count + spend + ROAS (no longer `$0.00 / 0.00x`).
- Clicking AUTO lists its campaigns (ME-SP/AUTO, BOX-SP/AUTO, BOTTLE-SP/AUTO, FRESH-SP/AUTO…) with **real** per-campaign spend/clicks (not zeros).
- An `Unclassified` card exists iff any campaign is unresolved.
- INTENT spend dropped by roughly the AUTO spend that moved out.
Take a screenshot as proof.

- [ ] **Step 5: Commit**

```bash
git add dashboard-react/src/pages/StrategiesPage.tsx dashboard-react/src/strategies/index.ts
git commit -m "feat(strategy): campaign-first Strategy page (AUTO populated, real campaign metrics)"
```

---

## Phase 4 — Admin override panel (ships after MVP)

### Task 9: Flask override endpoints

**Files:**
- Modify: `data-entry-app/app.py`

- [ ] **Step 1: Add GET list + POST assign** (mirror `/api/admin/campaign-mapping`, **no `@login_required`**, copy `/api/coverage` auth)

```python
@app.route('/api/admin/campaign-strategy', methods=['GET'])
def get_campaign_strategy():
    query = """
    SELECT campaign_id, campaign_name, campaign_type, parent_name,
           strategy_id, strategy_source
    FROM `onyga-482313.OI.V_STRATEGY_CAMPAIGN_PERF`
    ORDER BY (strategy_source = 'unclassified') DESC, spend DESC
    """
    try:
        rows = [dict(r) for r in client.query(query).result()]
        return jsonify({'success': True, 'campaigns': rows, 'strategies': MAPPING_STRATEGIES + ['UNCLASSIFIED']})
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500

@app.route('/api/admin/campaign-strategy/assign', methods=['POST'])
def assign_campaign_strategy():
    data = request.get_json(force=True) or {}
    campaign_id = data.get('campaign_id'); strategy = data.get('strategy')
    if not campaign_id or not strategy:
        return jsonify({'success': False, 'error': 'campaign_id and strategy required'}), 400
    if strategy not in (MAPPING_STRATEGIES + ['UNCLASSIFIED']):
        return jsonify({'success': False, 'error': f'unknown strategy: {strategy}'}), 400
    user_email = session.get('user', {}).get('email', 'dashboard')
    try:
        client.query(
            """
            MERGE `onyga-482313.OI.DE_CAMPAIGN_STRATEGY` T
            USING (SELECT @cid AS campaign_id) S ON T.campaign_id = S.campaign_id
            WHEN MATCHED THEN UPDATE SET strategy_id=@strat, updated_by=@u, updated_at=CURRENT_TIMESTAMP(), notes='manual'
            WHEN NOT MATCHED THEN INSERT (campaign_id, strategy_id, notes, updated_by)
              VALUES (@cid, @strat, 'manual', @u)
            """,
            job_config=bigquery.QueryJobConfig(query_parameters=[
                bigquery.ScalarQueryParameter('cid','STRING',campaign_id),
                bigquery.ScalarQueryParameter('strat','STRING',strategy),
                bigquery.ScalarQueryParameter('u','STRING',user_email),
            ])).result()
        clear_data_cache()
        return jsonify({'success': True})
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500
```

- [ ] **Step 2: Verify locally**

`curl -s localhost:5050/api/admin/campaign-strategy | head` (Flask on :5050, see [[fact_oi_admin_page_needs_flask_5050]]) → JSON with campaigns.
POST a test override for one campaign, confirm the row lands in `DE_CAMPAIGN_STRATEGY`, and that `V_STRATEGY_CAMPAIGN_PERF` reflects `strategy_source='override'` for it.

- [ ] **Step 3: Commit**

```bash
git add data-entry-app/app.py
git commit -m "feat(strategy): Admin campaign-strategy override endpoints"
```

### Task 10: Admin override UI

**Files:**
- Create: `src/components/CampaignStrategyOverride.tsx`
- Modify: the Admin page to mount it

- [ ] **Step 1: Build the panel** mirroring `CampaignMapping.tsx` — table of campaigns (name, family, current strategy, source badge) with a strategy `<select>` per row that POSTs `/api/admin/campaign-strategy/assign`, then refetches. Default sort surfaces `unclassified` first.

- [ ] **Step 2: Verify in browser** — set a campaign's strategy, confirm it moves cards on the Strategy page after a cube refresh ([[feedback_refresh_cube_cache_after_fix]]).

- [ ] **Step 3: Commit**

```bash
git add dashboard-react/src/components/CampaignStrategyOverride.tsx dashboard-react/src/pages/AdminPage.tsx
git commit -m "feat(strategy): Admin campaign-strategy override panel"
```

---

## Self-Review notes

- **Spec coverage:** campaign-first grouping (Task 7–8), autos→AUTO (Task 2 targeting rule), derived+override precedence (Task 2 COALESCE + Task 1 table + Phase 4), Unclassified bucket (Task 2 default + card), hardcoded-zero metrics fixed (Task 8 reads real perf), experiments parked not deleted (experiment loaders/objects untouched). ✅
- **Reversibility:** no destructive DML. `SP_AUTO_ASSIGN_CAMPAIGNS`, `DIM_EXPERIMENT_CAMPAIGN`, experiment cubes, and the Learn page are untouched. Reverting = point `pageDatasets.strategies` back and restore the old page.
- **Risk:** INTENT's headline spend drops when autos move to AUTO — expected and acknowledged by the user. Call it out in the PR description.
- **Open item to confirm at execution:** locate the live `V_CAMPAIGN_MAPPING_STATUS` DDL (not in `scripts/`) and, if missing from the repo, commit its reverse-engineered source alongside Task 2 so the dependency is tracked in `config.yaml`.
