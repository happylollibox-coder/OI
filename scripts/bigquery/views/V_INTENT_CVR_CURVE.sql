-- =============================================
-- V_INTENT_CVR_CURVE
-- 12-month conversion-rate curve per (product x intent theme), learned from the ads signal.
-- Grain: product_short_name x intent_key x month_of_year (1-12). Always fully populated —
-- every product x intent gets all 12 months, even where it has never run in that month.
--
-- WHY MULTIPLICATIVE, NOT A LOOKUP
-- Measured 2026-07-24: at product x intent x month only 25% of cells clear 100 clicks. Even
-- family x occasion x season_phase only reaches 61%. A direct table would set bids from three
-- clicks and one lucky order. So CVR is decomposed into two factors, each estimated where its
-- data is densest:
--
--   cvr_hat(product, intent, month) = base_cvr(product, intent) x season_index(intent, month)
--
--   base_cvr    — how well this product converts this intent, pooled over all months.
--   season_index— how this intent's month differs from its own annual average, pooled over
--                 all products. 1.0 means "no seasonal signal", which is the honest default.
--
-- Both are Beta-binomial shrunk toward a parent: (orders + k*parent_cvr) / (clicks + k).
-- base_cvr climbs product x intent -> family x intent -> intent -> global.
-- season_index shrinks intent x month toward the intent's own all-month rate.
-- k values live in DE_COACH_THRESHOLDS (INTENT_CVR_BASE_PRIOR_CLICKS / ..._SEASON_...), so
-- how much thin cells are trusted is a data decision, not a code change.
--
-- WHY SEASON IS POOLED ACROSS PRODUCTS
-- Back-to-school is a property of the intent, not of the journal. Pooling gives the seasonal
-- shape ~10x the data and stops each product re-learning the same calendar from noise.
--
-- READ confidence BEFORE ACTING. base_clicks < INSUFFICIENT means the number is mostly its
-- parent's, not its own.
--
-- Dependencies: FACT_AMAZON_ADS, V_INTENT_RESOLVED, DIM_PRODUCT, DE_COACH_THRESHOLDS
-- SOP: docs/superpowers/specs/2026-07-24-intent-coverage-phase0-design.md
-- Project: onyga-482313 / Dataset: OI
-- =============================================

CREATE OR REPLACE VIEW `onyga-482313.OI.V_INTENT_CVR_CURVE` AS

WITH params AS (
  SELECT
    MAX(IF(threshold_key = 'INTENT_CVR_BASE_PRIOR_CLICKS',   threshold_value, NULL)) AS k_base,
    MAX(IF(threshold_key = 'INTENT_CVR_SEASON_PRIOR_CLICKS', threshold_value, NULL)) AS k_season
  FROM `onyga-482313.OI.DE_COACH_THRESHOLDS`
  WHERE strategy_id = 'INTENT'
),

-- First sale per product — the anchor for the launch-ramp quarantine below.
first_sale AS (
  SELECT product_short_name, MIN(date) AS fs
  FROM `onyga-482313.OI.V_UNIFIED_DAILY`
  WHERE units > 0
  GROUP BY 1
),

-- Every ads click that carries an intent theme, stamped with product, family and month.
-- Full history on purpose: a 12-month curve needs every August there is.
obs AS (
  SELECT
    p.parent_name,
    p.product_short_name,
    i.intent_key,
    i.intent_type,
    EXTRACT(MONTH FROM a.date) AS month_of_year,
    a.Ads_clicks, a.Ads_orders, a.Ads_cost, a.GROSS_PROFIT,
    -- SEASON QUARANTINE (2026-07-25): observations inside a product's first 90 days are a
    -- launch ramp, not seasonality. Pooling them into season_index inflates the launch
    -- months' index for the intent ACCOUNT-WIDE — the exact mechanism that produced the
    -- false "LolliBall 11x back-to-school" signal in V_FAMILY_OCCASION_MAP. Mirrors
    -- V_PEAK_RELEVANCE's 90-day pre-peak maturity gate. Quarantined rows still feed
    -- base_cvr (a product's own rate is its own business) — only the POOLED season CTE
    -- filters on this flag.
    (fsale.fs IS NULL OR a.date < DATE_ADD(fsale.fs, INTERVAL 90 DAY)) AS in_launch_ramp
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` a
  JOIN `onyga-482313.OI.V_INTENT_RESOLVED` i ON i.search_term = a.search_term
  JOIN `onyga-482313.OI.DIM_PRODUCT` p             ON p.asin = a.ASIN_BY_CAMPAIGN_NAME
  LEFT JOIN first_sale fsale ON fsale.product_short_name = p.product_short_name
  WHERE i.intent_key IS NOT NULL
    AND p.parent_name IS NOT NULL AND p.parent_name != 'UNKNOWN'
),

-- ---- Rung 4: global -------------------------------------------------------
g AS (SELECT SAFE_DIVIDE(SUM(Ads_orders), SUM(Ads_clicks)) AS cvr FROM obs),

-- ---- Rung 3: intent (all products, all months) ----------------------------
i_lvl AS (
  SELECT o.intent_key,
    SUM(o.Ads_clicks) AS clicks, SUM(o.Ads_orders) AS orders,
    SAFE_DIVIDE(SUM(o.Ads_orders) + p.k_base * g.cvr,
                SUM(o.Ads_clicks) + p.k_base) AS cvr
  FROM obs o CROSS JOIN params p CROSS JOIN g
  GROUP BY o.intent_key, p.k_base, g.cvr
),

-- ---- Rung 2: family x intent ---------------------------------------------
f_lvl AS (
  SELECT o.parent_name, o.intent_key,
    SUM(o.Ads_clicks) AS clicks, SUM(o.Ads_orders) AS orders,
    SAFE_DIVIDE(SUM(o.Ads_orders) + p.k_base * i_lvl.cvr,
                SUM(o.Ads_clicks) + p.k_base) AS cvr
  FROM obs o
  JOIN i_lvl ON i_lvl.intent_key = o.intent_key
  CROSS JOIN params p
  GROUP BY o.parent_name, o.intent_key, p.k_base, i_lvl.cvr
),

-- ---- Rung 1: product x intent = base_cvr ---------------------------------
p_lvl AS (
  SELECT o.parent_name, o.product_short_name, o.intent_key, ANY_VALUE(o.intent_type) AS intent_type,
    SUM(o.Ads_clicks) AS base_clicks, SUM(o.Ads_orders) AS base_orders,
    SAFE_DIVIDE(SUM(o.Ads_orders) + p.k_base * f_lvl.cvr,
                SUM(o.Ads_clicks) + p.k_base) AS base_cvr,
    f_lvl.cvr AS family_cvr
  FROM obs o
  JOIN f_lvl ON f_lvl.parent_name = o.parent_name AND f_lvl.intent_key = o.intent_key
  CROSS JOIN params p
  GROUP BY o.parent_name, o.product_short_name, o.intent_key, p.k_base, f_lvl.cvr
),

-- ---- Seasonal index: intent x month, pooled over products ----------------
-- Shrunk toward the intent's own all-month rate, so a month with no data lands on 1.00.
-- LAUNCH-RAMP ROWS EXCLUDED (see in_launch_ramp in obs) — a new product's first 90 days
-- must not teach the whole account that its launch months are "the season".
season AS (
  SELECT o.intent_key, o.month_of_year,
    SUM(o.Ads_clicks) AS season_clicks, SUM(o.Ads_orders) AS season_orders,
    SAFE_DIVIDE(
      SAFE_DIVIDE(SUM(o.Ads_orders) + p.k_season * i_lvl.cvr,
                  SUM(o.Ads_clicks) + p.k_season),
      i_lvl.cvr) AS season_index
  FROM obs o
  JOIN i_lvl ON i_lvl.intent_key = o.intent_key
  CROSS JOIN params p
  WHERE NOT o.in_launch_ramp
  GROUP BY o.intent_key, o.month_of_year, p.k_season, i_lvl.cvr
),

months AS (SELECT m AS month_of_year FROM UNNEST(GENERATE_ARRAY(1, 12)) m)

SELECT
  pl.parent_name,
  pl.product_short_name,
  pl.intent_key,
  pl.intent_type,
  m.month_of_year,

  ROUND(pl.base_cvr, 5)                                  AS base_cvr,
  COALESCE(ROUND(s.season_index, 4), 1.0)                AS season_index,
  ROUND(pl.base_cvr * COALESCE(s.season_index, 1.0), 5)  AS cvr_hat,

  pl.base_clicks,
  pl.base_orders,
  COALESCE(s.season_clicks, 0)                           AS season_clicks,
  COALESCE(s.season_orders, 0)                           AS season_orders,
  ROUND(pl.family_cvr, 5)                                AS family_cvr,

  -- How much of base_cvr is the cell's own evidence rather than its family's.
  -- clicks / (clicks + k). 0.5 means half-borrowed.
  ROUND(SAFE_DIVIDE(pl.base_clicks, pl.base_clicks + p.k_base), 3) AS base_self_weight,
  CASE
    WHEN pl.base_clicks >= 500 THEN 'HIGH'
    WHEN pl.base_clicks >= 100 THEN 'MEDIUM'
    WHEN pl.base_clicks >= 20  THEN 'LOW'
    ELSE 'INSUFFICIENT'
  END                                                    AS confidence
FROM p_lvl pl
CROSS JOIN months m
LEFT JOIN season s ON s.intent_key = pl.intent_key AND s.month_of_year = m.month_of_year
CROSS JOIN params p;
