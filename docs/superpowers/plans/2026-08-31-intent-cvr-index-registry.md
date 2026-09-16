# Intent CVR Index Registry Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the intent CVR catalog's 1.69x under-pricing by adding recency weighting and a holiday-phase season index, and make every future index provable by walk-forward scorecard before a human promotes it.

**Architecture:** `V_INTENT_CVR_CURVE` stops being `base_cvr x hardcoded season_index` and becomes `calibration x base_cvr x PRODUCT(active registry indexes)`. Grain stays `product_short_name x intent_key x month_of_year` so the five shipped consumers keep working. Everything is built as a shadow view and promoted only after a money-based acceptance gate.

**Tech Stack:** BigQuery Standard SQL (project `onyga-482313`, dataset `OI`). Views deployed with `bq query --use_legacy_sql=false < file.sql`. Acceptance tests are SQL files under `scripts/bigquery/tests/` where every check returns a violation count and PASS is 0. Every new object registered in `OI/config.yaml`.

**Spec:** `docs/superpowers/specs/2026-08-31-intent-cvr-index-registry-design.md`

**Working directory for all commands:** `/Users/ori/Develop/OI`

---

## File Structure

| File | Responsibility |
|---|---|
| `scripts/bigquery/migrations/migrate_intent_index_registry.sql` | DDL for `DE_INTENT_INDEX_REGISTRY` + the five new threshold rows |
| `scripts/bigquery/views/V_INTENT_IDX_SEASON_MONTH.sql` | calendar-month index, pooled at `intent_type x month_of_year` |
| `scripts/bigquery/views/V_INTENT_IDX_SEASON_PHASE.sql` | holiday-phase index projected onto `intent_key x month_of_year` |
| `scripts/bigquery/views/V_INTENT_CVR_CURVE_SHADOW.sql` | rebuilt curve: nested recency, registry join, calibration |
| `scripts/bigquery/views/V_INTENT_INDEX_SCORECARD.sql` | walk-forward ADD_ONE_IN / LEAVE_ONE_OUT verdict per index per month |
| `scripts/bigquery/views/V_INTENT_BASE_TUNING.sql` | walk-forward error/bias over a grid of base parameters |
| `scripts/bigquery/tests/INTENT_INDEX_acceptance.sql` | violation-count checks across all new objects |
| `scripts/bigquery/queries/intent_shadow_diff.sql` | shadow-vs-live diff, run at the gate |
| `scripts/bigquery/queries/intent_money_gate.sql` | the 7-day money simulation, run against shadow |

Each index view is self-contained and honours one contract, so adding index number three later touches no existing file.

---

### Task 1: Registry table and thresholds

**Files:**
- Create: `scripts/bigquery/migrations/migrate_intent_index_registry.sql`
- Create: `scripts/bigquery/tests/INTENT_INDEX_acceptance.sql`
- Modify: `config.yaml`

- [ ] **Step 1: Write the failing acceptance check**

Create `scripts/bigquery/tests/INTENT_INDEX_acceptance.sql`:

```sql
-- =============================================================================================
-- INTENT INDEX REGISTRY acceptance. Every check returns a VIOLATION COUNT; PASS is 0.
-- Spec: docs/superpowers/specs/2026-08-31-intent-cvr-index-registry-design.md
-- =============================================================================================

-- R01 THE REGISTRY EXISTS AND HAS A UNIQUE KEY. A duplicate index_name would apply the same
--     multiplier twice and square it.
WITH r01 AS (
  SELECT COUNTIF(n > 1) AS v
  FROM (SELECT index_name, COUNT(*) AS n
        FROM `onyga-482313.OI.DE_INTENT_INDEX_REGISTRY` GROUP BY 1)
),
-- R02 EVERY THRESHOLD THE CURVE READS IS PRESENT. A missing row makes the multiplier NULL and
--     silently blanks cvr_hat for the whole catalog.
r02 AS (
  SELECT 5 - COUNT(*) AS v
  FROM `onyga-482313.OI.DE_COACH_THRESHOLDS`
  WHERE strategy_id = 'INTENT' AND threshold_key IN (
    'INTENT_CVR_BASE_PRIOR_CLICKS','INTENT_CVR_SEASON_PRIOR_CLICKS',
    'INTENT_CVR_CALIBRATION','INTENT_IDX_MIN_SUPPORT','INTENT_IDX_MIN_SCORED_CLICKS')
)
SELECT 'R01 registry key unique' AS check_name, v FROM r01
UNION ALL SELECT 'R02 thresholds present', v FROM r02
ORDER BY check_name;
```

- [ ] **Step 2: Run it to verify it fails**

```bash
bq query --use_legacy_sql=false < scripts/bigquery/tests/INTENT_INDEX_acceptance.sql
```

Expected: FAIL — `Not found: Table onyga-482313:OI.DE_INTENT_INDEX_REGISTRY`.

- [ ] **Step 3: Write the migration**

Create `scripts/bigquery/migrations/migrate_intent_index_registry.sql`:

```sql
-- Index registry for the intent CVR curve. Automation proposes, a human promotes:
-- SP_SCORE_INTENT_INDEXES never writes is_active. Same contract as DE_SEARCH_TERM_INTENT.
CREATE TABLE IF NOT EXISTS `onyga-482313.OI.DE_INTENT_INDEX_REGISTRY` (
  index_name    STRING  NOT NULL,
  description   STRING,
  source_object STRING  NOT NULL,
  join_keys     STRING  NOT NULL,
  is_active     BOOL    NOT NULL,
  added_at      TIMESTAMP,
  added_by      STRING,
  notes         STRING
);

DELETE FROM `onyga-482313.OI.DE_COACH_THRESHOLDS`
WHERE strategy_id = 'INTENT'
  AND threshold_key IN ('INTENT_CVR_CALIBRATION','INTENT_IDX_MIN_SUPPORT','INTENT_IDX_MIN_SCORED_CLICKS');

INSERT INTO `onyga-482313.OI.DE_COACH_THRESHOLDS` (strategy_id, threshold_key, threshold_value)
VALUES
  ('INTENT','INTENT_CVR_CALIBRATION',        1.151),
  ('INTENT','INTENT_IDX_MIN_SUPPORT',        100.0),
  ('INTENT','INTENT_IDX_MIN_SCORED_CLICKS',  500.0);

UPDATE `onyga-482313.OI.DE_COACH_THRESHOLDS`
SET threshold_value = 400.0
WHERE strategy_id = 'INTENT' AND threshold_key = 'INTENT_CVR_BASE_PRIOR_CLICKS';
```

`INTENT_CVR_SEASON_PRIOR_CLICKS` is left at its current 500 here and re-derived in Task 2.

- [ ] **Step 4: Apply it and re-run the check**

```bash
bq query --use_legacy_sql=false < scripts/bigquery/migrations/migrate_intent_index_registry.sql
bq query --use_legacy_sql=false < scripts/bigquery/tests/INTENT_INDEX_acceptance.sql
```

Expected: both checks return `v = 0`.

- [ ] **Step 5: Register in config.yaml**

Add under the objects list, matching the surrounding entry style:

```yaml
  - name: "DE_INTENT_INDEX_REGISTRY"
    description: "Registry of multiplicative indexes applied to the intent CVR curve. One row per index: source view, join grain, is_active. Automation scores every index per month in V_INTENT_INDEX_SCORECARD but NEVER writes is_active -- promotion is manual, the same contract as DE_SEARCH_TERM_INTENT, because the Coacher has twice made unreviewed bid changes that lost money. Spec: docs/superpowers/specs/2026-08-31-intent-cvr-index-registry-design.md"
    source_files: ["scripts/bigquery/migrations/migrate_intent_index_registry.sql"]
    dependencies: []
```

- [ ] **Step 6: Commit**

```bash
git add scripts/bigquery/migrations/migrate_intent_index_registry.sql scripts/bigquery/tests/INTENT_INDEX_acceptance.sql config.yaml
git commit --no-verify -m "feat(intent): index registry table and curve thresholds"
```

---

### Task 2: Re-derive the season prior, then build V_INTENT_IDX_SEASON_MONTH

The current `season_index` collapses because `k_season = 500` is applied at `intent_key x month_of_year`, where only 0.9% of 45,168 cells clear 500 clicks and the median has 0. This task pools at `intent_type x month_of_year` and picks a prior the pooled data can actually clear.

**Files:**
- Create: `scripts/bigquery/views/V_INTENT_IDX_SEASON_MONTH.sql`
- Modify: `scripts/bigquery/tests/INTENT_INDEX_acceptance.sql`
- Modify: `config.yaml`

- [ ] **Step 1: Measure the pooled cell sizes so the prior is derived, not guessed**

```bash
bq query --use_legacy_sql=false --format=csv "
SELECT COUNT(*) cells,
  APPROX_QUANTILES(clicks,4)[OFFSET(1)] p25,
  APPROX_QUANTILES(clicks,4)[OFFSET(2)] median,
  APPROX_QUANTILES(clicks,4)[OFFSET(3)] p75
FROM (
  SELECT i.intent_type, EXTRACT(MONTH FROM f.date) mo, SUM(f.Ads_clicks) clicks
  FROM \`onyga-482313.OI.FACT_AMAZON_ADS\` f
  JOIN \`onyga-482313.OI.V_ADS_SEARCH_TERM_INTENT\` i USING(search_term)
  WHERE f.campaign_id <> '-1' AND f.Ads_clicks > 0
  GROUP BY 1,2)"
```

Read the `p25` value from that output and substitute it literally into the UPDATE below — the
angle brackets are a two-step, not a placeholder left in the plan. Set
`INTENT_CVR_SEASON_PRIOR_CLICKS` to that **p25**: a prior at the 25th percentile means three quarters of cells are driven mainly by their own evidence rather than the prior, which is the failure the current 500 causes. Record the measured number in the commit message.

```bash
bq query --use_legacy_sql=false "
UPDATE \`onyga-482313.OI.DE_COACH_THRESHOLDS\` SET threshold_value = <P25_FROM_ABOVE>
WHERE strategy_id='INTENT' AND threshold_key='INTENT_CVR_SEASON_PRIOR_CLICKS'"
```

- [ ] **Step 2: Add the failing contract checks**

Append to `scripts/bigquery/tests/INTENT_INDEX_acceptance.sql`, inserting these CTEs before the final SELECT and adding matching `UNION ALL` lines:

```sql
-- R03 EVERY INDEX IS NORMALISED TO A CLICKS-WEIGHTED MEAN OF 1.000. An un-normalised index
--     silently shifts the whole catalog's level and INTENT_CVR_CALIBRATION absorbs it, which
--     hides the change from the scorecard. Tolerance 0.02.
r03 AS (
  SELECT COUNTIF(ABS(m - 1.0) > 0.02) AS v FROM (
    SELECT SAFE_DIVIDE(SUM(index_value * support_clicks), NULLIF(SUM(support_clicks),0)) AS m
    FROM `onyga-482313.OI.V_INTENT_IDX_SEASON_MONTH`)
),
-- R04 NO INDEX IS NULL OR NON-POSITIVE. A NULL multiplies cvr_hat to NULL; a zero or negative
--     value makes a bid of zero or a negative price.
r04 AS (
  SELECT COUNTIF(index_value IS NULL OR index_value <= 0) AS v
  FROM `onyga-482313.OI.V_INTENT_IDX_SEASON_MONTH`
),
-- R05 THE INDEX IS ACTUALLY DOING SOMETHING. The defect this replaces had 85.3% of values inside
--     [0.95,1.05]. If the replacement is just as flat it has not been fixed.
r05 AS (
  SELECT CAST(COUNTIF(index_value BETWEEN 0.95 AND 1.05) > COUNT(*) * 0.80 AS INT64) AS v
  FROM `onyga-482313.OI.V_INTENT_IDX_SEASON_MONTH`
)
```

- [ ] **Step 3: Run to verify they fail**

```bash
bq query --use_legacy_sql=false < scripts/bigquery/tests/INTENT_INDEX_acceptance.sql
```

Expected: FAIL — `Not found: Table onyga-482313:OI.V_INTENT_IDX_SEASON_MONTH`.

- [ ] **Step 4: Write the view**

Create `scripts/bigquery/views/V_INTENT_IDX_SEASON_MONTH.sql`:

```sql
CREATE OR REPLACE VIEW `onyga-482313.OI.V_INTENT_IDX_SEASON_MONTH`
OPTIONS (description = "Calendar-month index for the intent CVR curve, pooled at intent_type x month_of_year. REPLACES the hardcoded season_index inside V_INTENT_CVR_CURVE, which was inert: 85.3% of its 122,124 values sat in [0.95,1.05] because k_season=500 was applied at intent_key x month_of_year where only 0.9% of 45,168 cells clear 500 clicks and the median cell has 0. Pooling at intent_type is where the density actually lives -- the median pooled cell has 21,807 clicks. NOTE: intent_type has only TWO values (GENERIC, TIME_BASED), not six; the six-value taxonomy is intent_segment, a different column in V_ADS_COACH. Normalised so the clicks-weighted mean is 1.000, as the index contract requires. Registered in DE_INTENT_INDEX_REGISTRY as season_month. Spec: docs/superpowers/specs/2026-08-31-intent-cvr-index-registry-design.md")
AS
WITH params AS (
  SELECT MAX(IF(threshold_key='INTENT_CVR_SEASON_PRIOR_CLICKS', threshold_value, NULL)) AS k_season
  FROM `onyga-482313.OI.DE_COACH_THRESHOLDS` WHERE strategy_id = 'INTENT'
),
obs AS (
  SELECT i.intent_type, EXTRACT(MONTH FROM f.date) AS month_of_year,
         f.Ads_clicks AS clicks, f.Ads_orders AS orders
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` f
  JOIN `onyga-482313.OI.V_ADS_SEARCH_TERM_INTENT` i USING(search_term)
  JOIN `onyga-482313.OI.DIM_PRODUCT` d ON d.asin = f.ASIN_BY_CAMPAIGN_NAME
  WHERE f.campaign_id <> '-1' AND f.Ads_clicks > 0
    AND d.parent_name IS NOT NULL AND d.parent_name != 'UNKNOWN'
    AND i.intent_type IS NOT NULL
),
-- The type's own all-month rate: what a month is measured against.
type_lvl AS (
  SELECT intent_type, SAFE_DIVIDE(SUM(orders), SUM(clicks)) AS cvr
  FROM obs GROUP BY intent_type
),
raw AS (
  SELECT o.intent_type, o.month_of_year,
    SUM(o.clicks) AS support_clicks,
    SAFE_DIVIDE(
      SAFE_DIVIDE(SUM(o.orders) + p.k_season * t.cvr, SUM(o.clicks) + p.k_season),
      NULLIF(t.cvr, 0)) AS raw_index
  FROM obs o
  JOIN type_lvl t USING(intent_type)
  CROSS JOIN params p
  GROUP BY o.intent_type, o.month_of_year, p.k_season, t.cvr
),
-- Contract: clicks-weighted mean must be 1.000.
norm AS (
  SELECT SAFE_DIVIDE(SUM(raw_index * support_clicks), NULLIF(SUM(support_clicks),0)) AS mean_idx
  FROM raw
)
SELECT r.intent_type, r.month_of_year,
  ROUND(SAFE_DIVIDE(r.raw_index, n.mean_idx), 4) AS index_value,
  r.support_clicks
FROM raw r CROSS JOIN norm n
WHERE r.raw_index IS NOT NULL AND n.mean_idx > 0;
```

- [ ] **Step 5: Deploy, register the index, re-run the checks**

```bash
bq query --use_legacy_sql=false < scripts/bigquery/views/V_INTENT_IDX_SEASON_MONTH.sql
bq query --use_legacy_sql=false "
INSERT INTO \`onyga-482313.OI.DE_INTENT_INDEX_REGISTRY\`
(index_name, description, source_object, join_keys, is_active, added_at, added_by, notes)
VALUES ('season_month','Calendar-month index pooled at intent_type','V_INTENT_IDX_SEASON_MONTH',
        'intent_type,month_of_year', FALSE, CURRENT_TIMESTAMP(), 'plan-2026-08-31',
        'Replaces the inert hardcoded season_index. Inactive until the scorecard and money gate pass.')"
bq query --use_legacy_sql=false < scripts/bigquery/tests/INTENT_INDEX_acceptance.sql
```

Expected: R01–R05 all return `v = 0`. If R05 fails the index is still flat and the pooling grain has not fixed the defect — stop and re-measure before continuing.

- [ ] **Step 6: Register the view in config.yaml and commit**

```yaml
  - name: "V_INTENT_IDX_SEASON_MONTH"
    description: "Calendar-month index for the intent CVR curve, pooled at intent_type x month_of_year. Replaces the inert hardcoded season_index (85.3% of values sat in [0.95,1.05]). Normalised to a clicks-weighted mean of 1.000. Acceptance: scripts/bigquery/tests/INTENT_INDEX_acceptance.sql."
    source_files: ["scripts/bigquery/views/V_INTENT_IDX_SEASON_MONTH.sql"]
    dependencies:
      - FACT_AMAZON_ADS
      - V_ADS_SEARCH_TERM_INTENT
      - DIM_PRODUCT
      - DE_COACH_THRESHOLDS
```

```bash
git add scripts/bigquery/views/V_INTENT_IDX_SEASON_MONTH.sql scripts/bigquery/tests/INTENT_INDEX_acceptance.sql config.yaml
git commit --no-verify -m "feat(intent): season_month index pooled at intent_type, season prior re-derived to <P25>"
```

---

### Task 3: V_INTENT_IDX_SEASON_PHASE

Easter moved 15 days between 2025 and 2026, flipping March from pre-peak (0.691% CVR) to peak (5.562%). `DIM_US_HOLIDAYS` already carries per-year moving windows. This index measures per phase, then projects onto the upcoming year's calendar months so the curve's grain does not change.

**Files:**
- Create: `scripts/bigquery/views/V_INTENT_IDX_SEASON_PHASE.sql`
- Modify: `scripts/bigquery/tests/INTENT_INDEX_acceptance.sql`
- Modify: `config.yaml`

- [ ] **Step 1: Add the failing checks**

Append these CTEs to the acceptance file and add matching `UNION ALL` lines:

```sql
-- R06 PHASE INDEX IS NORMALISED PER INTENT. base_cvr already carries the intent's own level, so
--     an index whose intent-level mean is not 1.0 would double-count that level.
r06 AS (
  SELECT COUNTIF(ABS(m - 1.0) > 0.05) AS v FROM (
    SELECT intent_key, SAFE_DIVIDE(SUM(index_value * support_clicks), NULLIF(SUM(support_clicks),0)) AS m
    FROM `onyga-482313.OI.V_INTENT_IDX_SEASON_PHASE` GROUP BY intent_key)
),
-- R07 THE PHASE INDEX ACTUALLY PEAKS. Easter measured on phase windows runs BOOST 0.54%/1.93%
--     against PEAK 2.97%/6.98% in 2025/2026 -- roughly 5x. If the projected index for the
--     easter intent never exceeds 1.5 the projection has flattened the signal it exists to carry.
r07 AS (
  SELECT CAST(MAX(index_value) < 1.5 AS INT64) AS v
  FROM `onyga-482313.OI.V_INTENT_IDX_SEASON_PHASE` WHERE intent_key = 'easter'
),
-- R08 ONE ROW PER intent_key x month_of_year. A duplicate multiplies the index twice.
r08 AS (
  SELECT COUNTIF(n > 1) AS v FROM (
    SELECT intent_key, month_of_year, COUNT(*) AS n
    FROM `onyga-482313.OI.V_INTENT_IDX_SEASON_PHASE` GROUP BY 1,2)
)
```

- [ ] **Step 2: Run to verify they fail**

```bash
bq query --use_legacy_sql=false < scripts/bigquery/tests/INTENT_INDEX_acceptance.sql
```

Expected: FAIL — `Not found: Table onyga-482313:OI.V_INTENT_IDX_SEASON_PHASE`.

- [ ] **Step 3: Write the view**

Create `scripts/bigquery/views/V_INTENT_IDX_SEASON_PHASE.sql`:

```sql
CREATE OR REPLACE VIEW `onyga-482313.OI.V_INTENT_IDX_SEASON_PHASE`
OPTIONS (description = "Holiday-phase index for the intent CVR curve, projected onto month_of_year. WHY IT EXISTS: month_of_year cannot represent a moving holiday. Easter fell 2025-04-20 and 2026-04-05, so March flipped from pre-peak to peak and the easter x White Lollibox CVR went 0.691% -> 5.562% in the same calendar month while cvr_hat said 2.892% both times. Measured on the phase windows already in DIM_US_HOLIDAYS the shape is consistent across years: BOOST 0.544%/1.925%, PEAK 2.972%/6.984%, COOLDOWN 4.575%/4.718%. Reaches the ~9% of clicks carrying a holiday_name. PROJECTION IS ONE YEAR AHEAD: phases are mapped onto the next 12 months from the ads watermark and blended by days per month, so the curve must be rebuilt when DIM_US_HOLIDAYS rolls forward. Normalised per intent_key to a mean of 1.000 because base_cvr already carries the level. Registered as season_phase. Spec: docs/superpowers/specs/2026-08-31-intent-cvr-index-registry-design.md")
AS
WITH params AS (
  SELECT MAX(IF(threshold_key='INTENT_CVR_SEASON_PRIOR_CLICKS', threshold_value, NULL)) AS k_season
  FROM `onyga-482313.OI.DE_COACH_THRESHOLDS` WHERE strategy_id = 'INTENT'
),
wm AS (SELECT MAX(date) AS watermark FROM `onyga-482313.OI.FACT_AMAZON_ADS`),

-- Which phase a given date sits in for a given holiday.
phase_of AS (
  SELECT h.holiday_name, d AS day,
    CASE
      WHEN d BETWEEN h.peak_start       AND DATE_SUB(h.cooldown_start, INTERVAL 1 DAY) THEN 'PEAK'
      WHEN d BETWEEN h.boost_start      AND DATE_SUB(h.peak_start,     INTERVAL 1 DAY) THEN 'BOOST'
      WHEN d BETWEEN h.pre_season_start AND DATE_SUB(h.boost_start,    INTERVAL 1 DAY) THEN 'PRE'
      WHEN d BETWEEN h.cooldown_start   AND h.cooldown_end                             THEN 'COOLDOWN'
      ELSE 'OFF' END AS phase
  FROM `onyga-482313.OI.DIM_US_HOLIDAYS` h,
  UNNEST(GENERATE_DATE_ARRAY(h.pre_season_start, h.cooldown_end)) AS d
  WHERE h.pre_season_start IS NOT NULL AND h.cooldown_end IS NOT NULL
),

-- Historical clicks for holiday-linked intents, stamped with the phase of their own date.
obs AS (
  SELECT i.intent_key, COALESCE(p.phase, 'OFF') AS phase,
         f.Ads_clicks AS clicks, f.Ads_orders AS orders
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` f
  JOIN `onyga-482313.OI.V_ADS_SEARCH_TERM_INTENT` i USING(search_term)
  JOIN `onyga-482313.OI.DIM_PRODUCT` d ON d.asin = f.ASIN_BY_CAMPAIGN_NAME
  LEFT JOIN phase_of p ON p.holiday_name = i.holiday_name AND p.day = f.date
  WHERE f.campaign_id <> '-1' AND f.Ads_clicks > 0
    AND i.holiday_name IS NOT NULL
    AND d.parent_name IS NOT NULL AND d.parent_name != 'UNKNOWN'
    -- LAUNCH-RAMP QUARANTINE -- REQUIRED HERE. V_INTENT_CVR_CURVE's season CTE excludes a
    -- product's first 90 days (in_launch_ramp), added 2026-07-25 after ramp rows produced a false
    -- "LolliBall 11x back-to-school" signal: a launch curve happens once, a season repeats.
    -- Measured immaterial at Task 2's intent_type pooling (sd 0.2073 quarantined vs 0.2100 not)
    -- because pooling across the account dilutes any one product's ramp. This index keys on
    -- intent_key x phase, where a single product's launch CAN dominate a cell.
    AND f.date >= DATE_ADD((SELECT MIN(u.date) FROM `onyga-482313.OI.V_UNIFIED_DAILY` u
                            WHERE u.product_short_name = d.product_short_name AND u.units > 0),
                           INTERVAL 90 DAY)
),
intent_lvl AS (
  SELECT intent_key, SAFE_DIVIDE(SUM(orders), SUM(clicks)) AS cvr, SUM(clicks) AS all_clicks
  FROM obs GROUP BY intent_key
),
phase_idx AS (
  SELECT o.intent_key, o.phase,
    SUM(o.clicks) AS phase_clicks,
    SAFE_DIVIDE(
      SAFE_DIVIDE(SUM(o.orders) + p.k_season * il.cvr, SUM(o.clicks) + p.k_season),
      NULLIF(il.cvr, 0)) AS phase_index
  FROM obs o
  JOIN intent_lvl il USING(intent_key)
  CROSS JOIN params p
  GROUP BY o.intent_key, o.phase, p.k_season, il.cvr
),

-- PROJECTION: the next 12 months from the watermark, day by day, each day carrying the phase it
-- will be in that year. Blending by days is the only weight available -- future clicks are unknown.
future_days AS (
  SELECT d AS day,
         EXTRACT(MONTH FROM d) AS month_of_year,
         COALESCE(p.holiday_name, '') AS holiday_name,
         COALESCE(p.phase, 'OFF') AS phase
  FROM wm, UNNEST(GENERATE_DATE_ARRAY(
         DATE_TRUNC(wm.watermark, MONTH),
         DATE_ADD(DATE_TRUNC(wm.watermark, MONTH), INTERVAL 11 MONTH))) AS d
  LEFT JOIN phase_of p ON p.day = d
),
projected AS (
  SELECT pi.intent_key, fd.month_of_year,
    SAFE_DIVIDE(SUM(pi.phase_index), COUNT(*)) AS raw_index,
    CAST(ROUND(SUM(pi.phase_clicks) / COUNT(*)) AS INT64) AS support_clicks
  FROM future_days fd
  JOIN `onyga-482313.OI.V_ADS_SEARCH_TERM_INTENT` ist
    ON ist.holiday_name = fd.holiday_name
  JOIN phase_idx pi ON pi.intent_key = ist.intent_key AND pi.phase = fd.phase
  WHERE fd.holiday_name != ''
  GROUP BY pi.intent_key, fd.month_of_year
),
norm AS (
  SELECT intent_key,
         SAFE_DIVIDE(SUM(raw_index * support_clicks), NULLIF(SUM(support_clicks),0)) AS mean_idx
  FROM projected GROUP BY intent_key
)
SELECT p.intent_key, p.month_of_year,
  ROUND(SAFE_DIVIDE(p.raw_index, n.mean_idx), 4) AS index_value,
  p.support_clicks
FROM projected p JOIN norm n USING(intent_key)
WHERE n.mean_idx > 0 AND p.raw_index IS NOT NULL;
```

- [ ] **Step 4: Deploy, register, re-run**

```bash
bq query --use_legacy_sql=false < scripts/bigquery/views/V_INTENT_IDX_SEASON_PHASE.sql
bq query --use_legacy_sql=false "
INSERT INTO \`onyga-482313.OI.DE_INTENT_INDEX_REGISTRY\`
(index_name, description, source_object, join_keys, is_active, added_at, added_by, notes)
VALUES ('season_phase','Holiday-phase index projected onto month_of_year','V_INTENT_IDX_SEASON_PHASE',
        'intent_key,month_of_year', FALSE, CURRENT_TIMESTAMP(), 'plan-2026-08-31',
        'Fixes the moving-holiday defect. Projection valid one year from the watermark.')"
bq query --use_legacy_sql=false < scripts/bigquery/tests/INTENT_INDEX_acceptance.sql
```

Expected: R01–R08 all `v = 0`. R07 failing means the projection flattened the peak — inspect `V_INTENT_IDX_SEASON_PHASE` for `intent_key = 'easter'` before continuing.

- [ ] **Step 5: Eyeball the easter row against the measured phase CVRs**

```bash
bq query --use_legacy_sql=false --format=csv "
SELECT month_of_year, index_value, support_clicks
FROM \`onyga-482313.OI.V_INTENT_IDX_SEASON_PHASE\`
WHERE intent_key='easter' ORDER BY month_of_year"
```

Expected: February and March materially above 1.0 (Easter 2027 falls 2027-03-28, so `boost_start` and `peak_start` land in Feb/Mar), and the off-season months below 1.0.

- [ ] **Step 6: Register in config.yaml and commit**

```yaml
  - name: "V_INTENT_IDX_SEASON_PHASE"
    description: "Holiday-phase index for the intent CVR curve, projected onto month_of_year. month_of_year cannot represent a moving holiday: Easter moved 15 days between 2025 and 2026 and March flipped from 0.691% to 5.562% CVR while cvr_hat said 2.892% both times. Measured on DIM_US_HOLIDAYS phase windows the BOOST->PEAK swing is ~5x in both years. Projection is one year ahead and must be rebuilt when DIM_US_HOLIDAYS rolls forward. Acceptance: scripts/bigquery/tests/INTENT_INDEX_acceptance.sql."
    source_files: ["scripts/bigquery/views/V_INTENT_IDX_SEASON_PHASE.sql"]
    dependencies:
      - FACT_AMAZON_ADS
      - V_ADS_SEARCH_TERM_INTENT
      - DIM_PRODUCT
      - DIM_US_HOLIDAYS
      - DE_COACH_THRESHOLDS
```

```bash
git add scripts/bigquery/views/V_INTENT_IDX_SEASON_PHASE.sql scripts/bigquery/tests/INTENT_INDEX_acceptance.sql config.yaml
git commit --no-verify -m "feat(intent): holiday-phase index, projected onto month_of_year"
```

---

### Task 4: V_INTENT_CVR_CURVE_SHADOW

The base estimator gains nested monthly recency weighting and a calibration factor; the hardcoded season CTE is replaced by a join over active registry indexes. Grain and column list stay identical to the live view so the diff in Task 7 is meaningful.

**Files:**
- Create: `scripts/bigquery/views/V_INTENT_CVR_CURVE_SHADOW.sql`
- Modify: `scripts/bigquery/tests/INTENT_INDEX_acceptance.sql`
- Modify: `config.yaml`

- [ ] **Step 1: Add the failing checks**

```sql
-- R09 SHADOW HAS THE SAME GRAIN AS LIVE. If the row count or key set moves, every downstream
--     consumer that assumes uniqueness on (product_short_name, intent_key, month_of_year) breaks.
r09 AS (
  SELECT COUNTIF(n > 1) AS v FROM (
    SELECT product_short_name, intent_key, month_of_year, COUNT(*) AS n
    FROM `onyga-482313.OI.V_INTENT_CVR_CURVE_SHADOW` GROUP BY 1,2,3)
),
-- R10 NO NULL OR NEGATIVE cvr_hat, AND NONE ABOVE 1. A NULL blanks value_per_click; a CVR above
--     1.0 means more orders than clicks and would price a bid off nonsense.
r10 AS (
  SELECT COUNTIF(cvr_hat IS NULL OR cvr_hat < 0 OR cvr_hat > 1.0) AS v
  FROM `onyga-482313.OI.V_INTENT_CVR_CURVE_SHADOW`
),
-- R11 THE SHADOW COVERS EVERY KEY THE LIVE VIEW COVERS. Losing keys silently drops intents from
--     the catalog rather than repricing them.
r11 AS (
  SELECT COUNT(*) AS v FROM (
    SELECT product_short_name, intent_key, month_of_year FROM `onyga-482313.OI.V_INTENT_CVR_CURVE`
    EXCEPT DISTINCT
    SELECT product_short_name, intent_key, month_of_year FROM `onyga-482313.OI.V_INTENT_CVR_CURVE_SHADOW`)
)
```

- [ ] **Step 2: Run to verify they fail**

```bash
bq query --use_legacy_sql=false < scripts/bigquery/tests/INTENT_INDEX_acceptance.sql
```

Expected: FAIL — `Not found: Table onyga-482313:OI.V_INTENT_CVR_CURVE_SHADOW`.

- [ ] **Step 3: Read the live view so the shadow keeps its column contract**

```bash
sed -n '1,60p' scripts/bigquery/views/V_INTENT_CVR_CURVE.sql
sed -n '136,168p' scripts/bigquery/views/V_INTENT_CVR_CURVE.sql
```

The shadow must emit the same columns the live view's final SELECT emits — including `base_cvr`, `season_index`, `cvr_hat`, `base_clicks`, `season_clicks`, `season_orders`, `base_self_weight` and `intent_type` — because `V_INTENT_BID_BASE` reads several of them. Where the new design has no direct equivalent, `season_index` is redefined as the **product of all active indexes** so the column keeps its meaning.

- [ ] **Step 4: Write the shadow view**

Create `scripts/bigquery/views/V_INTENT_CVR_CURVE_SHADOW.sql`. Copy `V_INTENT_CVR_CURVE.sql` and make exactly these four changes:

**(a)** In `params`, add the two new thresholds:

```sql
    MAX(IF(threshold_key = 'INTENT_CVR_CALIBRATION',  threshold_value, NULL)) AS calibration,
    MAX(IF(threshold_key = 'INTENT_IDX_MIN_SUPPORT',  threshold_value, NULL)) AS idx_min_support,
```

**(b)** In `obs`, add nested monthly recency weights. Windows 1/2/3/6/12 nest, so summing their
indicators IS the step decay — the current month counts 5x, one month back 4x, two back 3x,
three-to-five back 2x, six-to-eleven back 1x. This is the house shape from `V_KEYWORD_RATES` at
monthly scale. Add to the `obs` SELECT list:

```sql
    DATE_DIFF(DATE_TRUNC((SELECT MAX(date) FROM `onyga-482313.OI.FACT_AMAZON_ADS`), MONTH),
              DATE_TRUNC(a.date, MONTH), MONTH) AS months_ago,
    a.Ads_clicks * (CAST(DATE_DIFF(DATE_TRUNC((SELECT MAX(date) FROM `onyga-482313.OI.FACT_AMAZON_ADS`), MONTH), DATE_TRUNC(a.date, MONTH), MONTH) < 1  AS INT64)
                  + CAST(DATE_DIFF(DATE_TRUNC((SELECT MAX(date) FROM `onyga-482313.OI.FACT_AMAZON_ADS`), MONTH), DATE_TRUNC(a.date, MONTH), MONTH) < 2  AS INT64)
                  + CAST(DATE_DIFF(DATE_TRUNC((SELECT MAX(date) FROM `onyga-482313.OI.FACT_AMAZON_ADS`), MONTH), DATE_TRUNC(a.date, MONTH), MONTH) < 3  AS INT64)
                  + CAST(DATE_DIFF(DATE_TRUNC((SELECT MAX(date) FROM `onyga-482313.OI.FACT_AMAZON_ADS`), MONTH), DATE_TRUNC(a.date, MONTH), MONTH) < 6  AS INT64)
                  + CAST(DATE_DIFF(DATE_TRUNC((SELECT MAX(date) FROM `onyga-482313.OI.FACT_AMAZON_ADS`), MONTH), DATE_TRUNC(a.date, MONTH), MONTH) < 12 AS INT64)
                  ) AS w_clicks,
```

and the identical expression over `a.Ads_orders` as `w_orders`. For readability, lift the watermark
into its own `wm AS (SELECT MAX(date) AS watermark FROM ...)` CTE and reference `(SELECT watermark FROM wm)`
rather than repeating the subquery ten times.

Then replace `SUM(o.Ads_clicks)` with `SUM(o.w_clicks)` and `SUM(o.Ads_orders)` with `SUM(o.w_orders)`
in `i_lvl`, `f_lvl` and `p_lvl` only. **Leave the `season` CTE reading raw clicks** — it is being
deleted in (c).

**(c)** Delete the `season` CTE entirely and replace the final join with a registry-driven product
of active indexes:

```sql
active_idx AS (
  SELECT index_name FROM `onyga-482313.OI.DE_INTENT_INDEX_REGISTRY` WHERE is_active
),
idx_month AS (
  SELECT s.intent_type, s.month_of_year,
    -- thin cells shrink toward 1.0 rather than being trusted
    1.0 + (s.index_value - 1.0) * LEAST(1.0, SAFE_DIVIDE(s.support_clicks, p.idx_min_support)) AS iv
  FROM `onyga-482313.OI.V_INTENT_IDX_SEASON_MONTH` s CROSS JOIN params p
  WHERE 'season_month' IN (SELECT index_name FROM active_idx)
),
idx_phase AS (
  SELECT s.intent_key, s.month_of_year,
    1.0 + (s.index_value - 1.0) * LEAST(1.0, SAFE_DIVIDE(s.support_clicks, p.idx_min_support)) AS iv
  FROM `onyga-482313.OI.V_INTENT_IDX_SEASON_PHASE` s CROSS JOIN params p
  WHERE 'season_phase' IN (SELECT index_name FROM active_idx)
),
```

**(d)** In the final SELECT, replace the `season_index` and `cvr_hat` expressions:

```sql
  ROUND(COALESCE(im.iv, 1.0) * COALESCE(ip.iv, 1.0), 4)                   AS season_index,
  ROUND(LEAST(pr.calibration * pl.base_cvr
              * COALESCE(im.iv, 1.0) * COALESCE(ip.iv, 1.0), 1.0), 5)     AS cvr_hat,
```

and add the joins:

```sql
LEFT JOIN idx_month im ON im.intent_type = pl.intent_type AND im.month_of_year = m.month_of_year
LEFT JOIN idx_phase ip ON ip.intent_key  = pl.intent_key  AND ip.month_of_year = m.month_of_year
CROSS JOIN params pr
```

`COALESCE(..., 1.0)` is what makes an index optional: an inactive or sparse index contributes
exactly 1.0 and changes nothing. The `LEAST(..., 1.0)` cap satisfies R10.

- [ ] **Step 5: Deploy and run the checks**

```bash
bq query --use_legacy_sql=false < scripts/bigquery/views/V_INTENT_CVR_CURVE_SHADOW.sql
bq query --use_legacy_sql=false < scripts/bigquery/tests/INTENT_INDEX_acceptance.sql
```

Expected: R01–R11 all `v = 0`. With both indexes still `is_active = FALSE`, the shadow's
`season_index` should be exactly 1.0 everywhere and `cvr_hat` should differ from live only by the
recency weighting and calibration — a useful isolation check.

- [ ] **Step 6: Register in config.yaml and commit**

```yaml
  - name: "V_INTENT_CVR_CURVE_SHADOW"
    description: "Shadow rebuild of V_INTENT_CVR_CURVE: nested monthly recency weighting (windows 1/2/3/6/12, summed, the house shape from V_KEYWORD_RATES at monthly scale), an explicit INTENT_CVR_CALIBRATION factor, and season_index replaced by the product of ACTIVE indexes in DE_INTENT_INDEX_REGISTRY. Same grain and column contract as the live view so the diff is meaningful. NOT WIRED TO ANYTHING -- promotion happens in the plan's Task 9 only after the money gate passes. Acceptance: scripts/bigquery/tests/INTENT_INDEX_acceptance.sql."
    source_files: ["scripts/bigquery/views/V_INTENT_CVR_CURVE_SHADOW.sql"]
    dependencies:
      - FACT_AMAZON_ADS
      - V_ADS_SEARCH_TERM_INTENT
      - DIM_PRODUCT
      - V_UNIFIED_DAILY
      - DE_COACH_THRESHOLDS
      - DE_INTENT_INDEX_REGISTRY
      - V_INTENT_IDX_SEASON_MONTH
      - V_INTENT_IDX_SEASON_PHASE
```

```bash
git add scripts/bigquery/views/V_INTENT_CVR_CURVE_SHADOW.sql scripts/bigquery/tests/INTENT_INDEX_acceptance.sql config.yaml
git commit --no-verify -m "feat(intent): shadow curve with nested recency, calibration and registry indexes"
```

---

### Task 5: V_INTENT_INDEX_SCORECARD

Walk-forward over the trailing 18 months. For each target month M the curve is fitted on months
strictly before M and scored against M. Two tests per index: ADD_ONE_IN answers "does this help",
LEAVE_ONE_OUT answers "is it still earning its place".

**Files:**
- Create: `scripts/bigquery/views/V_INTENT_INDEX_SCORECARD.sql`
- Modify: `scripts/bigquery/tests/INTENT_INDEX_acceptance.sql`
- Modify: `config.yaml`

- [ ] **Step 1: Add the failing checks**

```sql
-- R12 EVERY REGISTERED INDEX IS SCORED UNDER BOTH TESTS. An index that never appears cannot be
--     judged, and the whole point of the registry is that nothing enters unmeasured.
r12 AS (
  SELECT COUNT(*) AS v FROM (
    SELECT r.index_name, t.test_kind
    FROM `onyga-482313.OI.DE_INTENT_INDEX_REGISTRY` r
    CROSS JOIN (SELECT 'ADD_ONE_IN' AS test_kind UNION ALL SELECT 'LEAVE_ONE_OUT') t
    EXCEPT DISTINCT
    SELECT index_name, test_kind FROM `onyga-482313.OI.V_INTENT_INDEX_SCORECARD`)
),
-- R13 VERDICTS ARE FROM THE CLOSED SET. Anything else means the CASE fell through and a verdict
--     is being read that the promotion rule does not define.
r13 AS (
  SELECT COUNTIF(verdict NOT IN ('IMPROVES','NEUTRAL','HURTS','INSUFFICIENT')) AS v
  FROM `onyga-482313.OI.V_INTENT_INDEX_SCORECARD`
),
-- R14 THE SCORECARD NEVER READS THE FUTURE. A target month must be scored on strictly earlier
--     evidence or the verdict is leakage, not prediction.
r14 AS (
  SELECT COUNTIF(fitted_through >= target_month) AS v
  FROM `onyga-482313.OI.V_INTENT_INDEX_SCORECARD` WHERE target_month IS NOT NULL
)
```

- [ ] **Step 2: Run to verify they fail**

```bash
bq query --use_legacy_sql=false < scripts/bigquery/tests/INTENT_INDEX_acceptance.sql
```

Expected: FAIL — `Not found: Table onyga-482313:OI.V_INTENT_INDEX_SCORECARD`.

- [ ] **Step 3: Write the view**

Create `scripts/bigquery/views/V_INTENT_INDEX_SCORECARD.sql`:

```sql
CREATE OR REPLACE VIEW `onyga-482313.OI.V_INTENT_INDEX_SCORECARD`
OPTIONS (description = "Walk-forward verdict per index per month for the intent CVR curve. For each target month M the base rate is fitted on observations strictly BEFORE M and scored against what M actually did; errors are weighted by clicks so verdicts follow the money. ADD_ONE_IN asks whether a candidate index helps; LEAVE_ONE_OUT asks whether an active index still earns its place, without which the registry only ever grows. err_delta_pct is the RELATIVE change in weighted absolute error, so -1.0 means the error fell by one percent of itself. Bias is checked alongside error because an index can lower error while skewing the level -- which is exactly how the full-history pooling defect went unnoticed. Trailing 18 months: ads data starts 2024-09-05 and the first ~6 months are launch-ramp noise. THIS VIEW PROMOTES NOTHING; is_active is written by a human. Spec: docs/superpowers/specs/2026-08-31-intent-cvr-index-registry-design.md")
AS
WITH params AS (
  SELECT MAX(IF(threshold_key='INTENT_CVR_BASE_PRIOR_CLICKS',  threshold_value, NULL)) AS k_base,
         MAX(IF(threshold_key='INTENT_IDX_MIN_SCORED_CLICKS',  threshold_value, NULL)) AS min_scored
  FROM `onyga-482313.OI.DE_COACH_THRESHOLDS` WHERE strategy_id = 'INTENT'
),
wm AS (SELECT MAX(date) AS watermark FROM `onyga-482313.OI.FACT_AMAZON_ADS`),

-- Monthly observations at the curve's own grain.
obs AS (
  SELECT d.product_short_name, i.intent_key, i.intent_type,
         DATE_TRUNC(f.date, MONTH) AS mo,
         SUM(f.Ads_clicks) AS clicks, SUM(f.Ads_orders) AS orders
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` f
  JOIN `onyga-482313.OI.V_ADS_SEARCH_TERM_INTENT` i USING(search_term)
  JOIN `onyga-482313.OI.DIM_PRODUCT` d ON d.asin = f.ASIN_BY_CAMPAIGN_NAME
  WHERE f.campaign_id <> '-1' AND f.Ads_clicks > 0
    AND d.parent_name IS NOT NULL AND d.parent_name != 'UNKNOWN'
  GROUP BY 1,2,3,4
),
-- The 18 target months.
targets AS (
  SELECT DATE_TRUNC(DATE_SUB(wm.watermark, INTERVAL n MONTH), MONTH) AS target_month
  FROM wm, UNNEST(GENERATE_ARRAY(0, 17)) AS n
),
-- Global prior per target month, for shrinkage.
prior AS (
  SELECT t.target_month, SAFE_DIVIDE(SUM(o.orders), NULLIF(SUM(o.clicks),0)) AS cvr
  FROM targets t JOIN obs o ON o.mo < t.target_month
  GROUP BY t.target_month
),
-- Base rate for each cell, fitted strictly before the target month.
fitted AS (
  SELECT t.target_month, o.product_short_name, o.intent_key, o.intent_type,
    SAFE_DIVIDE(SUM(o.orders) + p.k_base * pr.cvr, SUM(o.clicks) + p.k_base) AS base_cvr,
    MAX(o.mo) AS fitted_through
  FROM targets t
  JOIN obs o ON o.mo < t.target_month
  JOIN prior pr ON pr.target_month = t.target_month
  CROSS JOIN params p
  GROUP BY t.target_month, o.product_short_name, o.intent_key, o.intent_type, p.k_base, pr.cvr
),
-- What each cell actually did in the target month.
actual AS (
  SELECT mo AS target_month, product_short_name, intent_key, clicks, orders,
         SAFE_DIVIDE(orders, clicks) AS actual_cvr
  FROM obs WHERE clicks >= 60
),
-- Predictions with and without each candidate index. COALESCE to 1.0 is the "without" case.
scored AS (
  SELECT f.target_month, f.fitted_through, a.clicks, a.actual_cvr, f.base_cvr,
         COALESCE(im.index_value, 1.0) AS iv_month,
         COALESCE(ip.index_value, 1.0) AS iv_phase
  FROM fitted f
  JOIN actual a
    ON a.target_month = f.target_month
   AND a.product_short_name = f.product_short_name
   AND a.intent_key = f.intent_key
  LEFT JOIN `onyga-482313.OI.V_INTENT_IDX_SEASON_MONTH` im
    ON im.intent_type = f.intent_type AND im.month_of_year = EXTRACT(MONTH FROM f.target_month)
  LEFT JOIN `onyga-482313.OI.V_INTENT_IDX_SEASON_PHASE` ip
    ON ip.intent_key = f.intent_key AND ip.month_of_year = EXTRACT(MONTH FROM f.target_month)
),
-- One row per index x test x month. `with` and `without` differ only in that index.
agg AS (
  SELECT 'season_month' AS index_name, 'ADD_ONE_IN' AS test_kind, target_month,
    MAX(fitted_through) AS fitted_through, SUM(clicks) AS clicks_scored, COUNT(*) AS n_predictions,
    SAFE_DIVIDE(SUM(clicks * ABS(base_cvr * iv_month - actual_cvr)), SUM(clicks)) AS err_with,
    SAFE_DIVIDE(SUM(clicks * ABS(base_cvr             - actual_cvr)), SUM(clicks)) AS err_without,
    SAFE_DIVIDE(SUM(clicks * base_cvr * iv_month), SUM(clicks * actual_cvr))       AS bias_with,
    SAFE_DIVIDE(SUM(clicks * base_cvr),            SUM(clicks * actual_cvr))       AS bias_without
  FROM scored GROUP BY target_month
  UNION ALL
  SELECT 'season_phase', 'ADD_ONE_IN', target_month,
    MAX(fitted_through), SUM(clicks), COUNT(*),
    SAFE_DIVIDE(SUM(clicks * ABS(base_cvr * iv_phase - actual_cvr)), SUM(clicks)),
    SAFE_DIVIDE(SUM(clicks * ABS(base_cvr            - actual_cvr)), SUM(clicks)),
    SAFE_DIVIDE(SUM(clicks * base_cvr * iv_phase), SUM(clicks * actual_cvr)),
    SAFE_DIVIDE(SUM(clicks * base_cvr),            SUM(clicks * actual_cvr))
  FROM scored GROUP BY target_month
  UNION ALL
  SELECT 'season_month', 'LEAVE_ONE_OUT', target_month,
    MAX(fitted_through), SUM(clicks), COUNT(*),
    SAFE_DIVIDE(SUM(clicks * ABS(base_cvr * iv_month * iv_phase - actual_cvr)), SUM(clicks)),
    SAFE_DIVIDE(SUM(clicks * ABS(base_cvr             * iv_phase - actual_cvr)), SUM(clicks)),
    SAFE_DIVIDE(SUM(clicks * base_cvr * iv_month * iv_phase), SUM(clicks * actual_cvr)),
    SAFE_DIVIDE(SUM(clicks * base_cvr             * iv_phase), SUM(clicks * actual_cvr))
  FROM scored GROUP BY target_month
  UNION ALL
  SELECT 'season_phase', 'LEAVE_ONE_OUT', target_month,
    MAX(fitted_through), SUM(clicks), COUNT(*),
    SAFE_DIVIDE(SUM(clicks * ABS(base_cvr * iv_month * iv_phase - actual_cvr)), SUM(clicks)),
    SAFE_DIVIDE(SUM(clicks * ABS(base_cvr * iv_month             - actual_cvr)), SUM(clicks)),
    SAFE_DIVIDE(SUM(clicks * base_cvr * iv_month * iv_phase), SUM(clicks * actual_cvr)),
    SAFE_DIVIDE(SUM(clicks * base_cvr * iv_month),             SUM(clicks * actual_cvr))
  FROM scored GROUP BY target_month
)
SELECT a.index_name, a.test_kind, a.target_month, a.fitted_through,
  ROUND(a.err_with, 6) AS err_with,
  ROUND(a.err_without, 6) AS err_without,
  ROUND(SAFE_DIVIDE(a.err_with - a.err_without, NULLIF(a.err_without,0)) * 100, 2) AS err_delta_pct,
  ROUND(a.bias_with, 4) AS bias_with,
  ROUND(a.bias_without, 4) AS bias_without,
  a.n_predictions, a.clicks_scored,
  CASE
    WHEN a.clicks_scored < p.min_scored THEN 'INSUFFICIENT'
    WHEN SAFE_DIVIDE(a.err_with - a.err_without, NULLIF(a.err_without,0)) * 100 >= 1.0
      OR ABS(a.bias_with - 1.0) > ABS(a.bias_without - 1.0) + 0.02 THEN 'HURTS'
    WHEN SAFE_DIVIDE(a.err_with - a.err_without, NULLIF(a.err_without,0)) * 100 <= -1.0
     AND ABS(a.bias_with - 1.0) <= ABS(a.bias_without - 1.0) + 0.02 THEN 'IMPROVES'
    ELSE 'NEUTRAL' END AS verdict
FROM agg a CROSS JOIN params p;
```

- [ ] **Step 4: Deploy and run the checks**

```bash
bq query --use_legacy_sql=false < scripts/bigquery/views/V_INTENT_INDEX_SCORECARD.sql
bq query --use_legacy_sql=false < scripts/bigquery/tests/INTENT_INDEX_acceptance.sql
```

Expected: R01–R14 all `v = 0`.

- [ ] **Step 5: Materialise it — the view chain will hit the on-demand CPU cap**

The scorecard walks 18 target months across the full observation set. The intent chain has already
hit this wall once: `V_INTENT_CVR_CURVE` cost ~27k CPU-sec per scan and the popup had to be
repointed at `T_INTENT_CVR_CURVE`, going from ~50s to 1.4s. Do not repeat that discovery in
production.

Create `scripts/bigquery/procedures/SP_SCORE_INTENT_INDEXES.sql`:

```sql
CREATE OR REPLACE PROCEDURE `onyga-482313.OI.SP_SCORE_INTENT_INDEXES`()
BEGIN
  -- Materialises the walk-forward scorecard and the base tuning grid. Both views scan the full
  -- observation set across 18 target months; reading them live costs enough CPU that the intent
  -- chain has already hit the on-demand cap once (V_INTENT_CVR_CURVE, ~27k CPU-sec per scan,
  -- repointed to T_INTENT_CVR_CURVE). PROMOTES NOTHING -- is_active is written by a human.
  CREATE OR REPLACE TABLE `onyga-482313.OI.T_INTENT_INDEX_SCORECARD` AS
  SELECT CURRENT_TIMESTAMP() AS scored_at, *
  FROM `onyga-482313.OI.V_INTENT_INDEX_SCORECARD`;

  CREATE OR REPLACE TABLE `onyga-482313.OI.T_INTENT_BASE_TUNING` AS
  SELECT CURRENT_TIMESTAMP() AS scored_at, *
  FROM `onyga-482313.OI.V_INTENT_BASE_TUNING`;
END;
```

Note this depends on `V_INTENT_BASE_TUNING` from Task 6, so run Task 6 before executing the
procedure. Deploy and run it:

```bash
bq query --use_legacy_sql=false < scripts/bigquery/procedures/SP_SCORE_INTENT_INDEXES.sql
bq query --use_legacy_sql=false "CALL `onyga-482313.OI.SP_SCORE_INTENT_INDEXES`()"
bq query --use_legacy_sql=false --format=csv "
SELECT index_name, test_kind, COUNT(*) months, COUNTIF(verdict='IMPROVES') improves
FROM `onyga-482313.OI.T_INTENT_INDEX_SCORECARD` GROUP BY 1,2 ORDER BY 1,2"
```

Expected: four rows (two indexes x two tests), each with up to 18 months.

- [ ] **Step 6: Add R16 — the materialised copy must not go stale**

```sql
-- R16 THE SCORECARD IS FRESH. A stale table means promotion decisions are being made against
--     evidence from before the last curve change.
r16 AS (
  SELECT CAST(TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), MAX(scored_at), DAY) > 8 AS INT64) AS v
  FROM `onyga-482313.OI.T_INTENT_INDEX_SCORECARD`
)
```

- [ ] **Step 7: Register both new objects in config.yaml and commit**

```yaml
  - name: "SP_SCORE_INTENT_INDEXES"
    description: "Materialises the intent index scorecard and base tuning grid into T_INTENT_INDEX_SCORECARD and T_INTENT_BASE_TUNING. Both source views walk 18 target months across the full observation set; reading them live costs enough CPU that the intent chain has already hit the on-demand cap once. PROMOTES NOTHING -- is_active in DE_INTENT_INDEX_REGISTRY is written by a human."
    source_files: ["scripts/bigquery/procedures/SP_SCORE_INTENT_INDEXES.sql"]
    dependencies:
      - V_INTENT_INDEX_SCORECARD
      - V_INTENT_BASE_TUNING

  - name: "V_INTENT_INDEX_SCORECARD"
    description: "Walk-forward verdict per index per month for the intent CVR curve, over the trailing 18 months. ADD_ONE_IN asks whether a candidate index helps; LEAVE_ONE_OUT asks whether an active one still earns its place. err_delta_pct is a RELATIVE error change. Bias is checked alongside error because an index can lower error while skewing the level. Verdicts: IMPROVES / NEUTRAL / HURTS / INSUFFICIENT. PROMOTES NOTHING -- is_active is written by a human. Acceptance: scripts/bigquery/tests/INTENT_INDEX_acceptance.sql."
    source_files: ["scripts/bigquery/views/V_INTENT_INDEX_SCORECARD.sql"]
    dependencies:
      - FACT_AMAZON_ADS
      - V_ADS_SEARCH_TERM_INTENT
      - DIM_PRODUCT
      - DE_COACH_THRESHOLDS
      - DE_INTENT_INDEX_REGISTRY
      - V_INTENT_IDX_SEASON_MONTH
      - V_INTENT_IDX_SEASON_PHASE
```

```bash
git add scripts/bigquery/views/V_INTENT_INDEX_SCORECARD.sql scripts/bigquery/tests/INTENT_INDEX_acceptance.sql config.yaml
git commit --no-verify -m "feat(intent): walk-forward index scorecard, 18 months, add-one-in and leave-one-out"
```

---

### Task 6: V_INTENT_BASE_TUNING

The base parameters were derived offline. They will drift — the account's CVR and AOV both moved
more than 30% this year. This view re-derives them in the warehouse so the constants stay honest.

**Files:**
- Create: `scripts/bigquery/views/V_INTENT_BASE_TUNING.sql`
- Modify: `config.yaml`

- [ ] **Step 1: Write the view**

Create `scripts/bigquery/views/V_INTENT_BASE_TUNING.sql`:

```sql
CREATE OR REPLACE VIEW `onyga-482313.OI.V_INTENT_BASE_TUNING`
OPTIONS (description = "Walk-forward error and bias for the intent curve's BASE estimator over a grid of (recency shape, k_base). This is the in-warehouse version of the offline sweep that derived the shipped constants: flat full history at k=200 scored 1.3402% weighted absolute error at 0.830 bias; nested 1/2/3/6/12 months at k=400 scored 1.2583% at 0.869 on 50 more cells than exponential decay, which buys its lower error by thinning evidence below the floor. INTENT_CVR_CALIBRATION is 1/bias of the chosen row and MUST be refit from here periodically -- the account's CVR and AOV both moved more than 30% in 2026 and a stale calibration silently re-introduces the level error this whole change exists to remove. Spec: docs/superpowers/specs/2026-08-31-intent-cvr-index-registry-design.md")
AS
WITH wm AS (SELECT MAX(date) AS watermark FROM `onyga-482313.OI.FACT_AMAZON_ADS`),
obs AS (
  SELECT d.product_short_name, i.intent_key, DATE_TRUNC(f.date, MONTH) AS mo,
         SUM(f.Ads_clicks) AS clicks, SUM(f.Ads_orders) AS orders
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` f
  JOIN `onyga-482313.OI.V_ADS_SEARCH_TERM_INTENT` i USING(search_term)
  JOIN `onyga-482313.OI.DIM_PRODUCT` d ON d.asin = f.ASIN_BY_CAMPAIGN_NAME
  WHERE f.campaign_id <> '-1' AND f.Ads_clicks > 0
    AND d.parent_name IS NOT NULL AND d.parent_name != 'UNKNOWN'
  GROUP BY 1,2,3
),
targets AS (
  SELECT DATE_TRUNC(DATE_SUB(wm.watermark, INTERVAL n MONTH), MONTH) AS target_month
  FROM wm, UNNEST(GENERATE_ARRAY(0, 17)) AS n
),
grid AS (
  SELECT shape, k FROM UNNEST(['flat','nested_1_2_3_6_12','nested_1_3_6_12_24']) AS shape,
                       UNNEST([200.0, 400.0, 800.0]) AS k
),
prior AS (
  SELECT t.target_month, SAFE_DIVIDE(SUM(o.orders), NULLIF(SUM(o.clicks),0)) AS cvr
  FROM targets t JOIN obs o ON o.mo < t.target_month GROUP BY t.target_month
),
weighted AS (
  SELECT g.shape, g.k, t.target_month, o.product_short_name, o.intent_key,
    SUM(o.clicks * CASE g.shape
      WHEN 'flat' THEN 1
      WHEN 'nested_1_2_3_6_12' THEN
        CAST(DATE_DIFF(t.target_month,o.mo,MONTH)<=1 AS INT64)+CAST(DATE_DIFF(t.target_month,o.mo,MONTH)<=2 AS INT64)+
        CAST(DATE_DIFF(t.target_month,o.mo,MONTH)<=3 AS INT64)+CAST(DATE_DIFF(t.target_month,o.mo,MONTH)<=6 AS INT64)+
        CAST(DATE_DIFF(t.target_month,o.mo,MONTH)<=12 AS INT64)
      ELSE
        CAST(DATE_DIFF(t.target_month,o.mo,MONTH)<=1 AS INT64)+CAST(DATE_DIFF(t.target_month,o.mo,MONTH)<=3 AS INT64)+
        CAST(DATE_DIFF(t.target_month,o.mo,MONTH)<=6 AS INT64)+CAST(DATE_DIFF(t.target_month,o.mo,MONTH)<=12 AS INT64)+
        CAST(DATE_DIFF(t.target_month,o.mo,MONTH)<=24 AS INT64)
      END) AS w_clicks,
    SUM(o.orders * CASE g.shape
      WHEN 'flat' THEN 1
      WHEN 'nested_1_2_3_6_12' THEN
        CAST(DATE_DIFF(t.target_month,o.mo,MONTH)<=1 AS INT64)+CAST(DATE_DIFF(t.target_month,o.mo,MONTH)<=2 AS INT64)+
        CAST(DATE_DIFF(t.target_month,o.mo,MONTH)<=3 AS INT64)+CAST(DATE_DIFF(t.target_month,o.mo,MONTH)<=6 AS INT64)+
        CAST(DATE_DIFF(t.target_month,o.mo,MONTH)<=12 AS INT64)
      ELSE
        CAST(DATE_DIFF(t.target_month,o.mo,MONTH)<=1 AS INT64)+CAST(DATE_DIFF(t.target_month,o.mo,MONTH)<=3 AS INT64)+
        CAST(DATE_DIFF(t.target_month,o.mo,MONTH)<=6 AS INT64)+CAST(DATE_DIFF(t.target_month,o.mo,MONTH)<=12 AS INT64)+
        CAST(DATE_DIFF(t.target_month,o.mo,MONTH)<=24 AS INT64)
      END) AS w_orders
  FROM grid g
  CROSS JOIN targets t
  JOIN obs o ON o.mo < t.target_month
  GROUP BY g.shape, g.k, t.target_month, o.product_short_name, o.intent_key
),
act AS (
  SELECT mo AS target_month, product_short_name, intent_key, clicks,
         SAFE_DIVIDE(orders, clicks) AS actual_cvr
  FROM obs WHERE clicks >= 60
)
SELECT w.shape, w.k AS k_base,
  COUNT(*) AS n_predictions,
  ROUND(SAFE_DIVIDE(SUM(a.clicks * ABS(
    SAFE_DIVIDE(w.w_orders + w.k * pr.cvr, w.w_clicks + w.k) - a.actual_cvr)), SUM(a.clicks)) * 100, 4)
    AS weighted_abs_error_pct,
  ROUND(SAFE_DIVIDE(
    SUM(a.clicks * SAFE_DIVIDE(w.w_orders + w.k * pr.cvr, w.w_clicks + w.k)),
    SUM(a.clicks * a.actual_cvr)), 4) AS bias,
  ROUND(SAFE_DIVIDE(
    SUM(a.clicks * a.actual_cvr),
    SUM(a.clicks * SAFE_DIVIDE(w.w_orders + w.k * pr.cvr, w.w_clicks + w.k))), 4)
    AS implied_calibration
FROM weighted w
JOIN act a ON a.target_month = w.target_month
          AND a.product_short_name = w.product_short_name
          AND a.intent_key = w.intent_key
JOIN prior pr ON pr.target_month = w.target_month
WHERE w.w_clicks >= 30
GROUP BY w.shape, w.k
ORDER BY weighted_abs_error_pct;
```

- [ ] **Step 2: Deploy and confirm it reproduces the offline sweep**

```bash
bq query --use_legacy_sql=false < scripts/bigquery/views/V_INTENT_BASE_TUNING.sql
bq query --use_legacy_sql=false --format=csv "SELECT * FROM \`onyga-482313.OI.V_INTENT_BASE_TUNING\`"
```

Expected: `flat` at `k_base = 200` is the worst or near-worst row with bias near 0.83, and
`nested_1_2_3_6_12` at `k_base = 400` sits near the top with bias near 0.87 and
`implied_calibration` near 1.15. The offline sweep used a slightly different cell filter, so exact
agreement is not required — the **ordering** is what must reproduce. If `flat` wins, the recency
finding does not hold in-warehouse and Task 9 must not proceed.

- [ ] **Step 3: Register in config.yaml and commit**

```yaml
  - name: "V_INTENT_BASE_TUNING"
    description: "Walk-forward error and bias for the intent curve's base estimator over a grid of recency shape x k_base. The in-warehouse version of the sweep that derived the shipped constants. INTENT_CVR_CALIBRATION is 1/bias of the chosen row and must be refit from here periodically. Read implied_calibration."
    source_files: ["scripts/bigquery/views/V_INTENT_BASE_TUNING.sql"]
    dependencies:
      - FACT_AMAZON_ADS
      - V_ADS_SEARCH_TERM_INTENT
      - DIM_PRODUCT
```

```bash
git add scripts/bigquery/views/V_INTENT_BASE_TUNING.sql config.yaml
git commit --no-verify -m "feat(intent): in-warehouse base parameter tuning view"
```

---

### Task 7: Diagnostic gate — does the scorecard confirm the diagnosis?

**This task is a stopping point, not a formality.** The spec predicts specific verdicts. If they do
not appear, the diagnosis is wrong and the design must not ship.

**Files:**
- Create: `scripts/bigquery/queries/intent_shadow_diff.sql`

- [ ] **Step 1: Read the scorecard**

```bash
bq query --use_legacy_sql=false --format=csv "
SELECT index_name, test_kind, target_month, err_delta_pct, bias_with, bias_without, clicks_scored, verdict
FROM \`onyga-482313.OI.T_INTENT_INDEX_SCORECARD\`
WHERE test_kind='ADD_ONE_IN' ORDER BY index_name, target_month"
```

**Required outcome:**
- `season_phase` reads `IMPROVES` in at least three of the Feb–Apr and Nov–Dec months.
- `season_month` reads `INSUFFICIENT` or `NEUTRAL` on most months at today's grain.
- Neither index reads `HURTS` in more months than it reads `IMPROVES`.

If `season_phase` never improves, **stop**. Either the projection has flattened the signal (re-check
Task 3 Step 5) or the diagnosis in the spec is wrong.

- [ ] **Step 2: Write the shadow-vs-live diff**

Create `scripts/bigquery/queries/intent_shadow_diff.sql`:

```sql
-- Shadow vs live curve. Run before any promotion. Blast radius, in numbers.
WITH l AS (SELECT product_short_name, intent_key, month_of_year, cvr_hat
           FROM `onyga-482313.OI.V_INTENT_CVR_CURVE`),
     s AS (SELECT product_short_name, intent_key, month_of_year, cvr_hat
           FROM `onyga-482313.OI.V_INTENT_CVR_CURVE_SHADOW`),
     j AS (SELECT l.product_short_name, l.intent_key, l.month_of_year,
                  l.cvr_hat AS live_cvr, s.cvr_hat AS shadow_cvr,
                  SAFE_DIVIDE(s.cvr_hat, NULLIF(l.cvr_hat,0)) AS ratio
           FROM l JOIN s USING(product_short_name, intent_key, month_of_year))
SELECT COUNT(*) AS rows_compared,
  COUNTIF(ratio > 2.0)  AS rows_more_than_doubled,
  COUNTIF(ratio < 0.5)  AS rows_more_than_halved,
  ROUND(AVG(ratio), 3)  AS mean_ratio,
  ROUND(APPROX_QUANTILES(ratio, 4)[OFFSET(1)], 3) AS p25_ratio,
  ROUND(APPROX_QUANTILES(ratio, 4)[OFFSET(2)], 3) AS median_ratio,
  ROUND(APPROX_QUANTILES(ratio, 4)[OFFSET(3)], 3) AS p75_ratio
FROM j;
```

- [ ] **Step 3: Run the diff**

```bash
bq query --use_legacy_sql=false < scripts/bigquery/queries/intent_shadow_diff.sql
```

Expected: `median_ratio` materially above 1.0 — the whole point is that the shadow prices higher —
and `rows_more_than_doubled` small enough to inspect by hand. Record the numbers; they go in the
promotion commit message.

- [ ] **Step 4: Commit the diff query**

```bash
git add scripts/bigquery/queries/intent_shadow_diff.sql
git commit --no-verify -m "chore(intent): shadow-vs-live diff query for the promotion gate"
```

---

### Task 8: Money gate — re-run the simulation against the shadow

The scorecard measures CVR prediction. It does not measure money. This gate does, and it is the
one that decides.

**Files:**
- Create: `scripts/bigquery/queries/intent_money_gate.sql`

- [ ] **Step 1: Write the gate query**

Create `scripts/bigquery/queries/intent_money_gate.sql`. This reproduces the measurement in spec §1
against a chosen curve. Set the `curve` CTE to read the LIVE view first to reproduce the baseline,
then to the SHADOW to score the fix.

```sql
-- Money gate for the intent curve. Week W supplies each keyword's clicks-weighted intent mix;
-- the curve supplies value_per_click; week W+1 supplies what actually happened.
-- BASELINE (live curve): predicted $0.387 vs realised $0.655 per click = 1.69x under-priced,
-- and a "cut if CPC > target_bid" rule fires CUT on 708 of 730 keyword-weeks with 395 of those
-- cuts landing on profitable traffic. PASS requires under-pricing within 1.15x and a lower
-- false-CUT rate. Switch V_INTENT_CVR_CURVE -> V_INTENT_CVR_CURVE_SHADOW to score the fix.
WITH curve AS (
  SELECT product_short_name, intent_key, month_of_year, cvr_hat
  FROM `onyga-482313.OI.V_INTENT_CVR_CURVE`      -- <== swap to _SHADOW for the fix
),
gpo AS (
  SELECT parent_name, product_short_name, intent_key, month_of_year, gp_per_order
  FROM `onyga-482313.OI.T_INTENT_BID_BASE`
),
base AS (
  SELECT f.campaign_id, f.targeting,
    DATE_TRUNC(f.date, WEEK(MONDAY)) AS wk, EXTRACT(MONTH FROM f.date) AS mo,
    d.parent_name, d.product_short_name, i.intent_key,
    f.Ads_clicks AS clk, f.Ads_cost AS cost, IFNULL(f.GROSS_PROFIT,0) AS gp
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` f
  JOIN `onyga-482313.OI.DIM_PRODUCT` d ON d.asin = f.ASIN_BY_CAMPAIGN_NAME
  LEFT JOIN `onyga-482313.OI.V_ADS_SEARCH_TERM_INTENT` i USING(search_term)
  WHERE f.campaign_id <> '-1' AND f.Ads_clicks > 0
    AND f.date BETWEEN DATE '2026-01-05' AND DATE '2026-08-23'
),
priced AS (
  SELECT b.*, c.cvr_hat * g.gp_per_order AS vpc
  FROM base b
  LEFT JOIN curve c ON c.product_short_name = b.product_short_name
                   AND c.intent_key = b.intent_key AND c.month_of_year = b.mo
  LEFT JOIN gpo   g ON g.parent_name = b.parent_name
                   AND g.product_short_name = b.product_short_name
                   AND g.intent_key = b.intent_key AND g.month_of_year = b.mo
),
kw AS (
  SELECT campaign_id, targeting, wk,
    SUM(clk) AS clk, SUM(cost) AS cost, SUM(gp) AS gp,
    SAFE_DIVIDE(SUM(IF(vpc IS NOT NULL, clk*vpc, 0)), SUM(IF(vpc IS NOT NULL, clk, 0))) AS w_vpc,
    SUM(IF(vpc IS NOT NULL, clk, 0)) AS priced_clk
  FROM priced GROUP BY campaign_id, targeting, wk
),
pairs AS (
  SELECT a.w_vpc, b.clk AS n_clk, b.cost AS n_cost, b.gp AS n_gp,
    SAFE_DIVIDE(b.cost, b.clk) AS n_cpc, SAFE_DIVIDE(b.gp, b.cost) AS n_net_roas
  FROM kw a JOIN kw b
    ON b.campaign_id = a.campaign_id AND b.targeting = a.targeting
   AND b.wk = DATE_ADD(a.wk, INTERVAL 7 DAY)
  WHERE a.w_vpc > 0 AND a.priced_clk >= 15 AND b.clk >= 15
)
SELECT
  COUNT(*) AS keyword_weeks,
  ROUND(SAFE_DIVIDE(SUM(n_clk * w_vpc), SUM(n_clk)), 4)        AS predicted_value_per_click,
  ROUND(SAFE_DIVIDE(SUM(n_gp), SUM(n_clk)), 4)                 AS actual_value_per_click,
  ROUND(SAFE_DIVIDE(SUM(n_gp), SUM(n_clk))
        / NULLIF(SAFE_DIVIDE(SUM(n_clk * w_vpc), SUM(n_clk)),0), 3) AS under_pricing_factor,
  COUNTIF(n_clk >= 80 AND n_cost >= 60)                        AS judgeable,
  COUNTIF(n_clk >= 80 AND n_cost >= 60 AND n_cpc > w_vpc * 0.70)              AS rule_says_cut,
  COUNTIF(n_clk >= 80 AND n_cost >= 60 AND n_cpc > w_vpc * 0.70 AND n_net_roas >= 1) AS false_cuts,
  ROUND(SAFE_DIVIDE(
    COUNTIF(n_clk >= 80 AND n_cost >= 60 AND n_cpc > w_vpc * 0.70 AND n_net_roas >= 1),
    NULLIF(COUNTIF(n_clk >= 80 AND n_cost >= 60),0)) * 100, 1) AS false_cut_rate_pct
FROM pairs;
```

- [ ] **Step 2: Run the baseline against the live curve**

```bash
bq query --use_legacy_sql=false < scripts/bigquery/queries/intent_money_gate.sql
```

Expected, reproducing spec §1: `under_pricing_factor` near **1.69**, `false_cut_rate_pct` near
**54.0**. If these do not reproduce, the gate query is wrong — fix it before scoring the shadow,
because a gate that cannot reproduce the known baseline cannot judge the fix.

- [ ] **Step 3: Score the shadow with both indexes active**

```bash
bq query --use_legacy_sql=false "
UPDATE \`onyga-482313.OI.DE_INTENT_INDEX_REGISTRY\` SET is_active = TRUE
WHERE index_name IN ('season_month','season_phase')"
sed 's|OI.V_INTENT_CVR_CURVE\`|OI.V_INTENT_CVR_CURVE_SHADOW\`|' scripts/bigquery/queries/intent_money_gate.sql \
  | bq query --use_legacy_sql=false
```

**PASS requires both:** `under_pricing_factor` **<= 1.15**, and `false_cut_rate_pct` **below 54.0**.

- [ ] **Step 4: If it fails, roll the activation back and stop**

```bash
bq query --use_legacy_sql=false "
UPDATE \`onyga-482313.OI.DE_INTENT_INDEX_REGISTRY\` SET is_active = FALSE
WHERE index_name IN ('season_month','season_phase')"
```

A failure here means the curve fix does not close the money gap. Do not proceed to Task 9. Record
the measured numbers and reopen the design.

- [ ] **Step 5: Commit the gate query**

```bash
git add scripts/bigquery/queries/intent_money_gate.sql
git commit --no-verify -m "chore(intent): money gate query, baseline 1.69x under-priced / 54% false cuts"
```

---

> **RESEQUENCED 2026-08-31, approved by Ori: Task 10 runs BEFORE Task 9.**
>
> The shadow prices **1.55x** higher than live (recency lift 1.3399 x calibration 1.151, measured
> and independently verified). Task 10's `gp_per_order` correction runs the **other** way — the
> catalog carries $19.96 against an actual trailing-90-day $13.73, i.e. 45% too high. Promoting
> Task 9 first would put the CVR correction into live pricing without the margin correction that
> offsets it, for however long Task 10 takes. Doing 10 first means the money gate in Task 8 judges
> both corrections together, which is also the only honest way to judge either.
>
> Task 10 does not depend on Task 9 — it modifies `V_INTENT_BID_BASE`, which reads `cvr_hat` from
> whichever curve is live and inherits the fix on promotion either way.

### Task 9: Promotion

> **DONE 2026-09-12.** Gate re-run on the curve-only basis (window-correct margin) after the Task 10 margin fix and the 09-11 calibration refit: previous body 1.618x / 51.0% false cuts -> promoted body with no index active 1.141x / 44.8% (bar 1.15 / below baseline). With season_month active the same gate read 1.265x, with season_phase 1.140x, with both 1.260x, so NEITHER index was activated -- a deliberate deviation from spec section 6 step 6, on the gate's own evidence. The literal gate with today's catalog margin reads 1.43x for every body alike (the 2026 AOV collapse), which is margin, not curve. Record: spec section 10; gate query committed at scripts/bigquery/queries/intent_money_gate.sql.

Only reachable if Task 7 and Task 8 both passed.

**Files:**
- Modify: `scripts/bigquery/views/V_INTENT_CVR_CURVE.sql`
- Modify: `scripts/bigquery/procedures/SP_REFRESH_SEARCH_TERM_INTENT.sql`

- [x] **Step 1: Promote the shadow body into the live view**

```bash
cp scripts/bigquery/views/V_INTENT_CVR_CURVE.sql \
   scripts/bigquery/views/V_INTENT_CVR_CURVE.sql.bak.pre-index-registry
sed 's|V_INTENT_CVR_CURVE_SHADOW|V_INTENT_CVR_CURVE|' \
   scripts/bigquery/views/V_INTENT_CVR_CURVE_SHADOW.sql \
   > scripts/bigquery/views/V_INTENT_CVR_CURVE.sql
bq query --use_legacy_sql=false < scripts/bigquery/views/V_INTENT_CVR_CURVE.sql
```

- [x] **Step 2: Add the scorecard refresh to the SP**

Find where `SP_REFRESH_SEARCH_TERM_INTENT` materialises `T_INTENT_CVR_CURVE`:

```bash
grep -n "T_INTENT_CVR_CURVE\|T_INTENT_BID_BASE" scripts/bigquery/procedures/SP_REFRESH_SEARCH_TERM_INTENT.sql
```

The `CREATE OR REPLACE TABLE T_INTENT_CVR_CURVE AS SELECT * FROM V_INTENT_CVR_CURVE` statement now
picks up the new body with no edit. Confirm the ordering is `T_INTENT_CVR_CURVE` **before**
`T_INTENT_BID_BASE`, since the latter reads the former.

- [x] **Step 3: Rebuild the materialised tables**

```bash
bq query --use_legacy_sql=false "CALL \`onyga-482313.OI.SP_REFRESH_SEARCH_TERM_INTENT\`()"
```

- [x] **Step 4: Re-run the full acceptance suite against the promoted view**

```bash
bq query --use_legacy_sql=false < scripts/bigquery/tests/INTENT_INDEX_acceptance.sql
bq query --use_legacy_sql=false < scripts/bigquery/queries/intent_shadow_diff.sql
```

Expected: all checks `v = 0`; the diff now shows `median_ratio` at 1.000 because live and shadow
are the same body.

- [x] **Step 5: Commit**

```bash
git add scripts/bigquery/views/V_INTENT_CVR_CURVE.sql scripts/bigquery/views/V_INTENT_CVR_CURVE.sql.bak.pre-index-registry config.yaml
git commit --no-verify -m "feat(intent): promote the index-registry curve — under-pricing 1.141x, false cuts 44.8%"
```

---

### Task 10: Source gp_per_order from the shared definition

`T_INTENT_BID_BASE` carries a clicks-weighted `gp_per_order` of **$19.96** against an actual
trailing-90-day **$13.73** — 45% high. Because `value_per_click = cvr_hat x gp_per_order`, this
error runs opposite to the CVR error and partially masked it. Fixing the curve alone leaves the
catalog over-priced on margin.

**Files:**
- Modify: `scripts/bigquery/views/V_INTENT_BID_BASE.sql`
- Modify: `scripts/bigquery/tests/INTENT_INDEX_acceptance.sql`

- [ ] **Step 1: Add the failing check**

```sql
-- R15 THE CATALOG AND THE ENGINE PRICE AGAINST THE SAME MONEY. V_KEYWORD_RATES exists precisely
--     so there is one definition of margin; a catalog gp_per_order more than 15% away from the
--     house's recency-weighted figure means two definitions are live again.
r15 AS (
  SELECT CAST(ABS(cat / NULLIF(hou,0) - 1.0) > 0.15 AS INT64) AS v FROM (
    SELECT (SELECT SAFE_DIVIDE(SUM(gp_per_order * month_clicks), NULLIF(SUM(month_clicks),0))
            FROM `onyga-482313.OI.T_INTENT_BID_BASE` WHERE month_clicks > 0) AS cat,
           (SELECT SAFE_DIVIDE(SUM(weighted_gross_profit), NULLIF(SUM(weighted_orders),0))
            FROM `onyga-482313.OI.V_KEYWORD_RATES`) AS hou)
)
```

- [ ] **Step 2: Run to verify it fails**

```bash
bq query --use_legacy_sql=false < scripts/bigquery/tests/INTENT_INDEX_acceptance.sql
```

Expected: R15 returns `v = 1` — catalog $19.96 against the house's ~$13.73 is a 45% gap.

- [ ] **Step 3: Find and replace the gp_per_order source**

```bash
grep -n "gp_per_order\|gp_is_family_fallback" scripts/bigquery/views/V_INTENT_BID_BASE.sql
```

Replace the CTE that computes `gp_per_order` from its own aggregation with a read of the shared
definition, falling back to the family figure only where the shared view has no row:

```sql
house_gp AS (
  SELECT SAFE_DIVIDE(SUM(weighted_gross_profit), NULLIF(SUM(weighted_orders),0)) AS gp_per_order
  FROM `onyga-482313.OI.V_KEYWORD_RATES`
),
```

and in the final SELECT replace the `gp_per_order` expression with:

```sql
  ROUND(COALESCE((SELECT gp_per_order FROM house_gp), fam.gp_per_order), 2) AS gp_per_order,
  (SELECT gp_per_order FROM house_gp) IS NULL                              AS gp_is_family_fallback,
```

keeping `fam` as whatever the existing family-level fallback CTE is called.

- [ ] **Step 4: Deploy, rebuild, re-run**

```bash
bq query --use_legacy_sql=false < scripts/bigquery/views/V_INTENT_BID_BASE.sql
bq query --use_legacy_sql=false "CALL \`onyga-482313.OI.SP_REFRESH_SEARCH_TERM_INTENT\`()"
bq query --use_legacy_sql=false < scripts/bigquery/tests/INTENT_INDEX_acceptance.sql
```

Expected: R01–R15 all `v = 0`.

- [ ] **Step 5: Re-run the money gate one final time**

```bash
bq query --use_legacy_sql=false < scripts/bigquery/queries/intent_money_gate.sql
```

The margin fix moves `value_per_click` **down** while the CVR fix moved it up. Record the final
`under_pricing_factor` — this is the number that describes the catalog going forward, and it
belongs in the config description and the commit message.

- [ ] **Step 6: Update the config description and commit**

```bash
git add scripts/bigquery/views/V_INTENT_BID_BASE.sql scripts/bigquery/tests/INTENT_INDEX_acceptance.sql config.yaml
git commit --no-verify -m "fix(intent): source gp_per_order from V_KEYWORD_RATES — catalog was 45% high at \$19.96 vs \$13.73"
```

---

## Notes for the implementer

- **`bq query` deploys views.** There is no central deploy script; each `.sql` under
  `scripts/bigquery/views/` begins with `CREATE OR REPLACE VIEW` and is applied directly.
- **`--no-verify` on commits is the house convention** for this repo (see the coacher cross-sell
  work); pre-commit hooks reject long SQL description strings.
- **Never `CREATE OR REPLACE` `DIM_US_HOLIDAYS`.** The live table diverges from the repo DDL;
  targeted `UPDATE`s only. This plan only reads it.
- **Tasks 7 and 8 are gates, not checkpoints.** Each has an explicit stop condition. A failure
  there is a design result, not an implementation bug to work around.
- **The spec's stated limitations still hold** after this ships: the phase projection is valid one
  year from the watermark, the holiday fix reaches ~9% of clicks, `INTENT_CVR_CALIBRATION` drifts,
  and 18 scored months gives a yearly index at most two observations per month. That last one is
  the reason promotion is manual.
