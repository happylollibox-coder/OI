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
    ARRAY_AGG(campaign_name ORDER BY date DESC LIMIT 1)[OFFSET(0)] AS campaign_name,
    ARRAY_AGG(serving_status ORDER BY date DESC LIMIT 1)[OFFSET(0)] AS serving_status
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
  WHERE is_primary_family   -- stray cross-family units must not fake coverage
),
-- Name-derived role fallback for campaigns V_CAMPAIGN_ROLE cannot classify yet (created today).
-- Shared with FN_COVERAGE_UNMAPPED so both agree on what counts as "mapped".
-- See V_CAMPAIGN_ROLE_BY_NAME: fallback only, never an override.
live_base AS (
  SELECT * FROM (
  SELECT
    r.parent_name, r.gp_per_unit,
    COALESCE(vcr.strategy_category, nr.strategy_category) AS strategy_category,
    r.campaign_id, cst.state, cst.campaign_name, cst.serving_status,
    r.impressions, r.clicks, r.cost, r.units, r.last_seen,
    CASE
      WHEN COALESCE(vcr.strategy_category, nr.strategy_category) = 'AUTO' THEN CONCAT('AUTO|', r.asin)
      WHEN COALESCE(vcr.strategy_category, nr.strategy_category) = 'PRODUCT_DEFENSE' THEN 'PRODUCT_DEFENSE|__STORE__'
      WHEN COALESCE(vcr.strategy_category, nr.strategy_category) IN ('BROAD_SP', 'BROAD_VIDEO', 'BROAD_SPOTLIGHT', 'PHRASE', 'EXACT', 'COMPETITOR', 'BRAND_DEFENSE')
        THEN CONCAT(COALESCE(vcr.strategy_category, nr.strategy_category), '|', r.parent_name)
      ELSE NULL
    END AS cell_key
  FROM src_rows r
  -- LEFT, not inner: a campaign that has begun delivering but is not yet in V_CAMPAIGN_ROLE
  -- (created today) would otherwise be dropped WITH its real metrics.
  LEFT JOIN `onyga-482313`.OI.V_CAMPAIGN_ROLE vcr ON vcr.campaign_id = r.campaign_id
  LEFT JOIN `onyga-482313`.OI.V_CAMPAIGN_ROLE_BY_NAME nr ON nr.campaign_id = r.campaign_id
  LEFT JOIN camp_state cst ON cst.campaign_id = r.campaign_id
  )
  WHERE strategy_category IS NOT NULL

  UNION ALL

  -- ── NEW CAMPAIGNS: ENABLED on Amazon but not delivering yet (0 impressions) ──
  -- A campaign created today has no impressions, so the `adv` gate above drops it and the cockpit
  -- shows nothing — exactly when you most want to confirm what you just built (Ori 2026-07-24:
  -- "show them as ENABLED (0 impressions) under the ENABLED campaigns").
  -- Neither V_CAMPAIGN_ROLE (90d-activity-gated) nor DIM_EXPERIMENT_CAMPAIGN (needs a manual
  -- mapping) knows them, so family + strategy are derived from the campaign NAME — safe here
  -- because the cockpit generates these names itself ({PREFIX}-{FORMAT}/{TARGETING} (qualifiers),
  -- see FN_COMPETITOR_CAMPAIGN_PLAN). Only high-confidence patterns map; anything unrecognised is
  -- skipped rather than guessed into the wrong cell. AUTO is excluded on purpose: its cell_key is
  -- per-ASIN and a campaign with no delivery has no ASIN to key on.
  SELECT
    n.parent_name, 0.0 AS gp_per_unit,
    n.strategy_category,
    n.campaign_id, n.state, n.campaign_name,
    -- brand-new ENABLED campaign shown as "ENABLED (0 impressions)"; treat as serving-eligible so is_enabled stays true
    'CAMPAIGN_STATUS_ENABLED' AS serving_status,
    0 AS impressions, 0 AS clicks, 0.0 AS cost, 0 AS units,
    CAST(NULL AS DATE) AS last_seen,
    IF(n.strategy_category = 'PRODUCT_DEFENSE',
       'PRODUCT_DEFENSE|__STORE__',
       CONCAT(n.strategy_category, '|', n.parent_name)) AS cell_key
  FROM `onyga-482313`.OI.V_CAMPAIGN_ROLE_BY_NAME n
  WHERE n.state = 'ENABLED'
    AND n.parent_name IS NOT NULL
    AND n.strategy_category IS NOT NULL
    AND n.campaign_id NOT IN (SELECT campaign_id FROM src_rows)
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
  -- serving now, not just stale state=ENABLED (an ENDED campaign keeps a stale ENABLED state row)
  (ANY_VALUE(state) = 'ENABLED' AND ANY_VALUE(serving_status) IN ('CAMPAIGN_STATUS_ENABLED', 'CAMPAIGN_OUT_OF_BUDGET')) AS is_enabled,
  CAST(SUM(impressions) AS INT64) AS impressions,
  CAST(SUM(clicks) AS INT64) AS clicks,
  CAST(SUM(units) AS INT64) AS units,
  ROUND(SUM(cost), 2) AS ad_spend,
  ROUND(SAFE_DIVIDE(SUM(cost), NULLIF(SUM(clicks), 0)), 2) AS cpc,
  ROUND(SAFE_DIVIDE(SUM(units * gp_per_unit), NULLIF(SUM(cost), 0)), 2) AS net_roas,
  ROUND(SUM(units * gp_per_unit) - SUM(cost), 2) AS net_profit,
  -- Binary NP verdict (Ori 2026-07-26): net profit positive -> green, else red.
  -- Zero spend stays 'unknown' (a silent campaign is not losing). No click floor,
  -- no ROAS-threshold indirection: NP = units x gp - cost, sign decides.
  CASE
    WHEN COALESCE(SUM(cost), 0) = 0 THEN 'unknown'
    WHEN SUM(units * gp_per_unit) - SUM(cost) > 0 THEN 'profitable'
    ELSE 'unprofitable'
  END AS profit_state,
  MAX(last_seen) AS last_seen
FROM live_base
LEFT JOIN floors fl ON fl.strategy_id = live_base.strategy_category
WHERE cell_key IS NOT NULL
GROUP BY cell_key, strategy_category, campaign_id
);
