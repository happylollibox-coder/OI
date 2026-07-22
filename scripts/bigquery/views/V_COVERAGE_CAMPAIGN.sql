-- V_COVERAGE_CAMPAIGN — coverage-cockpit reconciler (sub-project: owned-negatives / coverage, Stage 1)
--
-- Per (target cell) reconciles what SHOULD exist vs what DOES exist (live enabled campaigns),
-- classified through the 6-strategy lens of V_CAMPAIGN_ROLE.strategy_category (NOT `role`).
--
-- Grain per strategy (there is NO campaign->intent linkage in the live account):
--   AUTO            -> grain='ASIN'   one row per own sellable ASIN
--   INTENT          -> grain='FAMILY' one row per own family   (expected)
--   BRAND_DEFENSE   -> grain='FAMILY' one row per own family   (expected)
--   COMPETITOR      -> grain='FAMILY' one row per own family   (NOT expected -> 'none' when absent)
--   EXACT_BOOST     -> grain='FAMILY' one row per own family   (NOT expected -> 'none' when absent)
--   PRODUCT_DEFENSE -> grain='STORE'  exactly one row (parent_name NULL)
--
-- Assembly reuses ads_coverage_scan() (data-entry-app/app.py ~8974): own-product universe,
-- gp_per_unit, campaign state, advertised_product asin<->campaign link, 90-day metric window.
CREATE OR REPLACE VIEW `onyga-482313.OI.V_COVERAGE_CAMPAIGN` AS
WITH
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
fams AS (
  SELECT DISTINCT parent_name FROM prod
),
-- ── Latest campaign state + display name ──
camp_state AS (
  SELECT campaign_id,
    ARRAY_AGG(state ORDER BY date DESC LIMIT 1)[OFFSET(0)] AS state,
    ARRAY_AGG(campaign_name ORDER BY date DESC LIMIT 1)[OFFSET(0)] AS campaign_name
  FROM `onyga-482313`.OI.V_SRC_AmazonAds_campaign_history GROUP BY 1
),
-- ── Authoritative asin<->campaign link + 90-day metrics ──
adv AS (
  SELECT advertised_asin AS asin, campaign_id,
    SUM(impressions) AS impressions, SUM(clicks) AS clicks,
    SUM(cost) AS cost, SUM(units_7d) AS units
  FROM `onyga-482313`.OI.V_SRC_AmazonAds_advertised_product
  WHERE date >= DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY)
  GROUP BY 1, 2
),
-- ── Live rows: one per (own asin, campaign) with strategy_category + cell_key ──
live_base AS (
  SELECT
    p.parent_name, p.asin, p.gp_per_unit,
    vcr.strategy_category,
    adv.campaign_id, cst.state, cst.campaign_name,
    adv.impressions, adv.clicks, adv.cost, adv.units,
    CASE
      WHEN vcr.strategy_category = 'AUTO' THEN CONCAT('AUTO|', p.asin)
      WHEN vcr.strategy_category = 'PRODUCT_DEFENSE' THEN 'PRODUCT_DEFENSE|__STORE__'
      WHEN vcr.strategy_category IN ('INTENT', 'BRAND_DEFENSE', 'COMPETITOR', 'EXACT_BOOST')
        THEN CONCAT(vcr.strategy_category, '|', p.parent_name)
      ELSE NULL  -- OTHER / unclassified: not a target cell, dropped below
    END AS cell_key
  FROM prod p
  JOIN adv ON adv.asin = p.asin
  JOIN `onyga-482313`.OI.V_CAMPAIGN_ROLE vcr ON vcr.campaign_id = adv.campaign_id
  LEFT JOIN camp_state cst ON cst.campaign_id = adv.campaign_id
),
live_agg AS (
  SELECT cell_key,
    COUNT(DISTINCT IF(state = 'ENABLED', campaign_id, NULL)) AS n_enabled,
    COUNT(DISTINCT campaign_id) AS n_any,
    CAST(SUM(impressions) AS INT64) AS impressions,
    CAST(SUM(clicks) AS INT64) AS clicks,
    CAST(SUM(units) AS INT64) AS units,
    ROUND(SAFE_DIVIDE(SUM(units * gp_per_unit), NULLIF(SUM(cost), 0)), 2) AS net_roas,
    STRING_AGG(DISTINCT IF(state = 'ENABLED', campaign_name, NULL), ' | ') AS campaigns
  FROM live_base
  WHERE cell_key IS NOT NULL
  GROUP BY cell_key
),
-- ── Target universe: every cell that COULD/SHOULD exist, at its grain ──
target AS (
  -- AUTO: one row per own sellable ASIN
  SELECT 'ASIN' AS grain, parent_name, asin, product_short_name,
    'AUTO' AS strategy, TRUE AS expected, CONCAT('AUTO|', asin) AS cell_key
  FROM prod
  UNION ALL
  -- Family strategies (expected: INTENT, BRAND_DEFENSE; not-expected: COMPETITOR, EXACT_BOOST)
  SELECT 'FAMILY' AS grain, f.parent_name, CAST(NULL AS STRING) AS asin,
    CAST(NULL AS STRING) AS product_short_name,
    s.strategy, s.expected, CONCAT(s.strategy, '|', f.parent_name) AS cell_key
  FROM fams f
  CROSS JOIN UNNEST([
    STRUCT('INTENT' AS strategy, TRUE AS expected),
    STRUCT('BRAND_DEFENSE' AS strategy, TRUE AS expected),
    STRUCT('COMPETITOR' AS strategy, FALSE AS expected),
    STRUCT('EXACT_BOOST' AS strategy, FALSE AS expected)
  ]) s
  UNION ALL
  -- PRODUCT_DEFENSE: single store-wide row
  SELECT 'STORE' AS grain, CAST(NULL AS STRING) AS parent_name, CAST(NULL AS STRING) AS asin,
    CAST(NULL AS STRING) AS product_short_name,
    'PRODUCT_DEFENSE' AS strategy, TRUE AS expected, 'PRODUCT_DEFENSE|__STORE__' AS cell_key
),
-- ── Manual suppression overrides (deduped to one row per cell) ──
suppress AS (
  SELECT parent_name, asin, strategy, TRUE AS suppressed
  FROM `onyga-482313`.OI.DE_COVERAGE_EXPECTATION
  WHERE is_active
  GROUP BY parent_name, asin, strategy
)
SELECT
  t.grain,
  t.cell_key AS cell_key,
  t.parent_name,
  t.asin,
  t.product_short_name,
  t.strategy,
  t.expected,
  COALESCE(l.n_enabled, 0) AS n_enabled,
  COALESCE(l.n_any, 0) AS n_any,
  COALESCE(l.impressions, 0) AS impressions,
  COALESCE(l.clicks, 0) AS clicks,
  COALESCE(l.units, 0) AS units,
  l.net_roas,
  l.campaigns,
  COALESCE(sp.suppressed, FALSE) AS suppressed,
  CASE
    WHEN COALESCE(sp.suppressed, FALSE) THEN 'suppressed'
    WHEN NOT t.expected THEN
      CASE WHEN COALESCE(l.n_enabled, 0) = 0 THEN 'none'
           WHEN l.n_enabled > 1 THEN 'redundant'
           ELSE 'ok' END
    ELSE
      CASE WHEN COALESCE(l.n_enabled, 0) = 0 THEN 'missing'
           WHEN l.n_enabled > 1 THEN 'redundant'
           ELSE 'ok' END
  END AS status,
  -- ── S2 VERIFY: plain-English reason per cell (label = product / family / Store) ──
  CASE
    WHEN COALESCE(sp.suppressed, FALSE)
      THEN CONCAT('Marked not-expected for ', COALESCE(t.product_short_name, t.parent_name, 'Store'), '.')
    -- 'missing' = expected AND no enabled campaign
    WHEN t.expected AND COALESCE(l.n_enabled, 0) = 0 AND COALESCE(l.n_any, 0) > 0
      THEN CONCAT('No enabled ', t.strategy, ' campaign for ', COALESCE(t.product_short_name, t.parent_name, 'Store'),
                  ' — ', CAST(COALESCE(l.n_any, 0) AS STRING), ' paused/archived in history (was running, now off).')
    WHEN t.expected AND COALESCE(l.n_enabled, 0) = 0 AND COALESCE(l.n_any, 0) = 0
      THEN CONCAT('No ', t.strategy, ' campaign ever built for ', COALESCE(t.product_short_name, t.parent_name, 'Store'), '.')
    WHEN COALESCE(l.n_enabled, 0) > 1
      THEN CONCAT(CAST(l.n_enabled AS STRING), ' enabled ', t.strategy, ' campaigns competing for ',
                  COALESCE(t.product_short_name, t.parent_name, 'Store'), ' — consider consolidating.')
    WHEN COALESCE(l.n_enabled, 0) = 1
      THEN CONCAT('1 enabled ', t.strategy, ' campaign for ', COALESCE(t.product_short_name, t.parent_name, 'Store'),
                  IFNULL(CONCAT(', ', FORMAT('%.2f', l.net_roas), 'x net ROAS (90d).'), '.'))
    -- 'none' = not-expected AND no enabled campaign
    ELSE CONCAT('No ', t.strategy, ' campaign for ', COALESCE(t.product_short_name, t.parent_name, 'Store'),
                ' — optional, not flagged as missing.')
  END AS reason
FROM target t
LEFT JOIN live_agg l USING (cell_key)
LEFT JOIN suppress sp
  ON sp.parent_name IS NOT DISTINCT FROM t.parent_name
 AND sp.asin IS NOT DISTINCT FROM t.asin
 AND sp.strategy = t.strategy
