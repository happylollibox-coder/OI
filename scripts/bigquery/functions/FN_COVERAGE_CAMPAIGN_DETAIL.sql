-- FN_COVERAGE_CAMPAIGN_DETAIL(win_start, win_end, peak_only) — S2 VERIFY evidence, windowed.
-- Table-function version of V_COVERAGE_CAMPAIGN_DETAIL: identical (cell_key × campaign) evidence + profit
-- verdict, but the per-campaign metrics window is the caller-supplied [win_start, win_end] (peak_only=TRUE
-- restricts to gift-season days). Gate = "served impressions in the window" (was: last-30d recency gate),
-- so the evidence list matches FN_COVERAGE_CAMPAIGN cell-for-cell under the same window.
CREATE OR REPLACE TABLE FUNCTION `onyga-482313.OI.FN_COVERAGE_CAMPAIGN_DETAIL`(win_start DATE, win_end DATE, peak_only BOOL) AS (
WITH
peak_dates AS (
  SELECT DISTINCT d AS date
  FROM `onyga-482313`.OI.DIM_US_HOLIDAYS h, UNNEST(GENERATE_DATE_ARRAY(h.boost_start, h.cooldown_end)) d
  WHERE h.category = 'gift_season'
),
-- ── Own sellable products (target universe) + per-ASIN gross profit per unit ──
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
-- ── Latest campaign state + display name ──
camp_state AS (
  SELECT campaign_id,
    ARRAY_AGG(state ORDER BY date DESC LIMIT 1)[OFFSET(0)] AS state,
    ARRAY_AGG(campaign_name ORDER BY date DESC LIMIT 1)[OFFSET(0)] AS campaign_name
  FROM `onyga-482313`.OI.V_SRC_AmazonAds_campaign_history GROUP BY 1
),
-- ── Authoritative asin<->campaign link + WINDOW metrics (per campaign) ──
-- Gate = served impressions in the window (a pair dark across the whole window drops out of the evidence).
adv AS (
  SELECT asin, campaign_id, impressions, clicks, cost, units, last_seen
  FROM (
    SELECT advertised_asin AS asin, campaign_id,
      SUM(impressions) AS impressions, SUM(clicks) AS clicks,
      SUM(cost) AS cost, SUM(units_7d) AS units,
      MAX(date) AS last_seen
    FROM `onyga-482313`.OI.V_SRC_AmazonAds_advertised_product
    WHERE date BETWEEN win_start AND win_end
      AND (NOT peak_only OR date IN (SELECT date FROM peak_dates))
    GROUP BY 1, 2
  )
  WHERE impressions > 0
),
-- ── Live rows: one per (own asin, campaign) with strategy_category + cell_key ──
-- SP (advertised_product) + SB (FN_COVERAGE_SB) — see FN_COVERAGE_CAMPAIGN for why SB needs its
-- own source: Sponsored Brands never appear in advertised_product, so they were invisible here too.
src_rows AS (
  SELECT p.parent_name, p.asin, p.gp_per_unit, adv.campaign_id,
         adv.impressions, adv.clicks, adv.cost, adv.units, adv.last_seen
  FROM prod p
  JOIN adv ON adv.asin = p.asin
  UNION ALL
  SELECT parent_name, asin, gp_per_unit, campaign_id, impressions, clicks, cost, units, last_seen
  FROM `onyga-482313`.OI.FN_COVERAGE_SB(win_start, win_end, peak_only)
),
live_base AS (
  SELECT
    r.parent_name, r.gp_per_unit,
    vcr.strategy_category,
    r.campaign_id, cst.state, cst.campaign_name,
    r.impressions, r.clicks, r.cost, r.units, r.last_seen,
    CASE
      WHEN vcr.strategy_category = 'AUTO' THEN CONCAT('AUTO|', r.asin)
      WHEN vcr.strategy_category = 'PRODUCT_DEFENSE' THEN 'PRODUCT_DEFENSE|__STORE__'
      WHEN vcr.strategy_category IN ('INTENT', 'BRAND_DEFENSE', 'COMPETITOR', 'EXACT_BOOST')
        THEN CONCAT(vcr.strategy_category, '|', r.parent_name)
      ELSE NULL
    END AS cell_key
  FROM src_rows r
  JOIN `onyga-482313`.OI.V_CAMPAIGN_ROLE vcr ON vcr.campaign_id = r.campaign_id
  LEFT JOIN camp_state cst ON cst.campaign_id = r.campaign_id
),
floors AS (
  SELECT strategy_id, MAX(CAST(threshold_value AS FLOAT64)) AS v
  FROM `onyga-482313`.OI.DE_COACH_THRESHOLDS
  WHERE threshold_key = 'PROFITABLE_ROAS'
  GROUP BY strategy_id
)
SELECT
  cell_key,
  ANY_VALUE(parent_name) AS parent_name,
  strategy_category AS strategy,
  campaign_id,
  ANY_VALUE(campaign_name) AS campaign_name,
  ANY_VALUE(state) AS state,
  ANY_VALUE(state) = 'ENABLED' AS is_enabled,
  CAST(SUM(impressions) AS INT64) AS impressions,
  CAST(SUM(clicks) AS INT64) AS clicks,
  CAST(SUM(units) AS INT64) AS units,
  ROUND(SUM(cost), 2) AS ad_spend,
  ROUND(SAFE_DIVIDE(SUM(cost), NULLIF(SUM(clicks), 0)), 2) AS cpc,
  ROUND(SAFE_DIVIDE(SUM(units * gp_per_unit), NULLIF(SUM(cost), 0)), 2) AS net_roas,
  CASE
    WHEN SUM(clicks) < 10 THEN 'unknown'
    WHEN ROUND(SAFE_DIVIDE(SUM(units * gp_per_unit), NULLIF(SUM(cost), 0)), 2) IS NULL THEN 'unknown'
    WHEN ROUND(SAFE_DIVIDE(SUM(units * gp_per_unit), NULLIF(SUM(cost), 0)), 2) >= COALESCE(ANY_VALUE(fl.v), (
      SELECT MAX(CAST(threshold_value AS FLOAT64))
      FROM `onyga-482313`.OI.DE_COACH_THRESHOLDS
      WHERE threshold_key = 'PROFITABLE_ROAS' AND strategy_id = 'GLOBAL'
    )) THEN 'profitable'
    ELSE 'unprofitable'
  END AS profit_state,
  MAX(last_seen) AS last_seen
FROM live_base
LEFT JOIN floors fl ON fl.strategy_id = live_base.strategy_category
WHERE cell_key IS NOT NULL
GROUP BY cell_key, strategy_category, campaign_id
);
