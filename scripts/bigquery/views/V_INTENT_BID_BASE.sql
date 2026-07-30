-- =============================================
-- V_INTENT_BID_BASE
-- The base bid we are willing to pay for a click, per (product x intent x month).
-- Grain: product_short_name x intent_key x month_of_year (1-12).
--
--   base_bid = cvr_hat x gp_per_order x INTENT_BID_PROFIT_SHARE
--
-- Read it as: a click on this intent, for this product, in this month, is worth
-- cvr_hat x gp_per_order in expected gross margin. We pay a share of that and bank the rest.
-- At the default share of 0.70 we keep 30% of every click's expected margin.
--
-- WHY THIS IS NOT THE SAME AS A ROAS RULE
-- The existing profit gates judge an intent on its blended, year-round return. LolliME
-- back-to-school reads 1.12 ROAS blended and was dropped — but that is 4.20 in season and
-- 1.12 out of it, and the blend hides both. A bid that is a function of the month says
-- "pay $0.55 in August, $0.26 in July" instead of "this intent is dead".
--
-- ADVISORY ONLY. Nothing here writes to a campaign. Wiring into V_ADS_COACH is Phase 2.
--
-- action:
--   RUN         base_bid >= floor and >= the CPC actually being paid -> room to bid
--   RUN_TIGHTEN base_bid >= floor but below the CPC being paid -> overpaying now
--   OFF         base_bid < floor -> not worth placing this month
--
-- Dependencies: V_INTENT_CVR_CURVE, FACT_AMAZON_ADS, V_INTENT_RESOLVED, DIM_PRODUCT,
--               DE_COACH_THRESHOLDS
-- SOP: docs/superpowers/specs/2026-07-24-intent-coverage-phase0-design.md
-- Project: onyga-482313 / Dataset: OI
-- =============================================

CREATE OR REPLACE VIEW `onyga-482313.OI.V_INTENT_BID_BASE` AS

WITH params AS (
  SELECT
    MAX(IF(threshold_key = 'INTENT_BID_PROFIT_SHARE', threshold_value, NULL)) AS profit_share,
    MAX(IF(threshold_key = 'INTENT_BID_CEILING',      threshold_value, NULL)) AS bid_ceiling,
    MAX(IF(threshold_key = 'INTENT_BID_FLOOR',        threshold_value, NULL)) AS bid_floor,
    -- Band boundaries (spec 2026-07-25 §3). ALL from threshold rows, none hard-coded.
    MAX(IF(threshold_key = 'PROFITABLE_ROAS',         threshold_value, NULL)) AS roas_run,
    MAX(IF(threshold_key = 'VELOCITY_ROAS',           threshold_value, NULL)) AS roas_velocity,
    MAX(IF(threshold_key = 'INTENT_HOPELESS_ROAS',    threshold_value, NULL)) AS roas_hopeless
  FROM `onyga-482313.OI.DE_COACH_THRESHOLDS`
  WHERE strategy_id = 'INTENT'
),

-- Gross profit per ORDER, per product. Same table as the CVR numerator, so the ratio holds —
-- mixing FACT_AMAZON_ADS CVR with V_UNIFIED_DAILY margin would compare two attribution grains.
gp_product AS (
  SELECT p.product_short_name, p.parent_name,
    SAFE_DIVIDE(SUM(a.GROSS_PROFIT), SUM(a.Ads_orders)) AS gp_per_order,
    SUM(a.Ads_orders) AS orders_365d
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` a
  JOIN `onyga-482313.OI.DIM_PRODUCT` p ON p.asin = a.ASIN_BY_CAMPAIGN_NAME
  WHERE a.date >= DATE_SUB(CURRENT_DATE(), INTERVAL 365 DAY)
    AND p.parent_name IS NOT NULL AND p.parent_name != 'UNKNOWN'
  GROUP BY 1, 2
),

-- Family fallback for products too thin to price their own margin.
gp_family AS (
  SELECT parent_name,
    SAFE_DIVIDE(SUM(gp_per_order * orders_365d), SUM(orders_365d)) AS gp_per_order
  FROM gp_product GROUP BY 1
),

-- What we actually pay today for this product x intent x month, for comparison.
actual AS (
  SELECT p.product_short_name, i.intent_key, EXTRACT(MONTH FROM a.date) AS month_of_year,
    SUM(a.Ads_clicks) AS clicks,
    SAFE_DIVIDE(SUM(a.Ads_cost), SUM(a.Ads_clicks)) AS actual_cpc
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` a
  JOIN `onyga-482313.OI.V_INTENT_RESOLVED` i ON i.search_term = a.search_term
  JOIN `onyga-482313.OI.DIM_PRODUCT` p             ON p.asin = a.ASIN_BY_CAMPAIGN_NAME
  WHERE i.intent_key IS NOT NULL
  GROUP BY 1, 2, 3
),

priced AS (
  SELECT
    c.parent_name, c.product_short_name, c.intent_key, c.intent_type, c.month_of_year,
    c.base_cvr, c.season_index, c.cvr_hat, c.base_clicks, c.confidence, c.base_self_weight,
    COALESCE(gp.gp_per_order, gf.gp_per_order) AS gp_per_order,
    gp.gp_per_order IS NULL                    AS gp_is_family_fallback,
    c.cvr_hat * COALESCE(gp.gp_per_order, gf.gp_per_order) AS value_per_click,
    ac.actual_cpc, ac.clicks AS month_clicks,
    pr.profit_share, pr.bid_ceiling, pr.bid_floor,
    pr.roas_run, pr.roas_velocity, pr.roas_hopeless
  FROM `onyga-482313.OI.V_INTENT_CVR_CURVE` c
  LEFT JOIN gp_product gp ON gp.product_short_name = c.product_short_name
  LEFT JOIN gp_family  gf ON gf.parent_name        = c.parent_name
  LEFT JOIN actual     ac ON ac.product_short_name = c.product_short_name
                         AND ac.intent_key         = c.intent_key
                         AND ac.month_of_year      = c.month_of_year
  CROSS JOIN params pr
)

SELECT
  parent_name, product_short_name, intent_key, intent_type, month_of_year,
  ROUND(base_cvr, 5)        AS base_cvr,
  season_index,
  ROUND(cvr_hat, 5)         AS cvr_hat,
  ROUND(gp_per_order, 2)    AS gp_per_order,
  gp_is_family_fallback,
  ROUND(value_per_click, 3) AS value_per_click,
  -- max_bid is the BREAKEVEN CEILING — pay more than this and the click loses money.
  -- target_bid is the bid that also hits the margin goal. They are different questions and
  -- collapsing them was the first version's bug: it read "market is above my target" as
  -- "tighten" even when the market was also above breakeven (a money-loser), and read
  -- "target computed fine" as "run" even when the market cleared above the target and we
  -- would never win the auction.
  ROUND(LEAST(GREATEST(value_per_click, 0), bid_ceiling), 2)                AS max_bid,
  ROUND(LEAST(GREATEST(value_per_click * profit_share, 0), bid_ceiling), 2) AS target_bid,
  -- Band max CPCs (spec §3): willingness to pay per band.
  ROUND(LEAST(GREATEST(SAFE_DIVIDE(value_per_click, roas_run), 0), bid_ceiling), 2)      AS max_cpc_run,
  ROUND(LEAST(GREATEST(SAFE_DIVIDE(value_per_click, roas_velocity), 0), bid_ceiling), 2) AS max_cpc_velocity,
  ROUND(SAFE_DIVIDE(value_per_click, actual_cpc), 2) AS expected_net_roas_at_market,
  ROUND(actual_cpc, 2)      AS actual_cpc,
  month_clicks,
  base_clicks,
  base_self_weight,
  confidence,
  -- BAND assignment (spec 2026-07-25 §3, ratified four bands; boundaries all threshold
  -- rows). Hysteresis and the velocity-pace condition are STATEFUL — they live in the plan
  -- generator and checkpoint; this view reports the raw band only.
  CASE
    -- Not worth placing at any price.
    WHEN value_per_click < bid_floor THEN 'OFF'
    -- Never run, no market read: worth probing at target.
    WHEN actual_cpc IS NULL THEN 'RUN'
    WHEN SAFE_DIVIDE(value_per_click, actual_cpc) >= roas_run      THEN 'RUN'
    WHEN SAFE_DIVIDE(value_per_click, actual_cpc) >= roas_velocity THEN 'VELOCITY'
    WHEN SAFE_DIVIDE(value_per_click, actual_cpc) >= roas_hopeless THEN 'MARGINAL'
    ELSE 'OFF'
  END AS action,
  actual_cpc IS NULL AS no_market_read
FROM priced;
