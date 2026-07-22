-- V_COVERAGE_UNMAPPED — coverage-cockpit guard tile (7th "strategy": UNMAPPED)
--
-- Surfaces ad campaigns that DON'T classify into any of the 6 strategies, so unclassified
-- spend stops being invisible. The cockpit INNER-joins V_CAMPAIGN_ROLE and drops
-- strategy_category='OTHER'/unmatched — this view catches exactly those.
--
-- UNMAPPED = a campaign with 90-day advertised activity whose strategy_category
-- (LEFT JOIN V_CAMPAIGN_ROLE) is NULL or 'OTHER' (i.e. not one of
-- AUTO/INTENT/EXACT_BOOST/COMPETITOR/BRAND_DEFENSE/PRODUCT_DEFENSE), UNION any
-- V_CAMPAIGN_ROLE row classified 'OTHER' with no recent activity (dormant unclassified).
--
-- Reuses the same building blocks as V_COVERAGE_CAMPAIGN:
--   prod       : own sellable ASINs + gp_per_unit (listing price − unit cost)
--   camp_state : latest state + campaign_name from V_SRC_AmazonAds_campaign_history
--   adv        : advertised_product asin<->campaign link, 90d metric window
-- One row per campaign_id.
CREATE OR REPLACE VIEW `onyga-482313.OI.V_COVERAGE_UNMAPPED` AS
WITH
-- ── Own sellable products (for gp_per_unit + own-family label) ──
prod AS (
  SELECT dp.asin, dp.parent_name,
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
-- ── Advertised-product rows, last 90d, LEFT JOINed to own products for gp/family ──
adv AS (
  SELECT
    ap.campaign_id,
    ap.advertised_asin,
    ap.date,
    ap.impressions, ap.clicks, ap.cost, ap.units_7d,
    p.parent_name AS own_parent_name,
    ap.units_7d * COALESCE(p.gp_per_unit, 0) AS margin
  FROM `onyga-482313`.OI.V_SRC_AmazonAds_advertised_product ap
  LEFT JOIN prod p ON p.asin = ap.advertised_asin
  WHERE ap.date >= DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY)
),
-- ── Per-campaign 90d aggregate over all advertised activity ──
adv_agg AS (
  SELECT
    campaign_id,
    ANY_VALUE(own_parent_name) AS parent_name,   -- own family (NULL if none own)
    CAST(SUM(impressions) AS INT64) AS impressions,
    CAST(SUM(clicks) AS INT64) AS clicks,
    CAST(SUM(units_7d) AS INT64) AS units,
    SUM(cost) AS cost,
    SUM(margin) AS margin,
    MAX(date) AS last_seen
  FROM adv
  GROUP BY campaign_id
),
-- ── GLOBAL PROFITABLE_ROAS floor ──
floor AS (
  SELECT MAX(CAST(threshold_value AS FLOAT64)) AS v
  FROM `onyga-482313`.OI.DE_COACH_THRESHOLDS
  WHERE threshold_key = 'PROFITABLE_ROAS' AND strategy_id = 'GLOBAL'
),
-- ── Campaigns mapped to a VALID strategy (DIM_EXPERIMENT_CAMPAIGN → DIM_EXPERIMENT
--    with a real strategy_id). Excluded below so mapping a campaign removes it from
--    Unmapped immediately, even when dormant (V_CAMPAIGN_ROLE is 90d-activity-gated).
--    A campaign mapped to a strategy_less experiment (strategy_id NULL) is NOT excluded
--    — it's effectively unmapped and still needs a real strategy. ──
mapped AS (
  SELECT DISTINCT CAST(ec.campaign_id AS STRING) AS campaign_id
  FROM `onyga-482313`.OI.DIM_EXPERIMENT_CAMPAIGN ec
  JOIN `onyga-482313`.OI.DIM_EXPERIMENT e USING (experiment_id)
  WHERE e.strategy_id IN ('AUTO','INTENT','EXACT_BOOST','COMPETITOR','BRAND_DEFENSE','PRODUCT_DEFENSE')
),
-- ── Active campaigns (90d) whose role is NULL or 'OTHER' → UNMAPPED ──
active_unmapped AS (
  SELECT a.campaign_id, a.parent_name,
    a.impressions, a.clicks, a.units, a.cost, a.margin, a.last_seen
  FROM adv_agg a
  LEFT JOIN `onyga-482313`.OI.V_CAMPAIGN_ROLE vcr ON vcr.campaign_id = a.campaign_id
  WHERE vcr.strategy_category IS NULL OR vcr.strategy_category = 'OTHER'
),
-- ── Dormant 'OTHER' campaigns with NO 90d activity (metrics 0/NULL) ──
dormant_other AS (
  SELECT vcr.campaign_id,
    CAST(NULL AS STRING) AS parent_name,
    0 AS impressions, 0 AS clicks, 0 AS units,
    0.0 AS cost, 0.0 AS margin,
    CAST(NULL AS DATE) AS last_seen
  FROM `onyga-482313`.OI.V_CAMPAIGN_ROLE vcr
  WHERE vcr.strategy_category = 'OTHER'
    AND vcr.campaign_id NOT IN (SELECT campaign_id FROM adv_agg)
),
unmapped AS (
  SELECT * FROM active_unmapped
  UNION ALL
  SELECT * FROM dormant_other
)
SELECT
  u.campaign_id,
  cst.campaign_name,
  u.parent_name,
  cst.state,
  cst.state = 'ENABLED' AS is_enabled,
  u.impressions,
  u.clicks,
  u.units,
  u.cost,
  ROUND(SAFE_DIVIDE(u.margin, NULLIF(u.cost, 0)), 2) AS net_roas,
  ROUND(SAFE_DIVIDE(u.cost, NULLIF(u.clicks, 0)), 2) AS cpc,
  u.last_seen,
  CASE
    WHEN u.clicks < 10 THEN 'unknown'
    WHEN ROUND(SAFE_DIVIDE(u.margin, NULLIF(u.cost, 0)), 2) IS NULL THEN 'unknown'
    WHEN ROUND(SAFE_DIVIDE(u.margin, NULLIF(u.cost, 0)), 2) >= (SELECT v FROM floor) THEN 'profitable'
    ELSE 'unprofitable'
  END AS profit_state
FROM unmapped u
LEFT JOIN camp_state cst ON cst.campaign_id = u.campaign_id
WHERE u.campaign_id NOT IN (SELECT campaign_id FROM mapped)
