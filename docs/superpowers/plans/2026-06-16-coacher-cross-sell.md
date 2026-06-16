# Coacher Self-Brand Cross-Sell — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a coacher action that recommends advertising product B on product A's listing, chosen from proven in-brand co-purchase affinity, surfaced as an approvable card that exports a PRODUCT_DEFENSE product-targeting bulksheet row.

**Architecture:** New BigQuery view `V_ADS_COACH_CROSSSELL` (grain `target_asin × advertise_asin`) sourced from `V_SRC_AmazonAds_purchased_product`, materialized to `T_ADS_COACH_CROSSSELL`, exposed via a new `AdsCoachCrossSell` Cube → dashboard card → Do-page bulksheet. All decision logic in SQL + `DE_COACH_THRESHOLDS` (standing rule).

**Tech Stack:** BigQuery Standard SQL, Cube.js, React 19 + TypeScript (Vitest), the existing Do-page bulksheet generator.

**Spec:** `docs/superpowers/specs/2026-06-16-coacher-cross-sell-design.md`

**Validation note:** SQL objects are validated by deploying to a `*_TMP` name and running sanity queries (the pattern used for `V_ADS_COACH`), not pytest. TS/React parts use Vitest where logic warrants.

---

## File structure

- Create: `scripts/bigquery/views/V_ADS_COACH_CROSSSELL.sql`
- Modify: `scripts/bigquery/procedures/SP_REFRESH_CUBE_TABLES.sql` (add T_ build line)
- Modify: live `DE_COACH_THRESHOLDS` + `scripts/bigquery/tables/DE/DE_COACH_THRESHOLDS.sql` (new key)
- Modify: `config.yaml` (register view + table)
- Create: `cube/schema/AdsCoachCrossSell.js`
- Modify: `dashboard-react/src/types.ts` (`CoachCrossSellRow` + `DashboardData`)
- Modify: `dashboard-react/src/hooks/useCubeData.ts` (query + map)
- Create: `dashboard-react/src/components/Actions/CrossSellCard.tsx`
- Modify: `dashboard-react/src/pages/ActionsPage.tsx` (render the cross-sell section)
- Modify: `dashboard-react/src/pages/DoPage.tsx` (bulksheet export for cross-sell items)
- Modify: `architecture/ADS_COACH_DECISION_MATRIX.md` (document the action)

---

## Task 1: Add `CROSS_SELL_MIN_ORDERS` threshold

**Files:** live `DE_COACH_THRESHOLDS`; `scripts/bigquery/tables/DE/DE_COACH_THRESHOLDS.sql`

- [ ] **Step 1: Insert the GLOBAL threshold row (live)**

```bash
bq query --project_id=onyga-482313 --use_legacy_sql=false '
INSERT INTO `onyga-482313.OI.DE_COACH_THRESHOLDS`
  (threshold_key, strategy_id, coach_mode, product_family, threshold_value, description, source)
VALUES ("CROSS_SELL_MIN_ORDERS","GLOBAL","GUARDIAN",NULL,3.0,"Min A->B cross-purchase orders (30d) to recommend a self-cross-sell product target","MANUAL")'
```

- [ ] **Step 2: Verify exactly one row**

Run: `bq query --use_legacy_sql=false 'SELECT threshold_value FROM `onyga-482313.OI.DE_COACH_THRESHOLDS` WHERE threshold_key="CROSS_SELL_MIN_ORDERS"'`
Expected: one row, `3.0`.

- [ ] **Step 3: Reflect in the seed file** — add the same row to the INSERT in `scripts/bigquery/tables/DE/DE_COACH_THRESHOLDS.sql` (GLOBAL × GUARDIAN section), keeping it a faithful snapshot.

- [ ] **Step 4: Commit**

```bash
git add scripts/bigquery/tables/DE/DE_COACH_THRESHOLDS.sql
git commit -m "feat(coacher): add CROSS_SELL_MIN_ORDERS threshold"
```

---

## Task 2: Create `V_ADS_COACH_CROSSSELL` view

**Files:** Create `scripts/bigquery/views/V_ADS_COACH_CROSSSELL.sql`

Before writing, confirm the name columns on `DIM_PRODUCT` (expects `asin`, `parent_name`/`product_family`, a short-name column — check with `SELECT column_name FROM OI.INFORMATION_SCHEMA.COLUMNS WHERE table_name='DIM_PRODUCT'` and adjust the `pa`/`pb` selects).

- [ ] **Step 1: Write the view SQL**

```sql
CREATE OR REPLACE VIEW `onyga-482313.OI.V_ADS_COACH_CROSSSELL` AS
WITH thr AS (
  SELECT COALESCE(MAX(IF(threshold_key='CROSS_SELL_MIN_ORDERS', threshold_value, NULL)), 3) AS min_orders
  FROM `onyga-482313.OI.DE_COACH_THRESHOLDS`
  WHERE strategy_id='GLOBAL' AND product_family IS NULL
),
-- A (advertised) -> B (purchased) cross-purchases, last 30d, our ASINs only, A != B
pairs AS (
  SELECT
    pp.advertised_asin AS target_asin,      -- listing we will product-target
    pp.purchased_asin  AS advertise_asin,    -- product we will advertise on it
    SUM(pp.orders) AS cross_orders_30d,
    ROUND(SUM(pp.sales), 2) AS cross_sales_30d
  FROM `onyga-482313.OI.V_SRC_AmazonAds_purchased_product` pp
  WHERE pp.date >= DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL 30 DAY)
    AND pp.advertised_asin IS NOT NULL AND pp.purchased_asin IS NOT NULL
    AND pp.advertised_asin != pp.purchased_asin
  GROUP BY 1, 2
),
-- existing live product-target coverage (target=A advertising B), last 30d, to dedupe gaps
covered AS (
  SELECT DISTINCT
    REGEXP_EXTRACT(LOWER(fa.targeting), r'asin="?(b0[a-z0-9]{8})"?') AS target_asin,
    COALESCE(fa.most_advertised_asin_impressions, fa.ASIN_BY_CAMPAIGN_NAME) AS advertise_asin
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` fa
  WHERE fa.date >= DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL 30 DAY)
    AND LOWER(fa.targeting) LIKE 'asin=%'
)
SELECT
  p.target_asin,
  p.advertise_asin,
  pa.parent_name AS target_parent,
  pb.parent_name AS advertise_parent,
  pa.title AS target_name,
  pb.title AS advertise_name,
  p.cross_orders_30d,
  p.cross_sales_30d,
  CASE WHEN p.cross_orders_30d >= 10 THEN 'HIGH'
       WHEN p.cross_orders_30d >= 5  THEN 'MEDIUM'
       ELSE 'LOW' END AS confidence
FROM pairs p
CROSS JOIN thr
JOIN `onyga-482313.OI.DIM_PRODUCT` pa ON p.target_asin = pa.asin      -- target is ours
JOIN `onyga-482313.OI.DIM_PRODUCT` pb ON p.advertise_asin = pb.asin   -- advertised is ours
LEFT JOIN covered c ON c.target_asin = p.target_asin AND c.advertise_asin = p.advertise_asin
WHERE p.cross_orders_30d >= thr.min_orders
  AND c.target_asin IS NULL;  -- gaps only
```

- [ ] **Step 2: Validate on a TMP view**

```bash
sed 's/`onyga-482313.OI.V_ADS_COACH_CROSSSELL`/`onyga-482313.OI.V_ADS_COACH_CROSSSELL_TMP`/' \
  scripts/bigquery/views/V_ADS_COACH_CROSSSELL.sql | bq query --use_legacy_sql=false
```
Expected: `Created ... _TMP` (compiles).

- [ ] **Step 3: Sanity queries**

Run and eyeball:
```bash
bq query --use_legacy_sql=false 'SELECT COUNT(*) n, COUNTIF(target_asin=advertise_asin) self_pairs, MIN(cross_orders_30d) min_ord FROM `onyga-482313.OI.V_ADS_COACH_CROSSSELL_TMP`'
```
Expected: `self_pairs = 0`, `min_ord >= 3`. Spot-check a few rows have sensible product names. Then `bq rm -f -t onyga-482313:OI.V_ADS_COACH_CROSSSELL_TMP`.

- [ ] **Step 4: Deploy the real view + register in config.yaml**

```bash
bq query --use_legacy_sql=false < scripts/bigquery/views/V_ADS_COACH_CROSSSELL.sql
```
Add `V_ADS_COACH_CROSSSELL` to `config.yaml` under views.

- [ ] **Step 5: Commit**

```bash
git add scripts/bigquery/views/V_ADS_COACH_CROSSSELL.sql config.yaml
git commit -m "feat(coacher): V_ADS_COACH_CROSSSELL self-cross-sell pairs view"
```

---

## Task 3: Materialize `T_ADS_COACH_CROSSSELL`

**Files:** Modify `scripts/bigquery/procedures/SP_REFRESH_CUBE_TABLES.sql`; `config.yaml`

- [ ] **Step 1: Add the build line** after the `T_ADS_COACH_DECISION` line (~line 26):

```sql
  CREATE OR REPLACE TABLE `onyga-482313.OI.T_ADS_COACH_CROSSSELL` AS SELECT * FROM `onyga-482313.OI.V_ADS_COACH_CROSSSELL`;
```

- [ ] **Step 2: Build the table once**

```bash
bq query --use_legacy_sql=false 'CREATE OR REPLACE TABLE `onyga-482313.OI.T_ADS_COACH_CROSSSELL` AS SELECT * FROM `onyga-482313.OI.V_ADS_COACH_CROSSSELL`'
```

- [ ] **Step 3: Verify** `bq query --use_legacy_sql=false 'SELECT COUNT(*) FROM `onyga-482313.OI.T_ADS_COACH_CROSSSELL`'` returns a row. Register `T_ADS_COACH_CROSSSELL` in `config.yaml`.

- [ ] **Step 4: Commit**

```bash
git add scripts/bigquery/procedures/SP_REFRESH_CUBE_TABLES.sql config.yaml
git commit -m "feat(coacher): materialize T_ADS_COACH_CROSSSELL in cube refresh"
```

---

## Task 4: Cube schema `AdsCoachCrossSell`

**Files:** Create `cube/schema/AdsCoachCrossSell.js` (follow `cube/schema/AdsCoachDecision.js` style).

- [ ] **Step 1: Write the cube**

```javascript
cube(`AdsCoachCrossSell`, {
  sql: `SELECT * FROM \`onyga-482313.OI.T_ADS_COACH_CROSSSELL\``,
  dimensions: {
    pairId:        { sql: `CONCAT(target_asin, '|', advertise_asin)`, type: `string`, primaryKey: true },
    targetAsin:    { sql: `target_asin`, type: `string` },
    advertiseAsin: { sql: `advertise_asin`, type: `string` },
    targetName:    { sql: `target_name`, type: `string` },
    advertiseName: { sql: `advertise_name`, type: `string` },
    targetParent:  { sql: `target_parent`, type: `string` },
    confidence:    { sql: `confidence`, type: `string` },
  },
  measures: {
    crossOrders30d: { sql: `cross_orders_30d`, type: `sum` },
    crossSales30d:  { sql: `cross_sales_30d`, type: `sum` },
    count:          { type: `count` },
  },
});
```

- [ ] **Step 2: Verify it loads** — `cd cube && npm run dev`, then confirm `AdsCoachCrossSell` appears in the meta (`curl -s localhost:4000/cubejs-api/v1/meta | grep AdsCoachCrossSell`). Stop the dev server.

- [ ] **Step 3: Commit**

```bash
git add cube/schema/AdsCoachCrossSell.js
git commit -m "feat(coacher): AdsCoachCrossSell cube"
```

---

## Task 5: Dashboard type + data mapping

**Files:** Modify `dashboard-react/src/types.ts`, `dashboard-react/src/hooks/useCubeData.ts`

- [ ] **Step 1: Add the type** to `types.ts`:

```typescript
export interface CoachCrossSellRow {
  target_asin: string;
  advertise_asin: string;
  target_name: string | null;
  advertise_name: string | null;
  target_parent: string | null;
  cross_orders_30d: number;
  cross_sales_30d: number;
  confidence: string;
}
```
Add `coach_cross_sell: CoachCrossSellRow[];` to the `DashboardData` interface (follow how `coach_decisions` is declared).

- [ ] **Step 2: Map it in `useCubeData.ts`** — add an `AdsCoachCrossSell` Cube query mirroring the existing `AdsCoachDecision` load block, mapping dimensions/measures to `CoachCrossSellRow` (read the existing block first to match the query+map shape and the default-empty-array fallback).

- [ ] **Step 3: Typecheck**

Run: `cd dashboard-react && npx tsc --noEmit`
Expected: no errors.

- [ ] **Step 4: Commit**

```bash
git add dashboard-react/src/types.ts dashboard-react/src/hooks/useCubeData.ts
git commit -m "feat(coacher): CoachCrossSellRow type + cube mapping"
```

---

## Task 6: Cross-sell card + Actions page section

**Files:** Create `dashboard-react/src/components/Actions/CrossSellCard.tsx`; modify `dashboard-react/src/pages/ActionsPage.tsx`

- [ ] **Step 1: Build `CrossSellCard.tsx`** — read `components/Actions/DecisionCard.tsx` first to reuse the `Card`, formatters (`fM`), and `+ Queue` button pattern. The card shows: title `Advertise "{advertise_name}" on "{target_name}"'s listing`, body line `{cross_orders_30d} shoppers bought it after engaging ads for {target_name} (30d) · {fM(cross_sales_30d)}`, and a `+ Queue` button that pushes a `DoQueueItem` with `action: 'ADD_CROSS_SELL_TARGET'`, `product: advertise_asin`, `targeting: 'asin="'+target_asin+'"'`, `match_type: 'PRODUCT_TARGETING'`.

- [ ] **Step 2: Render a "Cross-sell" section** in `ActionsPage.tsx` from `data.coach_cross_sell`, grouped by `target_parent` (family), alongside the existing action sections.

- [ ] **Step 3: Vitest for the queue payload** — add `CrossSellCard.test.tsx` asserting the queued item has `action='ADD_CROSS_SELL_TARGET'`, `targeting='asin="<target_asin>"'`, `product='<advertise_asin>'`. Run `npx vitest run CrossSellCard`.

- [ ] **Step 4: Commit**

```bash
git add dashboard-react/src/components/Actions/CrossSellCard.tsx dashboard-react/src/pages/ActionsPage.tsx dashboard-react/src/components/Actions/CrossSellCard.test.tsx
git commit -m "feat(coacher): cross-sell action card + Actions section"
```

---

## Task 7: Do-page bulksheet export (PRODUCT_DEFENSE)

**Files:** Modify `dashboard-react/src/pages/DoPage.tsx`

- [ ] **Step 1: Read the existing PROMOTE_TO_EXACT bulksheet generator** in `DoPage.tsx` to learn the row shape, the `DIM_STRATEGY_CAMPAIGN_TEMPLATE` lookup, and the dedupe-vs-live logic.

- [ ] **Step 2: Handle `ADD_CROSS_SELL_TARGET` queue items** — emit Sponsored Products **product-targeting** rows: campaign/ad-group per the **PRODUCT_DEFENSE** template defaults (no fabricated bids/budgets — pull from `DIM_STRATEGY_CAMPAIGN_TEMPLATE` row `PRODUCT_DEFENSE`), advertised product = `product` (B), targeting expression = the item's `targeting` (`asin="A"`). Dedupe against live campaigns as the generator already does.

- [ ] **Step 3: Verify** — queue a cross-sell item in the running dashboard, export the bulksheet, confirm a product-targeting row appears with the right advertised ASIN + `asin="..."` target and PRODUCT_DEFENSE campaign defaults.

- [ ] **Step 4: Commit**

```bash
git add dashboard-react/src/pages/DoPage.tsx
git commit -m "feat(coacher): cross-sell bulksheet export into PRODUCT_DEFENSE"
```

---

## Task 8: SOP + final verification

**Files:** Modify `architecture/ADS_COACH_DECISION_MATRIX.md`

- [ ] **Step 1: Document** the `ADD_CROSS_SELL_TARGET` action, the `V_ADS_COACH_CROSSSELL` view, the `CROSS_SELL_MIN_ORDERS` threshold, and the PRODUCT_DEFENSE export routing; add a maintenance-log row.

- [ ] **Step 2: End-to-end check** — `SP_REFRESH_CUBE_TABLES` runs clean; dashboard shows cross-sell cards; queue → Do page → bulksheet produces a valid product-targeting row.

- [ ] **Step 3: Commit**

```bash
git add architecture/ADS_COACH_DECISION_MATRIX.md
git commit -m "docs(coacher): document cross-sell action in decision matrix"
```

---

## Self-review notes

- **Spec coverage:** signal (T2), pairing/direction (T2), bar ≥3/30d (T1,T2), gaps-only gating (T2 `covered`), grain/new view (T2), action+card (T6), Do-page PRODUCT_DEFENSE export (T7), plumbing T_/cube/type/config/SOP (T3,T4,T5,T8). All covered.
- **Open detail to resolve at execution:** exact `DIM_PRODUCT` name column and the `FACT_AMAZON_ADS.targeting` product-target format (the `covered` regex) — verify against live data in T2 Step 1.
