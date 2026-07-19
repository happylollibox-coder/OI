# Launch-Ramp Forecast Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the new-product demand forecast so a launch's month-to-month shape follows its chosen donor's *de-seasonalized* growth ramp times a trustworthy *real calendar*, eliminating the Bunny "August craters to 80" artifact.

**Architecture:** Two new views — `V_HOUSE_SEASONALITY` (mature-blend calendar) and `V_LAUNCH_RAMP` (donor growth by product age) — feed a rewritten Part D of `V_FORECAST_DEMAND`. Phase-1/2 forecast becomes `anchor × ramp(age_F)/ramp(age_now) × season(cal_F)/season(cal_now) × days`, with a thin-history reasonableness cap. Phase 3 (Parts A–C) is untouched, and the view's output column shape is preserved so `SP_LOAD_FACT_FORECAST_DEMAND` keeps working.

**Tech Stack:** BigQuery Standard SQL (views deployed via `bq query`), Cube.js (`ForecastDemand` reads the view live, 6h refreshKey), `config.yaml` object registry.

**Spec:** `docs/superpowers/specs/2026-07-19-launch-ramp-forecast-design.md`

---

## Verified reference numbers (for expected outputs)

House-blend index (≥540-day products = Lollibox + Fresh, `num_days ≥ 15`):

| mo | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 | 11 | 12 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| idx | .527 | .548 | .645 | .920 | .477 | .468 | **.417** | **.583** | .624 | .691 | 1.680 | 4.295 |

LolliME de-seasonalized ramp (normalized to age 1, plateau-held at age 6):

| age | 1 | 2 | 3 | 4 | 5 | 6 | 7+ |
|---|---|---|---|---|---|---|---|
| ramp | 1.000 | 1.055 | 1.648 | 1.680 | 2.127 | 2.240 | 2.240 |

Bunny expected (donor LolliME, family anchor ~7.5/day, age 3 = July):
Jul 233 · **Aug ~331** · Sep ~434 · Oct ~523 · Nov ~1,165 (5× cap) · Dec ~1,165 (5× cap).

---

## File structure

- **Create** `scripts/bigquery/views/V_HOUSE_SEASONALITY.sql` — mature-blend calendar index.
- **Create** `scripts/bigquery/views/V_LAUNCH_RAMP.sql` — donor growth by launch age.
- **Modify** `scripts/bigquery/views/V_PRODUCT_SEASONALITY_INDEX.sql` — `num_days ≥ 15` guard.
- **Modify** `scripts/bigquery/views/V_FORECAST_DEMAND.sql` — Part D rewrite (CTEs `trailing_14d`→`model_based`).
- **Modify** `config.yaml` — register the two new views.

All BigQuery deploys use: `bq --project_id=onyga-482313 query --use_legacy_sql=false < FILE.sql`
(the file contains a single `CREATE OR REPLACE VIEW`).

---

## Task 1: `V_HOUSE_SEASONALITY`

**Files:**
- Create: `scripts/bigquery/views/V_HOUSE_SEASONALITY.sql`
- Modify: `config.yaml`

- [ ] **Step 1: Write the view SQL**

```sql
CREATE OR REPLACE VIEW `onyga-482313.OI.V_HOUSE_SEASONALITY` AS
-- House seasonality: volume-weighted calendar-month index blended across
-- "mature" products (>=540 days of history, i.e. two-ish annual cycles so each
-- calendar month is sampled at a settled age, not mid-launch). Serves as the
-- fallback "real calendar" for new-product forecasting whose donor is too young
-- to define its own seasonality. num_days>=15 drops launch-exclusion remnant months.
-- Index = month_daily_rate / annual_daily_rate (1.0 = average month).
-- Consumed by V_LAUNCH_RAMP and V_FORECAST_DEMAND (Phase 1 & 2).
WITH mature_family AS (
  SELECT family
  FROM `onyga-482313.OI.T_UNIFIED_DAILY`
  WHERE units > 0 AND family IS NOT NULL
  GROUP BY 1
  HAVING DATE_DIFF(CURRENT_DATE(), MIN(date), DAY) >= 540
),
mature_months AS (
  SELECT si.calendar_month, si.total_units, si.num_days
  FROM `onyga-482313.OI.V_PRODUCT_SEASONALITY_INDEX` si
  JOIN mature_family mf ON si.family = mf.family
  WHERE si.num_days >= 15
),
blend AS (
  SELECT calendar_month,
    SAFE_DIVIDE(SUM(total_units), SUM(num_days)) AS daily_rate
  FROM mature_months
  GROUP BY 1
),
annual AS (
  SELECT SAFE_DIVIDE(SUM(total_units), SUM(num_days)) AS annual_daily_rate
  FROM mature_months
)
SELECT b.calendar_month,
  ROUND(SAFE_DIVIDE(b.daily_rate, a.annual_daily_rate), 4) AS house_season_index
FROM blend b, annual a
ORDER BY b.calendar_month;
```

- [ ] **Step 2: Deploy the view**

Run: `bq --project_id=onyga-482313 query --use_legacy_sql=false < scripts/bigquery/views/V_HOUSE_SEASONALITY.sql`
Expected: `Created ... OI.V_HOUSE_SEASONALITY` (no error).

- [ ] **Step 3: Validate the curve**

Run:
```bash
bq --project_id=onyga-482313 query --use_legacy_sql=false --format=pretty \
'SELECT calendar_month, house_season_index,
   ROUND(AVG(house_season_index) OVER (),3) AS mean_should_be_1
 FROM `onyga-482313.OI.V_HOUSE_SEASONALITY` ORDER BY 1'
```
Expected: 12 rows; `mean_should_be_1` ≈ 1.0; month 8 (0.58) **>** month 7 (0.42); month 12 ≈ 4.3. No August crater.

- [ ] **Step 4: Register in config.yaml**

Add under the views section (near the other `V_FORECAST_*` entries, ~line 664):
```yaml
  - name: "V_HOUSE_SEASONALITY"
    description: "Volume-weighted calendar-month seasonality blended across mature products (>=540 days history, num_days>=15 per month). The fallback 'real calendar' for new-product forecasting when the chosen donor is too young (<2yr) to define its own seasonality. Index 1.0 = average month; Dec ~4.3x. Consumed by V_LAUNCH_RAMP and V_FORECAST_DEMAND."
    source_files: ["scripts/bigquery/views/V_HOUSE_SEASONALITY.sql"]
    dependencies:
      - V_PRODUCT_SEASONALITY_INDEX
      - T_UNIFIED_DAILY
```

- [ ] **Step 5: Commit**

```bash
git add scripts/bigquery/views/V_HOUSE_SEASONALITY.sql config.yaml
git commit -m "feat(forecast): add V_HOUSE_SEASONALITY mature-blend calendar"
```

---

## Task 2: `V_PRODUCT_SEASONALITY_INDEX` — num_days guard

**Files:**
- Modify: `scripts/bigquery/views/V_PRODUCT_SEASONALITY_INDEX.sql`

This kills the LolliME August-0.251 (2-day) artifact and gates the future donor-own-season path. A thin month (<15 qualifying days) falls back to the product's mean index over its non-thin months (a neutral value), instead of emitting noise.

- [ ] **Step 1: Verify the current bug is present**

Run:
```bash
bq --project_id=onyga-482313 query --use_legacy_sql=false --format=pretty \
'SELECT calendar_month, num_days, seasonality_index
 FROM `onyga-482313.OI.V_PRODUCT_SEASONALITY_INDEX`
 WHERE product="Mint LolliME" AND calendar_month=8'
```
Expected (before fix): `num_days=2, seasonality_index=0.251`.

- [ ] **Step 2: Edit the final SELECT to add the guard**

Replace the final `SELECT` (lines 65-76) with:
```sql
SELECT
  mr.product,
  mr.family,
  mr.calendar_month,
  mr.total_units,
  mr.num_days,
  ROUND(mr.daily_rate, 2) AS daily_rate,
  ROUND(aa.avg_daily_rate, 2) AS avg_daily_rate,
  -- Seasonality index: this month vs annual average. Thin months (<15 qualifying
  -- days after the 60-day launch exclusion) are unreliable — a month sampled from
  -- only a few days produces noise (e.g. LolliME Aug = 2 days -> 0.251). Fall back
  -- to the product's mean index over its trustworthy (>=15-day) months.
  ROUND(
    CASE
      WHEN mr.num_days >= 15
        THEN SAFE_DIVIDE(mr.daily_rate, NULLIF(aa.avg_daily_rate, 0))
      ELSE COALESCE(gm.good_month_mean_index, 1.0)
    END, 3) AS seasonality_index
FROM monthly_rates mr
JOIN annual_avg aa ON mr.product = aa.product
LEFT JOIN (
  SELECT product,
    AVG(SAFE_DIVIDE(daily_rate, NULLIF(prod_avg, 0))) AS good_month_mean_index
  FROM (
    SELECT m.product, m.daily_rate,
      (SELECT avg_daily_rate FROM annual_avg a WHERE a.product = m.product) AS prod_avg
    FROM monthly_rates m
    WHERE m.num_days >= 15
  )
  GROUP BY product
) gm ON gm.product = mr.product;
```

- [ ] **Step 3: Deploy**

Run: `bq --project_id=onyga-482313 query --use_legacy_sql=false < scripts/bigquery/views/V_PRODUCT_SEASONALITY_INDEX.sql`
Expected: `Created ... V_PRODUCT_SEASONALITY_INDEX`.

- [ ] **Step 4: Validate the fix**

Run:
```bash
bq --project_id=onyga-482313 query --use_legacy_sql=false --format=pretty \
'SELECT calendar_month, num_days, seasonality_index
 FROM `onyga-482313.OI.V_PRODUCT_SEASONALITY_INDEX`
 WHERE product="Mint LolliME" AND calendar_month=8'
```
Expected (after fix): `num_days=2`, `seasonality_index` ≈ the product's good-month mean (roughly 0.5–0.7), **not** 0.251.

- [ ] **Step 5: Regression — mature product unchanged**

Run:
```bash
bq --project_id=onyga-482313 query --use_legacy_sql=false --format=pretty \
'SELECT calendar_month, seasonality_index FROM `onyga-482313.OI.V_PRODUCT_SEASONALITY_INDEX`
 WHERE product="Blue Lollibox" ORDER BY 1'
```
Expected: all 12 months have `num_days ≥ 15`, so every index is unchanged from before (Dec ≈ 5.1). No row shifted.

- [ ] **Step 6: Commit**

```bash
git add scripts/bigquery/views/V_PRODUCT_SEASONALITY_INDEX.sql
git commit -m "fix(forecast): guard thin-history months in seasonality index"
```

---

## Task 3: `V_LAUNCH_RAMP`

**Files:**
- Create: `scripts/bigquery/views/V_LAUNCH_RAMP.sql`
- Modify: `config.yaml`

- [ ] **Step 1: Write the view SQL**

```sql
CREATE OR REPLACE VIEW `onyga-482313.OI.V_LAUNCH_RAMP` AS
-- Donor launch-growth curve by PRODUCT AGE, de-seasonalized against the house
-- calendar (V_HOUSE_SEASONALITY) so it is pure growth with Christmas stripped out.
-- Normalized to age 1 = 1.000, forced monotonic (running max), and held flat after
-- PLATEAU_AGE = 6 to drop the noisy de-seasonalized tail. One row per
-- (donor_product, launch_age_month). Consumed by V_FORECAST_DEMAND (Phase 1 & 2):
-- a new product inherits its chosen donor's ramp shape by its own age.
WITH const AS (SELECT 6 AS plateau_age),
donor_first AS (
  SELECT product_short_name AS donor, MIN(date) AS first_sale
  FROM `onyga-482313.OI.T_UNIFIED_DAILY`
  WHERE units > 0 AND product_short_name IS NOT NULL
  GROUP BY 1
),
donor_age_month AS (
  SELECT
    d.donor,
    DATE_DIFF(DATE_TRUNC(u.date, MONTH), DATE_TRUNC(d.first_sale, MONTH), MONTH) + 1 AS age_month,
    EXTRACT(MONTH FROM u.date) AS cal_month,
    SUM(u.units) AS units,
    COUNT(DISTINCT u.date) AS days
  FROM `onyga-482313.OI.T_UNIFIED_DAILY` u
  JOIN donor_first d ON u.product_short_name = d.donor
  WHERE u.units > 0
  GROUP BY 1, 2, 3
),
-- De-seasonalize: daily rate / house index for that calendar month.
-- Ignore thin (<10-day) partial launch/tail months.
deseason AS (
  SELECT dam.donor, dam.age_month,
    SAFE_DIVIDE(SAFE_DIVIDE(dam.units, dam.days), NULLIF(hs.house_season_index, 0)) AS growth_raw
  FROM donor_age_month dam
  JOIN `onyga-482313.OI.V_HOUSE_SEASONALITY` hs ON hs.calendar_month = dam.cal_month
  WHERE dam.days >= 10
),
base AS (
  SELECT donor, growth_raw AS base_growth FROM deseason WHERE age_month = 1
),
norm AS (
  SELECT ds.donor, ds.age_month,
    SAFE_DIVIDE(ds.growth_raw, NULLIF(b.base_growth, 0)) AS ramp_norm
  FROM deseason ds JOIN base b ON b.donor = ds.donor
),
cummax AS (
  SELECT donor, age_month,
    MAX(ramp_norm) OVER (PARTITION BY donor ORDER BY age_month
      ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS ramp_mono
  FROM norm
),
plateau_val AS (
  SELECT donor,
    MAX(IF(age_month = (SELECT plateau_age FROM const), ramp_mono, NULL)) AS plateau_ramp
  FROM cummax GROUP BY 1
)
SELECT
  c.donor AS donor_product,
  c.age_month AS launch_age_month,
  ROUND(
    CASE WHEN c.age_month >= (SELECT plateau_age FROM const)
         THEN COALESCE(pv.plateau_ramp, c.ramp_mono)
         ELSE c.ramp_mono END, 4) AS ramp_factor
FROM cummax c
LEFT JOIN plateau_val pv ON pv.donor = c.donor
ORDER BY c.donor, c.age_month;
```

- [ ] **Step 2: Deploy**

Run: `bq --project_id=onyga-482313 query --use_legacy_sql=false < scripts/bigquery/views/V_LAUNCH_RAMP.sql`
Expected: `Created ... V_LAUNCH_RAMP`.

- [ ] **Step 3: Validate the LolliME ramp**

Run:
```bash
bq --project_id=onyga-482313 query --use_legacy_sql=false --format=pretty \
'SELECT launch_age_month, ramp_factor FROM `onyga-482313.OI.V_LAUNCH_RAMP`
 WHERE donor_product="Mint LolliME" ORDER BY 1'
```
Expected: age 1 = 1.000, monotonic non-decreasing, age 3 ≈ 1.65, age 5 ≈ 2.13, age ≥ 6 flat ≈ 2.24. No decreases; no tail spike.

- [ ] **Step 4: Register in config.yaml**

```yaml
  - name: "V_LAUNCH_RAMP"
    description: "Donor launch-growth curve by product age, de-seasonalized against V_HOUSE_SEASONALITY so it is pure growth (Christmas stripped). Normalized to age 1 = 1.0, monotonic, held flat after plateau age 6. One row per (donor_product, launch_age_month). A new product inherits its DE_NEW_PRODUCT_MODEL donor's ramp shape by its own age in V_FORECAST_DEMAND (Phase 1 & 2). LolliME ramps ~2.24x by month 6; a flat donor (Bottle) stays ~1.0."
    source_files: ["scripts/bigquery/views/V_LAUNCH_RAMP.sql"]
    dependencies:
      - V_HOUSE_SEASONALITY
      - T_UNIFIED_DAILY
```

- [ ] **Step 5: Commit**

```bash
git add scripts/bigquery/views/V_LAUNCH_RAMP.sql config.yaml
git commit -m "feat(forecast): add V_LAUNCH_RAMP donor growth-by-age curve"
```

---

## Task 4: Rewrite `V_FORECAST_DEMAND` Part D

**Files:**
- Modify: `scripts/bigquery/views/V_FORECAST_DEMAND.sql` (Part D: CTEs `model_seasonality` … `model_based`, lines ~461-566)

**Contract:** The final `SELECT * FROM final` column list MUST stay identical (product, family, forecast_year, forecast_month, family_forecast_units, product_share, forecast_units, is_new_product, is_draft, sqrt_lift, peak_days, offseason_days, peak_holidays, forecast_phase, model_product, is_stable) — `SP_LOAD_FACT_FORECAST_DEMAND` inserts an explicit column list and will error if the shape drifts.

- [ ] **Step 1: Replace the Part-D CTE block**

Delete `model_seasonality`, `model_first_month`, `trailing_14d`, `model_forecast`, and `model_based` (the block from `-- D2:` through the end of `model_based`) and replace with:

```sql
-- D-const: reasonableness-cap knobs (guard B) + plateau reference
model_const AS (
  SELECT 2.0 AS ramp_ceil, 5.0 AS season_ceil, 120 AS thin_history_days
),

-- D1: current-date anchors
now_ref AS (
  SELECT EXTRACT(YEAR FROM CURRENT_DATE()) AS cur_yr,
         EXTRACT(MONTH FROM CURRENT_DATE()) AS cur_mo,
         DATE_TRUNC(CURRENT_DATE(), MONTH) AS cur_month_start
),

-- D2: anchor daily rate per model product.
--   Phase 2 -> own trailing-14d rate; Phase 1 -> donor month-1 rate / phase1 split.
trailing_14d AS (
  SELECT product_short_name AS product, SAFE_DIVIDE(SUM(units), 14.0) AS trailing_daily_rate
  FROM `onyga-482313.OI.T_UNIFIED_DAILY`
  WHERE date >= DATE_SUB(CURRENT_DATE(), INTERVAL 14 DAY)
  GROUP BY 1
),
model_first_month AS (
  SELECT product, daily_rate AS month1_daily_rate
  FROM `onyga-482313.OI.V_PRODUCT_LAUNCH_MODEL`
  WHERE month_num = 2
),

-- D3: donor plateau ramp (for target ages beyond the donor's known ages)
donor_plateau AS (
  SELECT donor_product, MAX(ramp_factor) AS plateau_ramp
  FROM `onyga-482313.OI.V_LAUNCH_RAMP` GROUP BY 1
),

-- D4: donor maturity — donor uses its OWN seasonality only if it has >=730 days
-- of history; else fall back to house blend. (Today only Lollibox qualifies.)
donor_maturity AS (
  SELECT product_short_name AS donor,
    DATE_DIFF(CURRENT_DATE(), MIN(date), DAY) >= 730 AS donor_is_mature
  FROM `onyga-482313.OI.T_UNIFIED_DAILY`
  WHERE units > 0 AND product_short_name IS NOT NULL
  GROUP BY 1
),

-- D5: per-product own history length (gates guard B)
product_history_days AS (
  SELECT product_short_name AS product, DATE_DIFF(MAX(date), MIN(date), DAY) AS hist_days
  FROM `onyga-482313.OI.T_UNIFIED_DAILY`
  WHERE units > 0 GROUP BY 1
),

-- D6: month grid × phase-1/2 products (envelope-less families only, as before)
model_grid AS (
  SELECT mp.product, mp.family, mp.model_product, mp.forecast_phase,
    mp.estimated_start_selling_date,
    tf.yr AS forecast_year, tf.mo AS forecast_month,
    -- product ages (months) now and at the target month
    DATE_DIFF(DATE_TRUNC(CURRENT_DATE(), MONTH),
              DATE_TRUNC(mp.estimated_start_selling_date, MONTH), MONTH) + 1 AS age_now,
    DATE_DIFF(DATE(tf.yr, tf.mo, 1),
              DATE_TRUNC(mp.estimated_start_selling_date, MONTH), MONTH) + 1 AS age_f,
    DATE_DIFF(DATE_ADD(DATE(tf.yr, tf.mo, 1), INTERVAL 1 MONTH), DATE(tf.yr, tf.mo, 1), DAY) AS days_in_month
  FROM product_phases mp
  CROSS JOIN (SELECT DISTINCT yr, mo FROM tagged_future) tf
  LEFT JOIN family_has_envelope fhe ON fhe.family = mp.family
  WHERE mp.forecast_phase IN ('PHASE_1', 'PHASE_2') AND mp.model_product IS NOT NULL
    AND fhe.family IS NULL
),

-- D7: assemble factors
model_forecast AS (
  SELECT
    g.product, g.family, g.model_product, g.forecast_phase,
    g.estimated_start_selling_date, g.forecast_year, g.forecast_month, g.days_in_month,
    g.age_now, g.age_f,
    -- anchor rate
    CASE
      WHEN g.forecast_phase = 'PHASE_1'
        THEN COALESCE(SAFE_DIVIDE(mfm.month1_daily_rate, p1s.phase1_product_count), 0)
      ELSE COALESCE(t14.trailing_daily_rate, mfm.month1_daily_rate, 0)
    END AS anchor_rate,
    -- ramp factors (COALESCE to donor plateau when target age exceeds known ages)
    COALESCE(r_now.ramp_factor, dp.plateau_ramp, 1.0) AS ramp_now,
    COALESCE(r_f.ramp_factor,   dp.plateau_ramp, 1.0) AS ramp_f,
    -- seasonality: donor-own if mature else house blend
    COALESCE(CASE WHEN dm.donor_is_mature THEN own_now.seasonality_index END,
             hs_now.house_season_index, 1.0) AS season_now,
    COALESCE(CASE WHEN dm.donor_is_mature THEN own_f.seasonality_index END,
             hs_f.house_season_index, 1.0) AS season_f,
    COALESCE(ph.hist_days, 0) AS hist_days
  FROM model_grid g
  CROSS JOIN now_ref nr
  LEFT JOIN trailing_14d t14 ON t14.product = g.product
  LEFT JOIN model_first_month mfm ON mfm.product = g.model_product
  LEFT JOIN phase1_split p1s ON p1s.family = g.family AND p1s.model_product = g.model_product
  LEFT JOIN `onyga-482313.OI.V_LAUNCH_RAMP` r_now
    ON r_now.donor_product = g.model_product AND r_now.launch_age_month = g.age_now
  LEFT JOIN `onyga-482313.OI.V_LAUNCH_RAMP` r_f
    ON r_f.donor_product = g.model_product AND r_f.launch_age_month = g.age_f
  LEFT JOIN donor_plateau dp ON dp.donor_product = g.model_product
  LEFT JOIN donor_maturity dm ON dm.donor = g.model_product
  LEFT JOIN `onyga-482313.OI.V_PRODUCT_SEASONALITY_INDEX` own_now
    ON own_now.product = g.model_product AND own_now.calendar_month = nr.cur_mo
  LEFT JOIN `onyga-482313.OI.V_PRODUCT_SEASONALITY_INDEX` own_f
    ON own_f.product = g.model_product AND own_f.calendar_month = g.forecast_month
  LEFT JOIN `onyga-482313.OI.V_HOUSE_SEASONALITY` hs_now ON hs_now.calendar_month = nr.cur_mo
  LEFT JOIN `onyga-482313.OI.V_HOUSE_SEASONALITY` hs_f ON hs_f.calendar_month = g.forecast_month
  LEFT JOIN product_history_days ph ON ph.product = g.product
),

-- D8: final model-based output (same columns as family_based)
model_based AS (
  SELECT
    mf.product, mf.family, mf.forecast_year, mf.forecast_month,
    CAST(NULL AS INT64)   AS family_forecast_units,
    CAST(NULL AS FLOAT64) AS product_share,
    CASE
      -- zero before launch month
      WHEN mf.estimated_start_selling_date IS NOT NULL
        AND DATE(mf.forecast_year, mf.forecast_month, 1)
            < DATE_TRUNC(mf.estimated_start_selling_date, MONTH)
      THEN 0
      ELSE (
        SELECT
          CASE
            WHEN mf.hist_days < mc.thin_history_days
              THEN LEAST(
                     -- RAMP_CEIL cap on the growth factor, then SEASON_CEIL total cap
                     ROUND(mf.anchor_rate
                           * LEAST(SAFE_DIVIDE(mf.ramp_f, NULLIF(mf.ramp_now,0)), mc.ramp_ceil)
                           * SAFE_DIVIDE(mf.season_f, NULLIF(mf.season_now,0))
                           * mf.days_in_month),
                     ROUND(mc.season_ceil * mf.anchor_rate * mf.days_in_month))
            ELSE ROUND(mf.anchor_rate
                       * SAFE_DIVIDE(mf.ramp_f, NULLIF(mf.ramp_now,0))
                       * SAFE_DIVIDE(mf.season_f, NULLIF(mf.season_now,0))
                       * mf.days_in_month)
          END
        FROM model_const mc
      )
    END AS forecast_units,
    TRUE  AS is_new_product,
    TRUE  AS is_draft,
    CAST(NULL AS FLOAT64) AS sqrt_lift,
    0     AS peak_days,
    CAST(mf.days_in_month AS INT64) AS offseason_days,
    CAST(NULL AS STRING) AS peak_holidays,
    mf.forecast_phase,
    mf.model_product,
    FALSE AS is_stable
  FROM model_forecast mf
)
```

Note: keep the existing `phase1_split` CTE (Part D1.5) — it is still referenced. `model_seasonality` is deleted (no longer used).

- [ ] **Step 2: Deploy the view**

Run: `bq --project_id=onyga-482313 query --use_legacy_sql=false < scripts/bigquery/views/V_FORECAST_DEMAND.sql`
Expected: `Created ... V_FORECAST_DEMAND` with no "column"/"resources" error. If it errors on a missing CTE, confirm `phase1_split`, `product_phases`, `family_has_envelope`, `tagged_future` still exist above Part D.

- [ ] **Step 3: Validate Bunny — August no longer craters**

Run:
```bash
bq --project_id=onyga-482313 query --use_legacy_sql=false --format=pretty \
'SELECT forecast_month, SUM(forecast_units) AS bunny_units
 FROM `onyga-482313.OI.V_FORECAST_DEMAND`
 WHERE family="Bunny" AND forecast_year=2026 AND forecast_month BETWEEN 7 AND 12
 GROUP BY 1 ORDER BY 1'
```
Expected: month 8 (~330) **>** month 7 (~233); rising Sep (~430) / Oct (~520); Nov & Dec pinned near ~1,165 by the SEASON_CEIL cap. August is NOT ~80.

- [ ] **Step 4: Regression — Phase-3 mature family unchanged**

Run:
```bash
bq --project_id=onyga-482313 query --use_legacy_sql=false --format=pretty \
'SELECT forecast_phase, COUNT(*) n, ROUND(SUM(forecast_units)) units
 FROM `onyga-482313.OI.V_FORECAST_DEMAND`
 WHERE family="Lollibox" AND forecast_year=2026 GROUP BY 1'
```
Expected: all `PHASE_3`; totals identical to a pre-change snapshot (capture the same query's output before Step 2 for comparison).

- [ ] **Step 5: Materialize FACT + confirm loader still accepts the shape**

Run:
```bash
bq --project_id=onyga-482313 query --use_legacy_sql=false 'CALL `onyga-482313.OI.SP_LOAD_FACT_FORECAST_DEMAND`()'
bq --project_id=onyga-482313 query --use_legacy_sql=false --format=pretty \
'SELECT forecast_month, SUM(forecast_units) u FROM `onyga-482313.OI.FACT_FORECAST_DEMAND`
 WHERE family="Bunny" AND forecast_year=2026 AND forecast_month BETWEEN 7 AND 9 GROUP BY 1 ORDER BY 1'
```
Expected: `CALL` succeeds (no column-mismatch error); FACT rows match the view (Aug > Jul).

- [ ] **Step 6: Commit**

```bash
git add scripts/bigquery/views/V_FORECAST_DEMAND.sql
git commit -m "feat(forecast): donor ramp x house-season model for Phase 1/2 launches"
```

---

## Task 5: Refresh the Plan chart & verify end-to-end

**Files:** none (deploy/refresh only)

- [ ] **Step 1: Bust the Cube cache**

The `ForecastDemand` cube reads `V_FORECAST_DEMAND` live with a 6h `refreshKey`. Locally, touch the schema to force a rebuild:
```bash
touch cube/schema/ForecastDemand.js
```
In prod the change appears after the 6h refreshKey cycles (or a Cube redeploy).

- [ ] **Step 2: Verify via the same query the chart runs**

Run:
```bash
bq --project_id=onyga-482313 query --use_legacy_sql=false --format=pretty \
'SELECT forecast_month, SUM(forecast_units) u FROM `onyga-482313.OI.V_FORECAST_DEMAND`
 WHERE family="Bunny" AND forecast_year=2026 GROUP BY 1 ORDER BY 1'
```
Expected: the monthly series the Plan chart will render — August up from 80 to ~330.

- [ ] **Step 3: Confirm on the Plan page (optional, if a preview/dev server is available)**

Load the dashboard Plan page (parent = Bunny), confirm the August bar rises above July and no month craters. Screenshot for the owner.

---

## Self-review notes

- **Spec coverage:** V_HOUSE_SEASONALITY (Task 1) · num_days guard (Task 2) · V_LAUNCH_RAMP (Task 3) · Part-D rewrite with ramp×season + guard B (Task 4) · config.yaml (Tasks 1,3) · refresh chain (Task 5). All spec components mapped.
- **Column-shape contract** preserved in Task 4 (Step 5 verifies the FACT loader).
- **Guard-B params** (2.0 / 5.0 / 120d) live in the `model_const` CTE — the tunable knobs called out in the spec's Testing section; adjust here if the capped Christmas looks wrong to the owner.
- **Deferred:** promoting guard-B constants to a `DE_` table (only if tuning demands it).
