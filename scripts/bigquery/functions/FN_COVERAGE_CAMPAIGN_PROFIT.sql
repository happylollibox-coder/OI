-- FN_COVERAGE_CAMPAIGN_PROFIT(win_start, win_end, peak_only) — per-campaign P&L for the coverage cockpit, windowed.
-- Table-function version of V_COVERAGE_CAMPAIGN_PROFIT7D: one row per campaign_id with spend>0 in the
-- caller-supplied [win_start, win_end] (peak_only=TRUE restricts to gift-season days), classified through the
-- same 6-strategy lens. Backs the cockpit's strategy/family profit split. units_7d is click-attributed per day
-- so SUM over a date window is correct. Net profit = margin − spend, margin = SUM(units_7d × gp_per_unit).
CREATE OR REPLACE TABLE FUNCTION `onyga-482313.OI.FN_COVERAGE_CAMPAIGN_PROFIT`(win_start DATE, win_end DATE, peak_only BOOL) AS (
WITH
peak_dates AS (
  SELECT DISTINCT d AS date
  FROM `onyga-482313`.OI.DIM_US_HOLIDAYS h, UNNEST(GENERATE_DATE_ARRAY(h.boost_start, h.cooldown_end)) d
  WHERE h.category = 'gift_season'
),
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
-- ── advertised_product asin<->campaign link, over the window ──
adv AS (
  SELECT advertised_asin AS asin, campaign_id,
    SUM(clicks) AS clicks, SUM(cost) AS cost, SUM(units_7d) AS units
  FROM `onyga-482313`.OI.V_SRC_AmazonAds_advertised_product
  WHERE date BETWEEN win_start AND win_end
    AND (NOT peak_only OR date IN (SELECT date FROM peak_dates))
  GROUP BY 1, 2
),
-- SP (advertised_product) + SB (FN_COVERAGE_SB). Sponsored Brands never appear in
-- advertised_product, so without the union their spend/margin was missing from every
-- strategy + family P&L rollup on the page (Ori 2026-07-23).
src_rows AS (
  SELECT adv.campaign_id, p.parent_name, adv.clicks, adv.cost, adv.units,
         adv.units * p.gp_per_unit AS margin
  FROM adv
  JOIN prod p ON p.asin = adv.asin
  UNION ALL
  SELECT campaign_id, parent_name, clicks, cost, units,
         units * gp_per_unit AS margin
  FROM `onyga-482313`.OI.FN_COVERAGE_SB(win_start, win_end, peak_only)
),
joined AS (
  SELECT
    r.campaign_id,
    r.parent_name,
    vcr.strategy_category AS strategy,
    r.clicks, r.cost, r.units, r.margin
  FROM src_rows r
  JOIN `onyga-482313`.OI.V_CAMPAIGN_ROLE vcr ON vcr.campaign_id = r.campaign_id
)
SELECT
  campaign_id,
  ANY_VALUE(parent_name) AS parent_name,
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
);
