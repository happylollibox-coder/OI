# Weekly Run Budget Waterfall — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the Weekly Run one total daily ad budget ($700) that waterfalls to families (by real net profit) then campaigns (by ads net profit), plus a daily optimizer that tunes out-of-budget campaigns and a 30-day floor-campaign lifecycle — all backend, all prepare-only.

**Architecture:** BigQuery views feed the budget machinery that already exists (`DE_PRODUCT_BUDGET`, `V_ADS_COACH`, the weekly-plan tool). New `DE_*` config/log tables hold the knobs; new `V_*` views compute the allocation, the daily move, and the lifecycle; `V_ADS_COACH`'s old budget thresholds are replaced so there is one budget brain. A thin React Step-1 renders backend numbers and captures the total + manual overrides. Cube serves the new views via `T_*` tables.

**Tech Stack:** BigQuery Standard SQL, Python 3 (`tools/`, pytest), Cube.js (`cube/schema/`), React 19 + TypeScript + Vitest (`dashboard-react/`).

**Spec:** `docs/superpowers/specs/2026-07-05-weekly-run-budget-waterfall.md` — read it first.

**Conventions (OI):**
- Views deploy via raw `bq query --use_legacy_sql=false 'CREATE OR REPLACE VIEW …'`; the `.sql` file is the source of record and every object is registered in `config.yaml`.
- `bq` project flag: `--project_id=onyga-482313`, dataset `OI`, location US.
- Cube reads materialized `T_*` tables built by `SP_REFRESH_CUBE_TABLES`; a deployed view isn't "live" to the dashboard until that SP runs.
- BQ assertion tests live in `scripts/bigquery/tests/` and are run with `bq query`; a test passes when its `SELECT` returns zero violation rows.
- Dashboard TS commits use `--no-verify` (pre-existing tsc noise); run `npx tsc --noEmit` scoped to touched files.
- Node path: `/Users/ori/.nvm/versions/node/v22.22.1/bin`.

---

## File Structure

**New BigQuery objects** (`scripts/bigquery/`):
- `tables/DE/DE_BUDGET_CONFIG.sql` — keyed config (total, floor, thresholds).
- `tables/DE/DE_FLOOR_CAMPAIGN_LOG.sql` — floor-since clock.
- `views/V_FAMILY_NET_PROFIT_7D.sql` — per-family split weight.
- `views/V_FAMILY_BUDGET_ALLOCATION.sql` — total → family.
- `views/V_CAMPAIGN_BUDGET_BASE.sql` — family → campaign.
- `views/V_CAMPAIGN_DAILY_MOVE.sql` — daily out-of-budget optimizer.
- `views/V_FLOOR_CAMPAIGN_LIFECYCLE.sql` — 30-day graduate/close.
- `tests/BUDGET_WATERFALL_INVARIANTS.sql` — coverage + sum assertions.

**Modified BigQuery objects:**
- `views/V_ADS_COACH_CAMPAIGN.sql` — budget block reads the new views.
- `procedures/SP_REFRESH_CUBE_TABLES.sql` — build the new `T_*` + MERGE the floor log.
- `config.yaml` — register every new object.

**Python** (`tools/`):
- `tools/budget/waterfall.py` — weekly re-base: compute family allocation → write `DE_PRODUCT_BUDGET` (source `WATERFALL`).
- `tools/budget/tests/test_waterfall.py` — pure-function tests for the split math.

**Cube** (`cube/schema/`):
- `FamilyBudgetAllocation.js`, `CampaignBudgetBase.js`, `CampaignDailyMove.js`, `FloorCampaignLifecycle.js`.

**React** (`dashboard-react/src/`):
- `pages/WeeklyRunPage.tsx` — new Step 1 (total input + family override table + lifecycle verdicts).
- `pages/budgetWaterfall.ts` — pure allocation-display helpers.
- `pages/budgetWaterfall.test.ts` — vitest for the helpers.
- `hooks/useCubeData.ts` + `types.ts` — loaders + row types for the four new cubes.

---

## Phase 0 — Config + net-profit source

### Task 1: `DE_BUDGET_CONFIG` table + seed

**Files:**
- Create: `scripts/bigquery/tables/DE/DE_BUDGET_CONFIG.sql`
- Modify: `config.yaml`

- [ ] **Step 1: Write the DDL + seed file**

```sql
-- DE_BUDGET_CONFIG — knobs for the Weekly Run budget waterfall + daily optimizer.
-- Keyed like DE_COACH_THRESHOLDS so Ori can edit a single value without a deploy.
CREATE TABLE IF NOT EXISTS `onyga-482313.OI.DE_BUDGET_CONFIG` (
  config_key   STRING NOT NULL,
  config_value FLOAT64,
  note         STRING,
  updated_at   TIMESTAMP,
  updated_by   STRING
);
```

Seed values (run once after create):

```sql
DELETE FROM `onyga-482313.OI.DE_BUDGET_CONFIG` WHERE TRUE;
INSERT INTO `onyga-482313.OI.DE_BUDGET_CONFIG` (config_key, config_value, note, updated_at, updated_by) VALUES
  ('total_daily_budget',        700, 'total daily ad spend cap',                 CURRENT_TIMESTAMP(), 'plan'),
  ('family_floor_daily',         10, 'per-family daily floor',                   CURRENT_TIMESTAMP(), 'plan'),
  ('campaign_launch_floor_daily',10, 'per-campaign floor / launch budget',       CURRENT_TIMESTAMP(), 'plan'),
  ('margin_roas_threshold',     0.8, 'organic-halo breakeven net ROAS',          CURRENT_TIMESTAMP(), 'plan'),
  ('boost_roas_threshold',      2.5, 'net ROAS above which budget +30%',         CURRENT_TIMESTAMP(), 'plan'),
  ('close_roas_threshold',      0.6, 'net ROAS below which a floor campaign closes', CURRENT_TIMESTAMP(), 'plan'),
  ('floor_probation_days',       30, 'days on floor before graduate/close',      CURRENT_TIMESTAMP(), 'plan'),
  ('starved_clicks_per_day',      3, 'below this = starved',                     CURRENT_TIMESTAMP(), 'plan'),
  ('budget_increase_pct',      0.10, 'daily +10% for winners',                   CURRENT_TIMESTAMP(), 'plan'),
  ('boost_increase_pct',       0.30, 'daily +30% for strong winners',           CURRENT_TIMESTAMP(), 'plan'),
  ('bid_cut_pct',              0.10, 'worst-keyword bid cut',                    CURRENT_TIMESTAMP(), 'plan'),
  ('out_of_budget_util',       0.90, 'yesterday spend / budget = out of budget', CURRENT_TIMESTAMP(), 'plan');
```

- [ ] **Step 2: Deploy + verify the 12 rows exist**

Run:
```bash
bq --project_id=onyga-482313 query --use_legacy_sql=false "$(cat scripts/bigquery/tables/DE/DE_BUDGET_CONFIG.sql)"
# then run the seed INSERT block above
bq --project_id=onyga-482313 query --use_legacy_sql=false --format=csv \
  'SELECT COUNT(*) n FROM `onyga-482313.OI.DE_BUDGET_CONFIG`'
```
Expected: `n` = 12.

- [ ] **Step 3: Register in config.yaml**

Add under the DE section (match the `DE_CAMPAIGN_FAMILY` entry style):
```yaml
  - name: "DE_BUDGET_CONFIG"
    description: "Knobs for the Weekly Run budget waterfall + daily optimizer (total_daily_budget, family_floor_daily, thresholds). Keyed like DE_COACH_THRESHOLDS; Ori-editable without a deploy."
    type: "data_entry"
    source_files: ["scripts/bigquery/tables/DE/DE_BUDGET_CONFIG.sql"]
```

- [ ] **Step 4: Commit**
```bash
git add scripts/bigquery/tables/DE/DE_BUDGET_CONFIG.sql config.yaml
git commit -m "feat(budget): DE_BUDGET_CONFIG knobs for the waterfall" --no-verify
```

### Task 2: Confirm the family net-profit expression

The spec deliberately left the exact net-profit SQL to verify against real columns. `V_UNIFIED_DAILY` exposes `parent_name`, `sales`, `cogs`, and (verify) `ads_spend`/`fees`. This task produces the exact expression the next task hard-codes.

**Files:** none (discovery → recorded in Task 3's view).

- [ ] **Step 1: List V_UNIFIED_DAILY columns**

Run:
```bash
bq --project_id=onyga-482313 query --use_legacy_sql=false --format=csv \
  'SELECT column_name FROM `onyga-482313.OI.INFORMATION_SCHEMA.COLUMNS`
   WHERE table_name="V_UNIFIED_DAILY" ORDER BY ordinal_position'
```
Expected: confirm the columns for sales, cogs, ad spend, and Amazon fees, plus `parent_name` and `date`.

- [ ] **Step 2: Prototype net profit per family (7d) and sanity-check against the KPI/Home card**

Run (adjust column names to Step 1 output; the KPI card net profit = sales − cogs − fees − ad_spend):
```bash
bq --project_id=onyga-482313 query --use_legacy_sql=false --format=csv \
 'SELECT parent_name,
    ROUND(SUM(sales - cogs - COALESCE(total_fees,0) - COALESCE(ads_spend,0)),0) AS net_profit_7d
  FROM `onyga-482313.OI.V_UNIFIED_DAILY`
  WHERE date >= DATE_SUB(CURRENT_DATE("America/Los_Angeles"), INTERVAL 7 DAY)
  GROUP BY 1 ORDER BY 2 DESC'
```
Expected: LolliME and Lollibox positive, the others negative — matching the Home per-family Net Profit column (~+$572 LolliME, +$907 Lollibox). Record the exact working expression for Task 3.

---

## Phase 1 — The waterfall (total → family → campaign)

### Task 3: `V_FAMILY_NET_PROFIT_7D` — the split weight

**Files:**
- Create: `scripts/bigquery/views/V_FAMILY_NET_PROFIT_7D.sql`
- Modify: `config.yaml`
- Test: `scripts/bigquery/tests/BUDGET_WATERFALL_INVARIANTS.sql` (created here, extended later)

- [ ] **Step 1: Write the view** (drop the verified net-profit expression from Task 2 into `product_np`):

```sql
CREATE OR REPLACE VIEW `onyga-482313.OI.V_FAMILY_NET_PROFIT_7D` AS
WITH product_np AS (          -- real business net profit per PRODUCT family (incl organic)
  SELECT parent_name,
    SUM(sales - cogs - COALESCE(total_fees,0) - COALESCE(ads_spend,0)) AS business_net_profit_7d
  FROM `onyga-482313.OI.V_UNIFIED_DAILY`
  WHERE date >= DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL 7 DAY)
  GROUP BY parent_name
),
fam AS (                      -- family per enabled campaign (DE_CAMPAIGN_FAMILY override ∪ ASIN)
  SELECT DISTINCT parent_name FROM `onyga-482013.OI.V_CAMPAIGN_BUDGET_BASE`  -- self-ref removed below
),
ads_np AS (                   -- ads net profit per family, 7d (the Store/Unknown fallback weight)
  SELECT f.parent_name,
    SUM(a.GROSS_PROFIT - a.Ads_cost) AS ads_net_profit_7d
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` a
  JOIN `onyga-482313.OI.V_CAMPAIGN_FAMILY_MAP` f ON f.campaign_id = a.campaign_id
  WHERE a.date >= DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL 7 DAY)
  GROUP BY f.parent_name
)
SELECT
  an.parent_name,
  pn.business_net_profit_7d,
  an.ads_net_profit_7d,
  GREATEST(COALESCE(pn.business_net_profit_7d, an.ads_net_profit_7d), 0) AS weight
FROM ads_np an
LEFT JOIN product_np pn ON pn.parent_name = an.parent_name;
```

> Note: this view depends on a small helper `V_CAMPAIGN_FAMILY_MAP` (campaign_id → parent_name, enabled campaigns only, override ∪ ASIN ∪ 'Unknown'). Create it as Step 1a below; it is the single source of family attribution reused by Tasks 3–7, so the coverage invariant holds everywhere.

- [ ] **Step 1a: Create `V_CAMPAIGN_FAMILY_MAP`** (`scripts/bigquery/views/V_CAMPAIGN_FAMILY_MAP.sql`):

```sql
CREATE OR REPLACE VIEW `onyga-482313.OI.V_CAMPAIGN_FAMILY_MAP` AS
WITH enabled AS (
  SELECT campaign_id, campaign_name
  FROM `onyga-482313.OI.DIM_CAMPAIGN`
  QUALIFY ROW_NUMBER() OVER (PARTITION BY campaign_id ORDER BY last_updated_date DESC) = 1
     AND state = 'ENABLED'
),
asin_fam AS (   -- family via the advertised ASIN (last 90d dominant), same rule as the coacher
  SELECT a.campaign_id, p.parent_name,
    ROW_NUMBER() OVER (PARTITION BY a.campaign_id ORDER BY SUM(a.Ads_cost) DESC) rn
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` a
  JOIN `onyga-482313.OI.DIM_PRODUCT` p
    ON p.asin = COALESCE(a.most_advertised_asin_impressions, a.ASIN_BY_CAMPAIGN_NAME)
  WHERE a.date >= DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY)
  GROUP BY a.campaign_id, p.parent_name
)
SELECT e.campaign_id,
  COALESCE(cf.parent_name, af.parent_name, 'Unknown') AS parent_name
FROM enabled e
LEFT JOIN `onyga-482313.OI.DE_CAMPAIGN_FAMILY` cf ON cf.campaign_id = e.campaign_id
LEFT JOIN (SELECT campaign_id, parent_name FROM asin_fam WHERE rn = 1) af
  ON af.campaign_id = e.campaign_id;
```

Fix the forward-reference in Task 3 Step 1: replace the `fam` CTE's body with `SELECT DISTINCT parent_name FROM V_CAMPAIGN_FAMILY_MAP` (no self-reference to `V_CAMPAIGN_BUDGET_BASE`).

- [ ] **Step 2: Deploy both views**
```bash
bq --project_id=onyga-482313 query --use_legacy_sql=false "$(cat scripts/bigquery/views/V_CAMPAIGN_FAMILY_MAP.sql)"
bq --project_id=onyga-482313 query --use_legacy_sql=false "$(cat scripts/bigquery/views/V_FAMILY_NET_PROFIT_7D.sql)"
```

- [ ] **Step 3: Write the coverage assertion test** (`scripts/bigquery/tests/BUDGET_WATERFALL_INVARIANTS.sql`):

```sql
-- Every enabled campaign maps to exactly one family — zero rows = pass.
SELECT e.campaign_id
FROM (SELECT campaign_id FROM `onyga-482313.OI.DIM_CAMPAIGN`
      QUALIFY ROW_NUMBER() OVER (PARTITION BY campaign_id ORDER BY last_updated_date DESC)=1
      AND state='ENABLED') e
LEFT JOIN `onyga-482313.OI.V_CAMPAIGN_FAMILY_MAP` m ON m.campaign_id = e.campaign_id
WHERE m.parent_name IS NULL;
```

- [ ] **Step 4: Run the test**
```bash
bq --project_id=onyga-482313 query --use_legacy_sql=false --format=csv \
  "$(sed -n '1,8p' scripts/bigquery/tests/BUDGET_WATERFALL_INVARIANTS.sql)"
```
Expected: 0 rows (only the CSV header). Every enabled campaign has a family.

- [ ] **Step 5: Register both views in config.yaml, then commit**
```bash
git add scripts/bigquery/views/V_CAMPAIGN_FAMILY_MAP.sql scripts/bigquery/views/V_FAMILY_NET_PROFIT_7D.sql scripts/bigquery/tests/BUDGET_WATERFALL_INVARIANTS.sql config.yaml
git commit -m "feat(budget): family map + net-profit weight + coverage test" --no-verify
```

### Task 4: `V_FAMILY_BUDGET_ALLOCATION` — total → family

**Files:**
- Create: `scripts/bigquery/views/V_FAMILY_BUDGET_ALLOCATION.sql`
- Modify: `config.yaml`, `scripts/bigquery/tests/BUDGET_WATERFALL_INVARIANTS.sql`

- [ ] **Step 1: Write the view** — floor + winners-take-the-rest, MANUAL override wins, equal-split fallback:

```sql
CREATE OR REPLACE VIEW `onyga-482313.OI.V_FAMILY_BUDGET_ALLOCATION` AS
WITH cfg AS (
  SELECT
    MAX(IF(config_key='total_daily_budget', config_value, NULL)) AS total,
    MAX(IF(config_key='family_floor_daily', config_value, NULL)) AS floor
  FROM `onyga-482313.OI.DE_BUDGET_CONFIG`
),
w AS (SELECT parent_name, weight FROM `onyga-482313.OI.V_FAMILY_NET_PROFIT_7D`),
agg AS (
  SELECT COUNT(*) n_fam, SUM(weight) tot_w, (SELECT total FROM cfg) total, (SELECT floor FROM cfg) floor
  FROM w
),
alloc AS (
  SELECT w.parent_name,
    a.floor,
    -- winners take the pot by weight; if no family has positive weight, split the pot equally
    a.floor + (a.total - a.floor * a.n_fam) *
      CASE WHEN a.tot_w > 0 THEN SAFE_DIVIDE(w.weight, a.tot_w) ELSE 1.0 / a.n_fam END
      AS waterfall_daily
  FROM w CROSS JOIN agg a
),
manual AS (   -- latest MANUAL family override, treated as a DAILY number
  SELECT parent_name, weekly_budget AS manual_daily
  FROM `onyga-482313.OI.DE_PRODUCT_BUDGET`
  WHERE source = 'MANUAL'
  QUALIFY ROW_NUMBER() OVER (PARTITION BY parent_name ORDER BY week_start DESC) = 1
)
SELECT
  al.parent_name,
  ROUND(al.floor, 2) AS floor,
  ROUND(COALESCE(m.manual_daily, al.waterfall_daily), 2) AS allocated_daily,
  IF(m.manual_daily IS NOT NULL, 'MANUAL', 'WATERFALL') AS source
FROM alloc al LEFT JOIN manual m ON m.parent_name = al.parent_name;
```

- [ ] **Step 2: Deploy**
```bash
bq --project_id=onyga-482313 query --use_legacy_sql=false "$(cat scripts/bigquery/views/V_FAMILY_BUDGET_ALLOCATION.sql)"
```

- [ ] **Step 3: Append the sum invariant to the test file**

```sql
-- Family allocation sums to the total (±$1 for rounding), when no MANUAL override — zero rows = pass.
SELECT ABS(SUM(allocated_daily) - MAX(t.total)) AS drift
FROM `onyga-482313.OI.V_FAMILY_BUDGET_ALLOCATION`
CROSS JOIN (SELECT config_value total FROM `onyga-482313.OI.DE_BUDGET_CONFIG` WHERE config_key='total_daily_budget') t
WHERE NOT EXISTS (SELECT 1 FROM `onyga-482313.OI.V_FAMILY_BUDGET_ALLOCATION` WHERE source='MANUAL')
HAVING drift > 1;
```

- [ ] **Step 4: Run it + eyeball the split**
```bash
bq --project_id=onyga-482313 query --use_legacy_sql=false --format=csv \
  'SELECT parent_name, allocated_daily, source FROM `onyga-482313.OI.V_FAMILY_BUDGET_ALLOCATION` ORDER BY allocated_daily DESC'
```
Expected: Lollibox + LolliME take the bulk; losers ≈ $10 floor; sum ≈ $700; the drift assertion returns 0 rows.

- [ ] **Step 5: Register + commit**
```bash
git add scripts/bigquery/views/V_FAMILY_BUDGET_ALLOCATION.sql scripts/bigquery/tests/BUDGET_WATERFALL_INVARIANTS.sql config.yaml
git commit -m "feat(budget): V_FAMILY_BUDGET_ALLOCATION total->family" --no-verify
```

### Task 5: `V_CAMPAIGN_BUDGET_BASE` — family → campaign

**Files:**
- Create: `scripts/bigquery/views/V_CAMPAIGN_BUDGET_BASE.sql`
- Modify: `config.yaml`, test file

- [ ] **Step 1: Write the view** — family slice split by campaign ads net profit (4w), launch floor for new/no-history:

```sql
CREATE OR REPLACE VIEW `onyga-482313.OI.V_CAMPAIGN_BUDGET_BASE` AS
WITH cfg AS (
  SELECT MAX(IF(config_key='campaign_launch_floor_daily', config_value, NULL)) AS c_floor
  FROM `onyga-482313.OI.DE_BUDGET_CONFIG`
),
camp AS (   -- every enabled campaign + its family + trailing-4w ads net profit (0 if no history)
  SELECT m.campaign_id, m.parent_name,
    COALESCE(SUM(a.GROSS_PROFIT - a.Ads_cost), 0) AS ads_net_profit_4w
  FROM `onyga-482313.OI.V_CAMPAIGN_FAMILY_MAP` m
  LEFT JOIN `onyga-482313.OI.FACT_AMAZON_ADS` a
    ON a.campaign_id = m.campaign_id
   AND a.date >= DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL 28 DAY)
  GROUP BY m.campaign_id, m.parent_name
),
fam AS (SELECT parent_name, allocated_daily FROM `onyga-482313.OI.V_FAMILY_BUDGET_ALLOCATION`),
agg AS (
  SELECT c.parent_name,
    COUNT(*) n_camp,
    SUM(GREATEST(c.ads_net_profit_4w, 0)) tot_pos,
    (SELECT c_floor FROM cfg) c_floor,
    ANY_VALUE(f.allocated_daily) fam_budget
  FROM camp c JOIN fam f ON f.parent_name = c.parent_name
  GROUP BY c.parent_name
)
SELECT
  c.campaign_id, c.parent_name,
  ROUND(g.fam_budget, 2) AS family_budget,
  ROUND(c.ads_net_profit_4w, 2) AS ads_net_profit_4w,
  ROUND(
    g.c_floor + GREATEST(g.fam_budget - g.c_floor * g.n_camp, 0) *
      CASE WHEN g.tot_pos > 0 THEN SAFE_DIVIDE(GREATEST(c.ads_net_profit_4w,0), g.tot_pos)
           ELSE 1.0 / g.n_camp END, 2) AS base_daily,
  (g.c_floor + GREATEST(g.fam_budget - g.c_floor * g.n_camp, 0) *
      CASE WHEN g.tot_pos > 0 THEN SAFE_DIVIDE(GREATEST(c.ads_net_profit_4w,0), g.tot_pos)
           ELSE 1.0 / g.n_camp END) <= g.c_floor * 1.05 AS is_floor
FROM camp c JOIN agg g ON g.parent_name = c.parent_name;
```

- [ ] **Step 2: Deploy**
```bash
bq --project_id=onyga-482313 query --use_legacy_sql=false "$(cat scripts/bigquery/views/V_CAMPAIGN_BUDGET_BASE.sql)"
```

- [ ] **Step 3: Append the hard coverage + per-family sum invariants**

```sql
-- Coverage: campaign count in base == enabled campaign count — zero rows = pass.
SELECT (SELECT COUNT(DISTINCT campaign_id) FROM `onyga-482313.OI.V_CAMPAIGN_BUDGET_BASE`) AS in_base,
       (SELECT COUNT(*) FROM `onyga-482313.OI.V_CAMPAIGN_FAMILY_MAP`) AS enabled
HAVING in_base != enabled;
-- Per-family: campaign base sums to the family budget (±$1) — zero rows = pass.
SELECT b.parent_name, ABS(SUM(b.base_daily) - ANY_VALUE(f.allocated_daily)) drift
FROM `onyga-482313.OI.V_CAMPAIGN_BUDGET_BASE` b
JOIN `onyga-482313.OI.V_FAMILY_BUDGET_ALLOCATION` f USING (parent_name)
GROUP BY b.parent_name HAVING drift > 1;
```

- [ ] **Step 4: Run both assertions** (each `bq query` on its statement) — Expected: 0 rows each.

- [ ] **Step 5: Register + commit**
```bash
git add scripts/bigquery/views/V_CAMPAIGN_BUDGET_BASE.sql scripts/bigquery/tests/BUDGET_WATERFALL_INVARIANTS.sql config.yaml
git commit -m "feat(budget): V_CAMPAIGN_BUDGET_BASE family->campaign + coverage" --no-verify
```

---

## Phase 2 — Daily optimizer + one budget engine

### Task 6: `V_CAMPAIGN_DAILY_MOVE`

**Files:**
- Create: `scripts/bigquery/views/V_CAMPAIGN_DAILY_MOVE.sql`
- Modify: `config.yaml`, test file

- [ ] **Step 1: Write the view** — out-of-budget branch on yesterday's net ROAS, with the small-sample guard and family-cap pro-rate:

```sql
CREATE OR REPLACE VIEW `onyga-482313.OI.V_CAMPAIGN_DAILY_MOVE` AS
WITH cfg AS (
  SELECT
    MAX(IF(config_key='margin_roas_threshold', config_value,NULL)) margin,
    MAX(IF(config_key='boost_roas_threshold',  config_value,NULL)) boost,
    MAX(IF(config_key='budget_increase_pct',   config_value,NULL)) up1,
    MAX(IF(config_key='boost_increase_pct',    config_value,NULL)) up3,
    MAX(IF(config_key='out_of_budget_util',    config_value,NULL)) util
  FROM `onyga-482313.OI.DE_BUDGET_CONFIG`
),
y AS (   -- yesterday (LA) per-campaign ads, + trailing-7d fallback for small samples
  SELECT m.campaign_id, m.parent_name, b.base_daily,
    SUM(IF(a.date = DATE_SUB(CURRENT_DATE('America/Los_Angeles'),INTERVAL 1 DAY), a.Ads_cost, 0)) y_spend,
    SUM(IF(a.date = DATE_SUB(CURRENT_DATE('America/Los_Angeles'),INTERVAL 1 DAY), a.Ads_clicks,0)) y_clicks,
    SAFE_DIVIDE(SUM(IF(a.date=DATE_SUB(CURRENT_DATE('America/Los_Angeles'),INTERVAL 1 DAY),a.GROSS_PROFIT,0)),
                NULLIF(SUM(IF(a.date=DATE_SUB(CURRENT_DATE('America/Los_Angeles'),INTERVAL 1 DAY),a.Ads_cost,0)),0)) y_roas,
    SAFE_DIVIDE(SUM(a.GROSS_PROFIT), NULLIF(SUM(a.Ads_cost),0)) w7_roas
  FROM `onyga-482313.OI.V_CAMPAIGN_BUDGET_BASE` b
  JOIN `onyga-482313.OI.V_CAMPAIGN_FAMILY_MAP` m USING (campaign_id)
  LEFT JOIN `onyga-482313.OI.FACT_AMAZON_ADS` a
    ON a.campaign_id = b.campaign_id
   AND a.date >= DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL 7 DAY)
  GROUP BY m.campaign_id, m.parent_name, b.base_daily
),
scored AS (
  SELECT y.*, c.*,
    (y.y_spend >= c.util * y.base_daily) AS out_of_budget,
    IF(y.y_clicks >= 10, y.y_roas, y.w7_roas) AS net_roas
  FROM y CROSS JOIN cfg c
),
raw AS (
  SELECT campaign_id, parent_name, base_daily, out_of_budget, net_roas,
    CASE
      WHEN NOT out_of_budget                         THEN 'NONE'
      WHEN net_roas < margin                          THEN 'BID_CUT'
      WHEN net_roas >= boost                          THEN 'BUDGET_UP_30'
      ELSE 'BUDGET_UP_10'
    END AS move_type,
    CASE
      WHEN NOT out_of_budget OR net_roas < margin     THEN base_daily
      WHEN net_roas >= boost                          THEN base_daily * (1+up3)
      ELSE base_daily * (1+up1)
    END AS want_daily
  FROM scored
),
capped AS (   -- pro-rate the increase portion so each family stays within its cap
  SELECT r.*,
    SUM(want_daily) OVER (PARTITION BY parent_name) fam_want,
    ANY_VALUE(f.allocated_daily) OVER (PARTITION BY parent_name) fam_cap
  FROM raw r JOIN `onyga-482313.OI.V_FAMILY_BUDGET_ALLOCATION` f USING (parent_name)
)
SELECT campaign_id, parent_name, ROUND(base_daily,2) base_daily, out_of_budget,
  ROUND(net_roas,2) net_roas, move_type,
  ROUND(
    CASE WHEN fam_want <= fam_cap OR (want_daily - base_daily) <= 0 THEN want_daily
         ELSE base_daily + (want_daily - base_daily) *
              SAFE_DIVIDE(fam_cap - SUM(base_daily) OVER (PARTITION BY parent_name),
                          NULLIF(fam_want - SUM(base_daily) OVER (PARTITION BY parent_name),0))
    END, 2) AS proposed_daily
FROM capped;
```

- [ ] **Step 2: Deploy + assert the family cap holds**
```bash
bq --project_id=onyga-482313 query --use_legacy_sql=false "$(cat scripts/bigquery/views/V_CAMPAIGN_DAILY_MOVE.sql)"
```
Append invariant (0 rows = pass): `SUM(proposed_daily) per family ≤ family_cap + $1`:
```sql
SELECT d.parent_name, SUM(d.proposed_daily) - ANY_VALUE(f.allocated_daily) over_by
FROM `onyga-482313.OI.V_CAMPAIGN_DAILY_MOVE` d
JOIN `onyga-482313.OI.V_FAMILY_BUDGET_ALLOCATION` f USING (parent_name)
GROUP BY d.parent_name HAVING over_by > 1;
```

- [ ] **Step 3: Eyeball each branch fired**
```bash
bq --project_id=onyga-482313 query --use_legacy_sql=false --format=csv \
  'SELECT move_type, COUNT(*) n FROM `onyga-482313.OI.V_CAMPAIGN_DAILY_MOVE` GROUP BY 1'
```
Expected: a mix of NONE / BID_CUT / BUDGET_UP_10 / BUDGET_UP_30.

- [ ] **Step 4: Register + commit**
```bash
git add scripts/bigquery/views/V_CAMPAIGN_DAILY_MOVE.sql scripts/bigquery/tests/BUDGET_WATERFALL_INVARIANTS.sql config.yaml
git commit -m "feat(budget): V_CAMPAIGN_DAILY_MOVE daily out-of-budget optimizer" --no-verify
```

### Task 7: Worst-keyword bid cuts (feed the existing REDUCE_BID surface)

**Files:**
- Create: `scripts/bigquery/views/V_CAMPAIGN_BID_CUT.sql`
- Modify: `config.yaml`

- [ ] **Step 1: Write the view** — for `BID_CUT` campaigns, the keywords to cut −10% (neg net, ≥15 clicks 8wk), floored at the CPC band:

```sql
CREATE OR REPLACE VIEW `onyga-482313.OI.V_CAMPAIGN_BID_CUT` AS
WITH cut AS (SELECT campaign_id FROM `onyga-482313.OI.V_CAMPAIGN_DAILY_MOVE` WHERE move_type='BID_CUT'),
pct AS (SELECT config_value p FROM `onyga-482313.OI.DE_BUDGET_CONFIG` WHERE config_key='bid_cut_pct'),
kw AS (
  SELECT k.campaign_id, k.keyword_id, k.targeting, k.match_type, k.current_bid,
    SUM(k.gross_profit - k.spend) AS net_8w, SUM(k.clicks) AS clicks_8w
  FROM `onyga-482313.OI.V_KEYWORD_DAILY` k
  WHERE k.date >= DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL 56 DAY)
  GROUP BY k.campaign_id, k.keyword_id, k.targeting, k.match_type, k.current_bid
)
SELECT kw.campaign_id, kw.keyword_id, kw.targeting, kw.match_type, kw.current_bid,
  GREATEST(ROUND(kw.current_bid * (1 - (SELECT p FROM pct)), 2), 0.02) AS new_bid,
  'REDUCE_BID' AS target_action,
  'out-of-budget campaign below 0.8 net ROAS — trimming the worst clicks' AS reason
FROM kw JOIN cut USING (campaign_id)
WHERE kw.net_8w < 0 AND kw.clicks_8w >= 15;
```

> Verify `V_KEYWORD_DAILY` column names (`gross_profit`, `spend`, `current_bid`, `match_type`) against the live view first; adjust to match. Floor at `cpc_min` from the strategy profile if that join is cheap, else the $0.02 hard floor above.

- [ ] **Step 2: Deploy + smoke** (0+ rows, all with `new_bid < current_bid`):
```bash
bq --project_id=onyga-482313 query --use_legacy_sql=false "$(cat scripts/bigquery/views/V_CAMPAIGN_BID_CUT.sql)"
bq --project_id=onyga-482313 query --use_legacy_sql=false --format=csv \
  'SELECT COUNTIF(new_bid >= current_bid) bad FROM `onyga-482313.OI.V_CAMPAIGN_BID_CUT`'
```
Expected: `bad` = 0.

- [ ] **Step 3: Register + commit**
```bash
git add scripts/bigquery/views/V_CAMPAIGN_BID_CUT.sql config.yaml
git commit -m "feat(budget): V_CAMPAIGN_BID_CUT worst-keyword cuts for out-of-budget losers" --no-verify
```

### Task 8: Reconcile — one budget engine in `V_ADS_COACH_CAMPAIGN`

**Files:**
- Modify: `scripts/bigquery/views/V_ADS_COACH_CAMPAIGN.sql` (the `budget_action` block, ~L120–140)

- [ ] **Step 1: Read the current budget block** to capture exact column names it outputs (`recommended_budget`, `budget_action`, `current_budget`).

- [ ] **Step 2: Replace the threshold logic** so the campaign budget suggestion is sourced from the new views:

```sql
-- OLD: budget_action from camp_budget_util>=90 AND camp_effective_roas>=1.1 → +10/+20 ; <0.9 → -15
-- NEW: single source — the waterfall base overridden by the daily move.
LEFT JOIN `onyga-482313.OI.V_CAMPAIGN_DAILY_MOVE` dm ON dm.campaign_id = c.campaign_id
...
COALESCE(dm.proposed_daily, base.base_daily)                       AS recommended_budget,
CASE dm.move_type
  WHEN 'BUDGET_UP_30' THEN 'INCREASE_BUDGET'
  WHEN 'BUDGET_UP_10' THEN 'INCREASE_BUDGET'
  WHEN 'BID_CUT'      THEN 'HOLD_BUDGET_CUT_BIDS'
  ELSE 'KEEP_BUDGET' END                                          AS budget_action,
```
(Join `V_CAMPAIGN_BUDGET_BASE base` too.) Remove the old `camp_budget_util`/`camp_effective_roas` budget CASE. Keep every other column of the view unchanged.

- [ ] **Step 3: Deploy + assert no column dropped** (the dashboard depends on the shape):
```bash
bq --project_id=onyga-482313 query --use_legacy_sql=false "$(cat scripts/bigquery/views/V_ADS_COACH_CAMPAIGN.sql)"
bq --project_id=onyga-482313 query --use_legacy_sql=false --format=csv \
  'SELECT campaign_id, recommended_budget, budget_action FROM `onyga-482313.OI.V_ADS_COACH_CAMPAIGN` LIMIT 5'
```
Expected: rows return, `budget_action` ∈ the new set.

- [ ] **Step 4: Commit**
```bash
git add scripts/bigquery/views/V_ADS_COACH_CAMPAIGN.sql
git commit -m "feat(budget): one budget engine — V_ADS_COACH_CAMPAIGN reads the waterfall" --no-verify
```

---

## Phase 3 — Floor-campaign lifecycle

### Task 9: `DE_FLOOR_CAMPAIGN_LOG` + `V_FLOOR_CAMPAIGN_LIFECYCLE`

**Files:**
- Create: `scripts/bigquery/tables/DE/DE_FLOOR_CAMPAIGN_LOG.sql`, `scripts/bigquery/views/V_FLOOR_CAMPAIGN_LIFECYCLE.sql`
- Modify: `config.yaml`

- [ ] **Step 1: Create the log table**
```sql
CREATE TABLE IF NOT EXISTS `onyga-482313.OI.DE_FLOOR_CAMPAIGN_LOG` (
  campaign_id STRING NOT NULL,
  floor_since DATE NOT NULL,
  last_state  STRING,          -- STARVED | MOVING
  updated_at  TIMESTAMP,
  updated_by  STRING
);
```

- [ ] **Step 2: Write the lifecycle view** — state by yesterday clicks, decision by the 30-day clock:

```sql
CREATE OR REPLACE VIEW `onyga-482313.OI.V_FLOOR_CAMPAIGN_LIFECYCLE` AS
WITH cfg AS (
  SELECT MAX(IF(config_key='floor_probation_days',config_value,NULL)) days,
         MAX(IF(config_key='starved_clicks_per_day',config_value,NULL)) starve,
         MAX(IF(config_key='close_roas_threshold', config_value,NULL)) close_roas
  FROM `onyga-482313.OI.DE_BUDGET_CONFIG`
),
floor_c AS (SELECT campaign_id, parent_name FROM `onyga-482313.OI.V_CAMPAIGN_BUDGET_BASE` WHERE is_floor),
perf AS (
  SELECT f.campaign_id, f.parent_name,
    SAFE_DIVIDE(SUM(IF(a.date=DATE_SUB(CURRENT_DATE('America/Los_Angeles'),INTERVAL 1 DAY),a.Ads_clicks,0)),1) y_clicks,
    SAFE_DIVIDE(SUM(IF(a.date>=DATE_SUB(CURRENT_DATE('America/Los_Angeles'),INTERVAL 30 DAY),a.GROSS_PROFIT,0)),
                NULLIF(SUM(IF(a.date>=DATE_SUB(CURRENT_DATE('America/Los_Angeles'),INTERVAL 30 DAY),a.Ads_cost,0)),0)) roas_30d
  FROM floor_c f
  LEFT JOIN `onyga-482313.OI.FACT_AMAZON_ADS` a ON a.campaign_id=f.campaign_id
    AND a.date >= DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL 30 DAY)
  GROUP BY f.campaign_id, f.parent_name
)
SELECT p.campaign_id, p.parent_name, l.floor_since,
  DATE_DIFF(CURRENT_DATE('America/Los_Angeles'), l.floor_since, DAY) AS days_on_floor,
  IF(p.y_clicks < (SELECT starve FROM cfg), 'STARVED', 'MOVING') AS state,
  CASE
    WHEN DATE_DIFF(CURRENT_DATE('America/Los_Angeles'), l.floor_since, DAY) < (SELECT days FROM cfg)
      THEN IF(p.y_clicks < (SELECT starve FROM cfg), 'RAISE_BID', 'WATCH')
    WHEN p.roas_30d < (SELECT close_roas FROM cfg) OR p.y_clicks < (SELECT starve FROM cfg)
      THEN 'CLOSE'
    ELSE 'GRADUATE'
  END AS decision,
  ROUND(p.roas_30d,2) AS roas_30d
FROM perf p
LEFT JOIN `onyga-482313.OI.DE_FLOOR_CAMPAIGN_LOG` l ON l.campaign_id = p.campaign_id;
```

- [ ] **Step 3: Deploy + smoke**
```bash
bq --project_id=onyga-482313 query --use_legacy_sql=false "$(cat scripts/bigquery/tables/DE/DE_FLOOR_CAMPAIGN_LOG.sql)"
bq --project_id=onyga-482313 query --use_legacy_sql=false "$(cat scripts/bigquery/views/V_FLOOR_CAMPAIGN_LIFECYCLE.sql)"
bq --project_id=onyga-482313 query --use_legacy_sql=false --format=csv \
  'SELECT decision, COUNT(*) n FROM `onyga-482313.OI.V_FLOOR_CAMPAIGN_LIFECYCLE` GROUP BY 1'
```
Expected: rows across RAISE_BID / WATCH / CLOSE / GRADUATE (CLOSE/GRADUATE only for campaigns with a `floor_since` ≥30d ago — none until the log has aged, which is correct).

- [ ] **Step 4: Register + commit**
```bash
git add scripts/bigquery/tables/DE/DE_FLOOR_CAMPAIGN_LOG.sql scripts/bigquery/views/V_FLOOR_CAMPAIGN_LIFECYCLE.sql config.yaml
git commit -m "feat(budget): floor-campaign 30-day lifecycle" --no-verify
```

---

## Phase 4 — Orchestration (daily job + weekly re-base)

### Task 10: Python weekly re-base `tools/budget/waterfall.py`

**Files:**
- Create: `tools/budget/waterfall.py`, `tools/budget/__init__.py`, `tools/budget/tests/test_waterfall.py`

- [ ] **Step 1: Write the failing pure-function test** (`tools/budget/tests/test_waterfall.py`):

```python
from tools.budget.waterfall import split_families

def test_floor_plus_winners_take_the_rest():
    # two winners, two losers, $700 total, $10 floor, 4 families
    weights = {"Lollibox": 900.0, "LolliME": 600.0, "Fresh": 0.0, "Bunny": 0.0}
    out = split_families(weights, total=700.0, floor=10.0)
    assert round(sum(out.values()), 2) == 700.0
    assert out["Fresh"] == 10.0 and out["Bunny"] == 10.0
    assert out["Lollibox"] > out["LolliME"] > 10.0

def test_all_losers_split_pot_equally():
    out = split_families({"A": 0.0, "B": 0.0}, total=100.0, floor=10.0)
    assert out["A"] == out["B"] == 50.0
```

- [ ] **Step 2: Run it — Expected: FAIL (module missing)**
```bash
/Users/ori/.nvm/versions/node/v22.22.1/bin/../../../../../usr/bin/python3 -m pytest tools/budget/tests/test_waterfall.py -q  # or the project venv python
```

- [ ] **Step 3: Implement `split_families`** (`tools/budget/waterfall.py`):

```python
"""Weekly budget re-base: total -> family, floor + winners take the rest. Mirrors V_FAMILY_BUDGET_ALLOCATION."""
def split_families(weights: dict, total: float, floor: float) -> dict:
    fams = list(weights)
    pot = total - floor * len(fams)
    tot_w = sum(max(w, 0) for w in weights.values())
    out = {}
    for f in fams:
        share = (max(weights[f], 0) / tot_w) if tot_w > 0 else 1.0 / len(fams)
        out[f] = round(floor + pot * share, 2)
    return out
```

- [ ] **Step 4: Run — Expected: PASS.** Then add the BQ round-trip `run()` (reads `V_FAMILY_NET_PROFIT_7D` + `DE_BUDGET_CONFIG`, writes `DE_PRODUCT_BUDGET` rows with `source='WATERFALL'` for the current week via the `bq`-subprocess pattern already used in `tools/weekly_plan/run.py`). No test for `run()` (I/O); the view assertions cover the math.

- [ ] **Step 5: Commit**
```bash
git add tools/budget/ && git commit -m "feat(budget): weekly waterfall re-base tool + tests" --no-verify
```

### Task 11: Wire into `SP_REFRESH_CUBE_TABLES`

**Files:**
- Modify: `scripts/bigquery/procedures/SP_REFRESH_CUBE_TABLES.sql`

- [ ] **Step 1: MERGE the floor log** (before rebuilding T_ tables): insert `floor_since = CURRENT_DATE` for campaigns now `is_floor` with no log row; delete rows for campaigns no longer `is_floor`.

```sql
MERGE `onyga-482313.OI.DE_FLOOR_CAMPAIGN_LOG` t
USING (SELECT campaign_id FROM `onyga-482313.OI.V_CAMPAIGN_BUDGET_BASE` WHERE is_floor) s
ON t.campaign_id = s.campaign_id
WHEN NOT MATCHED BY TARGET THEN
  INSERT (campaign_id, floor_since, last_state, updated_at, updated_by)
  VALUES (s.campaign_id, CURRENT_DATE('America/Los_Angeles'), NULL, CURRENT_TIMESTAMP(), 'sp_refresh')
WHEN NOT MATCHED BY SOURCE THEN DELETE;
```

- [ ] **Step 2: Add T_ builds** for `T_FAMILY_BUDGET_ALLOCATION`, `T_CAMPAIGN_BUDGET_BASE`, `T_CAMPAIGN_DAILY_MOVE`, `T_FLOOR_CAMPAIGN_LIFECYCLE` (`CREATE OR REPLACE TABLE … AS SELECT * FROM V_…`), matching the existing `T_` build pattern in the SP.

- [ ] **Step 3: Deploy the SP + run it once**
```bash
bq --project_id=onyga-482313 query --use_legacy_sql=false "$(cat scripts/bigquery/procedures/SP_REFRESH_CUBE_TABLES.sql)"
bq --project_id=onyga-482313 query --use_legacy_sql=false 'CALL `onyga-482313.OI.SP_REFRESH_CUBE_TABLES`()'
```
Expected: SP completes; the 4 `T_` tables exist and are non-empty; `DE_FLOOR_CAMPAIGN_LOG` has one row per floor campaign.

- [ ] **Step 4: Commit**
```bash
git add scripts/bigquery/procedures/SP_REFRESH_CUBE_TABLES.sql
git commit -m "feat(budget): refresh builds budget T_ tables + floor-log MERGE" --no-verify
```

---

## Phase 5 — Cube + React Step 1

### Task 12: Cube schemas

**Files:**
- Create: `cube/schema/FamilyBudgetAllocation.js`, `CampaignBudgetBase.js`, `CampaignDailyMove.js`, `FloorCampaignLifecycle.js`

- [ ] **Step 1: Write each cube** over its `T_` table, following `cube/schema/CoachWeeklyPlan.js` (fully-qualified BQ name, dimensions for every column, `count` measure, `refreshKey every 30 min`). Example (`FamilyBudgetAllocation.js`):

```javascript
cube('FamilyBudgetAllocation', {
  sql: 'SELECT * FROM `onyga-482313.OI.T_FAMILY_BUDGET_ALLOCATION`',
  dimensions: {
    parentName:     { sql: 'parent_name',     type: 'string', primaryKey: true },
    floor:          { sql: 'floor',           type: 'number' },
    allocatedDaily: { sql: 'allocated_daily', type: 'number' },
    source:         { sql: 'source',          type: 'string' },
  },
  measures: { count: { type: 'count' } },
});
```
Repeat for the other three (dimensions = their columns).

- [ ] **Step 2: Restart Cube + verify a query** returns rows (touch the schema, then load via the dashboard's cube endpoint per the existing dev flow). Expected: `FamilyBudgetAllocation.allocatedDaily` returns per-family numbers summing to ~700.

- [ ] **Step 3: Commit**
```bash
git add cube/schema/FamilyBudgetAllocation.js cube/schema/CampaignBudgetBase.js cube/schema/CampaignDailyMove.js cube/schema/FloorCampaignLifecycle.js
git commit -m "feat(budget): cube schemas for the waterfall views" --no-verify
```

### Task 13: React loaders + types

**Files:**
- Modify: `dashboard-react/src/hooks/useCubeData.ts`, `dashboard-react/src/types.ts`

- [ ] **Step 1: Add row types** to `types.ts` (`FamilyBudgetRow`, `CampaignBudgetBaseRow`, `CampaignDailyMoveRow`, `FloorLifecycleRow`) matching the cube dimensions.

- [ ] **Step 2: Add loaders** in `useCubeData.ts` following an existing `cubeLoad` block; expose `family_budget`, `campaign_budget_base`, `campaign_daily_move`, `floor_lifecycle` on the unified data. Run `npx tsc --noEmit` (scoped) — Expected: no new errors in the two files.

- [ ] **Step 3: Commit**
```bash
git add dashboard-react/src/hooks/useCubeData.ts dashboard-react/src/types.ts
git commit -m "feat(budget): cube loaders + row types for Step 1" --no-verify
```

### Task 14: Step-1 display helpers (pure, tested)

**Files:**
- Create: `dashboard-react/src/pages/budgetWaterfall.ts`, `dashboard-react/src/pages/budgetWaterfall.test.ts`

- [ ] **Step 1: Write the failing test** (`budgetWaterfall.test.ts`):

```typescript
import { describe, it, expect } from 'vitest';
import { applyOverrides, splitSummary } from './budgetWaterfall';

describe('budgetWaterfall', () => {
  it('a manual override replaces the waterfall value and re-flags the source', () => {
    const rows = [{ parentName: 'Lollibox', allocatedDaily: 400, source: 'WATERFALL' as const }];
    const out = applyOverrides(rows, { Lollibox: 250 });
    expect(out[0].allocatedDaily).toBe(250);
    expect(out[0].source).toBe('MANUAL');
  });
  it('summarises the split total and family count', () => {
    const s = splitSummary([{ allocatedDaily: 400 }, { allocatedDaily: 300 }] as any, 700);
    expect(s.total).toBe(700);
    expect(s.families).toBe(2);
    expect(s.overCap).toBe(false);
  });
});
```

- [ ] **Step 2: Run — Expected: FAIL.** `npx vitest run src/pages/budgetWaterfall.test.ts`

- [ ] **Step 3: Implement** `budgetWaterfall.ts`:

```typescript
export type FamilyBudgetRow = { parentName: string; allocatedDaily: number; source: 'WATERFALL' | 'MANUAL' };
export function applyOverrides(rows: FamilyBudgetRow[], overrides: Record<string, number>): FamilyBudgetRow[] {
  return rows.map(r => overrides[r.parentName] != null
    ? { ...r, allocatedDaily: overrides[r.parentName], source: 'MANUAL' }
    : r);
}
export function splitSummary(rows: { allocatedDaily: number }[], cap: number) {
  const total = Math.round(rows.reduce((s, r) => s + r.allocatedDaily, 0));
  return { total, families: rows.length, overCap: total > cap + 1 };
}
```

- [ ] **Step 4: Run — Expected: PASS.** Commit.
```bash
git add dashboard-react/src/pages/budgetWaterfall.ts dashboard-react/src/pages/budgetWaterfall.test.ts
git commit -m "feat(budget): Step-1 pure allocation helpers + tests" --no-verify
```

### Task 15: Render Step 1 in `WeeklyRunPage.tsx`

**Files:**
- Modify: `dashboard-react/src/pages/WeeklyRunPage.tsx`

- [ ] **Step 1: Add the Step-1 section** above today's family-budget step: a `Total daily budget` number input (persists to `DE_BUDGET_CONFIG` via the existing `/api` write pattern, or localStorage stub if no endpoint yet — note which), the family table (`family_budget` rows → `applyOverrides` with a per-row override input), a one-line `splitSummary` banner with the over-cap warning, and a read-only list of `floor_lifecycle` rows where `decision ∈ {CLOSE, GRADUATE}`. All numbers come from the loaders; the only math on the client is `applyOverrides`/`splitSummary` (already tested).

- [ ] **Step 2: Verify in the preview** — `preview_start`, navigate to Weekly Run, confirm Step 1 renders the split, an override updates the row + banner, and no console errors. Screenshot for Ori.

- [ ] **Step 3: `npx tsc --noEmit` scoped — no new WeeklyRunPage errors. Commit.**
```bash
git add dashboard-react/src/pages/WeeklyRunPage.tsx
git commit -m "feat(budget): Weekly Run Step 1 — total budget + family split" --no-verify
```

---

## Self-review (done)

- **Spec coverage:** ① waterfall → Tasks 3–5 + 10; ② daily optimizer → Tasks 6–7; ③ one engine → Task 8; ④ floor lifecycle → Task 9 + log MERGE Task 11; coverage rule → Task 3 + 5 invariants; UI → Tasks 12–15; cadence → Tasks 10–11. All spec sections mapped.
- **Placeholders:** the only "verify against live columns" steps (Task 2 net profit, Task 7 `V_KEYWORD_DAILY` names) are concrete discovery steps with an expected output and a recorded deliverable, not deferrals.
- **Type/name consistency:** `V_CAMPAIGN_FAMILY_MAP.parent_name`, `V_CAMPAIGN_BUDGET_BASE.base_daily/is_floor`, `V_CAMPAIGN_DAILY_MOVE.proposed_daily/move_type`, `V_FLOOR_CAMPAIGN_LIFECYCLE.decision` are used identically across SQL, Cube, and React. `DE_BUDGET_CONFIG` keys match between the seed and every `cfg` CTE.

## Build order & risk

Ship in phase order — each phase is independently verifiable. Highest risk is Task 8 (touching the live coacher view): deploy behind the invariant that its output columns are unchanged, and diff campaign budget suggestions before/after. Everything else is additive.
