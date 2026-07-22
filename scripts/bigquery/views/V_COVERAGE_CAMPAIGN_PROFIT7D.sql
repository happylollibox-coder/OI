-- V_COVERAGE_CAMPAIGN_PROFIT7D — per-campaign 7-day P&L for the coverage cockpit.
--
-- One row per campaign_id that had spend>0 in the LAST 7 DAYS, classified through the same
-- 6-strategy lens as V_COVERAGE_CAMPAIGN (V_CAMPAIGN_ROLE.strategy_category). Backs the cockpit's
-- strategy-tile + family-tile profit split (# profitable campaigns, net-profit-positive vs -negative).
--
-- Reuses the SAME building blocks as V_COVERAGE_CAMPAIGN:
--   prod : own sellable ASINs + gp_per_unit (listing price − unit cost)
--   adv  : advertised_product asin<->campaign link, SUM impr/clicks/cost/units_7d over the window
-- units_7d is click-attributed per day, so SUM over a date window is correct (no overcount).
-- Net profit = margin − spend, margin = SUM(units_7d × gp_per_unit).
CREATE OR REPLACE VIEW `onyga-482313.OI.V_COVERAGE_CAMPAIGN_PROFIT7D` AS
WITH
prod AS (
  SELECT dp.asin, dp.parent_name, dp.product_short_name,
    ROUND(lc.price - COALESCE(ch.TOTAL_COST_PER_UNIT, 0), 2) AS gp_per_unit
  FROM `onyga-482313`.OI.DIM_PRODUCT dp
  LEFT JOIN (
    SELECT asin1, price FROM `onyga-482313`.OI.V_DIM_LISTING_CURRENT
    QUALIFY ROW_NUMBER() OVER (PARTITION BY asin1 ORDER BY price DESC) = 1
  ) lc ON lc.asin1 = dp.asin
  LEFT JOIN (
    SELECT asin, TOTAL_COST_PER_UNIT FROM `onyga-482313`.OI.DIM_COSTS_HISTORY
    WHERE end_date IS NULL OR end_date >= CURRENT_DATE()
    QUALIFY ROW_NUMBER() OVER (PARTITION BY asin ORDER BY start_date DESC) = 1
  ) ch ON ch.asin = dp.asin
  WHERE dp.parent_name IS NOT NULL AND dp.parent_name != 'UNKNOWN' AND dp.is_active = true
),
-- ── advertised_product asin<->campaign link, LAST 7 DAYS ──
adv AS (
  SELECT advertised_asin AS asin, campaign_id,
    SUM(clicks) AS clicks, SUM(cost) AS cost, SUM(units_7d) AS units
  FROM `onyga-482313`.OI.V_SRC_AmazonAds_advertised_product
  WHERE date >= DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY)
  GROUP BY 1, 2
),
-- ── join to own products (gp_per_unit + parent_name) and role, aggregate to campaign ──
joined AS (
  SELECT
    adv.campaign_id,
    p.parent_name,
    vcr.strategy_category AS strategy,
    adv.clicks, adv.cost, adv.units,
    adv.units * p.gp_per_unit AS margin
  FROM adv
  JOIN prod p ON p.asin = adv.asin
  JOIN `onyga-482313`.OI.V_CAMPAIGN_ROLE vcr ON vcr.campaign_id = adv.campaign_id
)
SELECT
  campaign_id,
  ANY_VALUE(parent_name) AS parent_name,      -- a campaign is one family in practice
  strategy,
  CAST(SUM(clicks) AS INT64) AS clicks,
  SUM(cost) AS spend,
  CAST(SUM(units) AS INT64) AS units,
  SUM(margin) AS margin,
  SUM(margin) - SUM(cost) AS net_profit,
  (SUM(margin) - SUM(cost)) >= 0 AS profitable
FROM joined
WHERE strategy IS NOT NULL AND strategy != 'OTHER'
GROUP BY campaign_id, strategy
HAVING SUM(cost) > 0
