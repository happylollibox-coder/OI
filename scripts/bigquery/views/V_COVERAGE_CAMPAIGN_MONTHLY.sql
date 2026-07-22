-- V_COVERAGE_CAMPAIGN_MONTHLY — per (campaign_id × month) 12-month P&L for the cockpit drill.
--
-- One row per (campaign_id, month) over the LAST 12 MONTHS. Backs the per-campaign monthly drill
-- behind a coverage cell. Reuses the SAME building blocks as V_COVERAGE_CAMPAIGN (prod + adv):
--   prod : own sellable ASINs + gp_per_unit (listing price − unit cost)
--   adv  : advertised_product asin<->campaign link (monthly grain), SUM impr/clicks/cost/units_7d
-- units_7d is click-attributed per day, so SUM over a date window is correct (no overcount).
-- net_profit = SUM(units_7d × gp_per_unit) − SUM(cost); net_roas = margin / spend.
CREATE OR REPLACE VIEW `onyga-482313.OI.V_COVERAGE_CAMPAIGN_MONTHLY` AS
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
adv AS (
  SELECT advertised_asin AS asin, campaign_id, DATE_TRUNC(date, MONTH) AS month,
    SUM(impressions) AS impressions, SUM(clicks) AS clicks,
    SUM(cost) AS cost, SUM(units_7d) AS units
  FROM `onyga-482313`.OI.V_SRC_AmazonAds_advertised_product
  WHERE date >= DATE_TRUNC(DATE_SUB(CURRENT_DATE(), INTERVAL 11 MONTH), MONTH)
  GROUP BY 1, 2, 3
)
SELECT
  adv.campaign_id,
  adv.month,
  CAST(SUM(adv.impressions) AS INT64) AS impressions,
  CAST(SUM(adv.clicks) AS INT64) AS clicks,
  SUM(adv.cost) AS spend,
  CAST(SUM(adv.units) AS INT64) AS units,
  SUM(adv.units * p.gp_per_unit) - SUM(adv.cost) AS net_profit,
  ROUND(SAFE_DIVIDE(SUM(adv.units * p.gp_per_unit), NULLIF(SUM(adv.cost), 0)), 2) AS net_roas
FROM adv
JOIN prod p ON p.asin = adv.asin
GROUP BY adv.campaign_id, adv.month
