-- FN_COVERAGE_UNMAPPED(win_start, win_end, peak_only) — coverage-cockpit guard tile (UNMAPPED), windowed.
-- Table-function version of V_COVERAGE_UNMAPPED: campaigns that don't classify into any of the 6 strategies,
-- with advertised activity aggregated over the caller-supplied [win_start, win_end] (peak_only=TRUE restricts
-- to gift-season days). Dormant 'OTHER' campaigns (no activity in the window) are still surfaced — they're
-- structurally unmapped regardless of window. One row per campaign_id.
CREATE OR REPLACE TABLE FUNCTION `onyga-482313.OI.FN_COVERAGE_UNMAPPED`(win_start DATE, win_end DATE, peak_only BOOL) AS (
WITH
peak_dates AS (
  SELECT DISTINCT d AS date
  FROM `onyga-482313`.OI.DIM_US_HOLIDAYS h, UNNEST(GENERATE_DATE_ARRAY(h.boost_start, h.cooldown_end)) d
  WHERE h.category = 'gift_season'
),
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
  -- 2026-07-30: consolidated source (V_DIM_CAMPAIGN_CURRENT / DIM_*) per prefer-DIM/FACT rule; was V_SRC_AmazonAds_campaign_history
  SELECT campaign_id,
    campaign_state AS state,
    campaign_name
  FROM `onyga-482313`.OI.V_DIM_CAMPAIGN_CURRENT
),
-- ── Advertised-product rows over the window, LEFT JOINed to own products for gp/family ──
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
  WHERE ap.date BETWEEN win_start AND win_end
    AND (NOT peak_only OR ap.date IN (SELECT date FROM peak_dates))
),
adv_agg AS (
  SELECT
    campaign_id,
    ANY_VALUE(own_parent_name) AS parent_name,
    CAST(SUM(impressions) AS INT64) AS impressions,
    CAST(SUM(clicks) AS INT64) AS clicks,
    CAST(SUM(units_7d) AS INT64) AS units,
    SUM(cost) AS cost,
    SUM(margin) AS margin,
    MAX(date) AS last_seen
  FROM adv
  GROUP BY campaign_id
),
floor AS (
  SELECT MAX(CAST(threshold_value AS FLOAT64)) AS v
  FROM `onyga-482313`.OI.DE_COACH_THRESHOLDS
  WHERE threshold_key = 'PROFITABLE_ROAS' AND strategy_id = 'GLOBAL'
),
mapped AS (
  SELECT DISTINCT CAST(ec.campaign_id AS STRING) AS campaign_id
  FROM `onyga-482313`.OI.DIM_EXPERIMENT_CAMPAIGN ec
  JOIN `onyga-482313`.OI.DIM_EXPERIMENT e USING (experiment_id)
  WHERE e.strategy_id IN ('AUTO','BROAD_SP','BROAD_VIDEO','BROAD_SPOTLIGHT','PHRASE','EXACT','COMPETITOR','BRAND_DEFENSE','PRODUCT_DEFENSE')
),
active_unmapped AS (
  SELECT a.campaign_id, a.parent_name,
    a.impressions, a.clicks, a.units, a.cost, a.margin, a.last_seen
  FROM adv_agg a
  LEFT JOIN `onyga-482313`.OI.V_CAMPAIGN_ROLE vcr ON vcr.campaign_id = a.campaign_id
  -- A campaign whose NAME resolves to a strategy is NOT unmapped — FN_COVERAGE_CAMPAIGN_DETAIL
  -- now places it in its cell via the same fallback, so listing it here too would double-count a
  -- brand-new campaign as both covered and unmapped (Ori 2026-07-24).
  LEFT JOIN `onyga-482313`.OI.V_CAMPAIGN_ROLE_BY_NAME nr ON nr.campaign_id = a.campaign_id
  WHERE (vcr.strategy_category IS NULL OR vcr.strategy_category = 'OTHER')
    AND (nr.strategy_category IS NULL OR nr.parent_name IS NULL)
),
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
  -- An ARCHIVED campaign can never need mapping — it's history, not work. The endpoint keeps its
  -- spend in the P&L rollups (so wide-window money stays truthful) but excludes it from the
  -- UNMAPPED to-do list + badge. Without this, 12mo/Peak surfaced 42 dead campaigns as "to map"
  -- (Ori 2026-07-23). NULL state (never seen in campaign_history) is treated as actionable.
  COALESCE(cst.state, '') = 'ARCHIVED' AS is_archived,
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
);
