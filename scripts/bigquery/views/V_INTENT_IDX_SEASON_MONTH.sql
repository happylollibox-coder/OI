CREATE OR REPLACE VIEW `onyga-482313.OI.V_INTENT_IDX_SEASON_MONTH`
OPTIONS (description = "Calendar-month index for the intent CVR curve, pooled at intent_type x month_of_year. REPLACES the hardcoded season_index inside V_INTENT_CVR_CURVE, which was inert: 85.3% of its 122,124 values sat in [0.95,1.05] because k_season=500 was applied at intent_key x month_of_year where only 0.9% of 45,168 cells clear 500 clicks and the median cell has 0. Pooling at intent_type is where the density actually lives — the median pooled cell has 21,807 clicks. Normalised so the clicks-weighted mean is 1.000, as the index contract requires. Registered in DE_INTENT_INDEX_REGISTRY as season_month, is_active=FALSE until the scorecard and money gate pass. Spec: docs/superpowers/specs/2026-08-31-intent-cvr-index-registry-design.md")
AS
-- =============================================================================================
-- V_INTENT_IDX_SEASON_MONTH — calendar-month multiplier for the intent CVR curve.
-- Grain: one row per intent_type x month_of_year. 24 rows today (2 types x 12 months).
--
-- CONTRACT (every registry index honours these three):
--   1. clicks-weighted mean of index_value is 1.000, so the index shifts SHAPE not LEVEL and
--      INTENT_CVR_CALIBRATION cannot silently absorb it.
--   2. index_value is never NULL and never <= 0.
--   3. every row publishes its support_clicks so a thin cell can be weighed, not just trusted.
--
-- NOTHING READS THIS YET. It is registered with is_active = FALSE and joined by nothing until
-- V_INTENT_CVR_CURVE_SHADOW is built and passes the money gate.
--
-- WHY intent_type AND NOT intent_key
--   The defect being fixed is a prior that no cell can clear. At intent_key x month the median
--   cell has 0 clicks, so every cell shrinks all the way back to the intent's own all-month rate
--   and the index degenerates to 1.000. intent_type has only two values account-wide (GENERIC,
--   TIME_BASED — DE_INTENT_THEMES carries no others), which is coarse, but coarse-and-real beats
--   fine-and-inert: pooled cells run 304 to 219,057 clicks and the resulting index spans
--   0.575 to 1.398. A finer seasonal signal is the job of V_INTENT_IDX_SEASON_PHASE, which keys
--   on holiday phase rather than on the sparse intent_key grid.
--
-- Dependencies: FACT_AMAZON_ADS, V_ADS_SEARCH_TERM_INTENT, DIM_PRODUCT, DE_COACH_THRESHOLDS
-- Project: onyga-482313 / Dataset: OI
-- =============================================================================================
WITH params AS (
  -- coach_mode IS PART OF THE RESOLUTION KEY, not a tag (see DE_COACH_THRESHOLDS.sql and the
  -- four-way LEFT JOIN in V_ADS_COACH). Filtering to GUARDIAN makes this view read the exact row
  -- INTENT_INDEX_acceptance R02/R02b pin. Without it, a threshold later added under BLITZ or
  -- COOLDOWN would give MAX() two candidates and it would silently return the larger — a prior
  -- nobody chose for this view. product_family is also part of the grain, and is pinned NULL for
  -- the same reason: this index has no product dimension to resolve a family override against,
  -- so it must read the account-level default.
  SELECT MAX(IF(threshold_key='INTENT_CVR_SEASON_PRIOR_CLICKS', threshold_value, NULL)) AS k_season
  FROM `onyga-482313.OI.DE_COACH_THRESHOLDS`
  WHERE strategy_id = 'INTENT' AND coach_mode = 'GUARDIAN' AND product_family IS NULL
),

-- Every ads click that carries an intent type, on an own product.
-- Full history on purpose: a 12-month index needs every August there is.
obs AS (
  SELECT i.intent_type, EXTRACT(MONTH FROM f.date) AS month_of_year,
         f.Ads_clicks AS clicks, f.Ads_orders AS orders
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` f
  -- V_ADS_SEARCH_TERM_INTENT is exactly one row per search_term (352,750 rows over 352,750
  -- distinct terms), so this join does not inflate the click sums it feeds.
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

-- Beta-binomial shrink toward the type's all-month rate, then express as a ratio to it.
-- A month with THIN evidence lands near 1.000 rather than on noise. A month with no clicks
-- at all is a different case: it produces no row and is simply absent from the grid, not
-- present at 1.000. R03b in the acceptance file is what catches such a hole.
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

-- Contract 1: clicks-weighted mean must be 1.000.
-- THE WHERE IS LOAD-BEARING, not defensive tidying. SUM() skips NULLs in the numerator, but a
-- NULL-raw_index row's support_clicks still lands in the DENOMINATOR — so without this filter the
-- normaliser is computed over a different row set than the final SELECT publishes (that SELECT
-- drops NULL raw_index), and the published clicks-weighted mean stops being 1.000 the moment any
-- row is NULL. raw_index goes NULL whenever a type's all-month cvr is 0 or k_season is NULL.
norm AS (
  SELECT SAFE_DIVIDE(SUM(raw_index * support_clicks), NULLIF(SUM(support_clicks),0)) AS mean_idx
  FROM raw WHERE raw_index IS NOT NULL
)

SELECT r.intent_type, r.month_of_year,
  ROUND(SAFE_DIVIDE(r.raw_index, n.mean_idx), 4) AS index_value,
  r.support_clicks
FROM raw r CROSS JOIN norm n
WHERE r.raw_index IS NOT NULL AND n.mean_idx > 0;
