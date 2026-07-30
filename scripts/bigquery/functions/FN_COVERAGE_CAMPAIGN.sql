-- FN_COVERAGE_CAMPAIGN(win_start, win_end, peak_only) — window-parameterized coverage reconciler.
-- Table-function version of the former V_COVERAGE_CAMPAIGN: identical cell/status/reason logic, but the
-- (asin×campaign) metric window is now the caller-supplied [win_start, win_end] (peak_only=TRUE additionally
-- restricts to gift-season days). The whole view reflects the window: coverage counts, status AND measures.
--   gate = "served impressions in the window" (a pair with 0 window impressions isn't current coverage FOR that window).
-- Callers: /api/coverage maps its 7 toggle windows (today/yesterday/7d/30d/90d/12mo/peak) to (start,end,peak_only).
CREATE OR REPLACE TABLE FUNCTION `onyga-482313.OI.FN_COVERAGE_CAMPAIGN`(win_start DATE, win_end DATE, peak_only BOOL) AS (
WITH
-- gift-season days (for peak_only); harmless when peak_only=FALSE.
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
fams AS (
  SELECT DISTINCT parent_name FROM prod
),
-- ── Latest campaign state + display name ──
camp_state AS (
  -- 2026-07-30: consolidated source (V_DIM_CAMPAIGN_CURRENT / DIM_*) per prefer-DIM/FACT rule; was V_SRC_AmazonAds_campaign_history latest-row read
  SELECT campaign_id,
    campaign_state AS state,
    campaign_name,
    -- Amazon's own serving verdict — catches ENDED/PENDING campaigns whose last STATE row still reads
    -- ENABLED because the change-log is event-based and the end/archive event never synced.
    serving_status
  FROM `onyga-482313`.OI.V_DIM_CAMPAIGN_CURRENT
),
-- ── DARK: campaigns CONFIGURED (state=ENABLED) but NOT DELIVERING ──
-- Why this exists: the metric gate below keeps only pairs that served impressions in the window, so a
-- dark campaign silently VANISHES — and a cell whose only campaign is dark then reads 'missing', as if
-- nothing were configured. That invites building a duplicate campaign when one already exists and just
-- isn't serving. These cells get status 'dark' instead (Ori 2026-07-23).
--
-- Delivery check uses FACT_AMAZON_ADS because it covers SP **and** SB. advertised_product omits
-- Sponsored Brands entirely, so checking it alone would flag the whole SB/VIDEO portfolio as dark.
-- Cell link uses the EXPLICIT mapping (DIM_EXPERIMENT_CAMPAIGN→DIM_EXPERIMENT + DE_CAMPAIGN_FAMILY),
-- because V_CAMPAIGN_ROLE is 90d-activity-gated and therefore blind to exactly these campaigns.
-- "Dark" is always judged on the LAST 30 DAYS regardless of the selected window: the window governs
-- money (what was spent), current state governs work (what needs fixing).
served_30d AS (
  SELECT DISTINCT CAST(campaign_id AS STRING) AS campaign_id
  FROM `onyga-482313`.OI.FACT_AMAZON_ADS
  WHERE date >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY) AND Ads_impressions > 0
),
camp_strategy_explicit AS (
  SELECT CAST(ec.campaign_id AS STRING) AS campaign_id, ANY_VALUE(e.strategy_id) AS strategy_id
  FROM `onyga-482313`.OI.DIM_EXPERIMENT_CAMPAIGN ec
  JOIN `onyga-482313`.OI.DIM_EXPERIMENT e USING (experiment_id)
  GROUP BY 1
),
-- Fallback family: whatever the campaign historically advertised. Uses advertised_product because its
-- asin<->campaign link is authoritative; FACT_AMAZON_ADS's ASIN columns mis-attribute across families
-- (it is safe only at campaign grain, which is why the delivery check above may use it but this may not).
-- SB campaigns have no advertised_product rows, so an SB campaign with no DE_CAMPAIGN_FAMILY row stays
-- unresolved and simply doesn't attach to a cell (better than inventing a wrong one).
camp_family_hist AS (
  SELECT ap.campaign_id, ANY_VALUE(dp.parent_name) AS parent_name
  FROM `onyga-482313`.OI.V_SRC_AmazonAds_advertised_product ap
  JOIN `onyga-482313`.OI.DIM_PRODUCT dp ON dp.asin = ap.advertised_asin
  WHERE dp.parent_name IS NOT NULL AND dp.parent_name != 'UNKNOWN'
  GROUP BY 1
),
dark AS (
  SELECT cst.campaign_id, cst.campaign_name, se.strategy_id,
         COALESCE(cf.parent_name, fh.parent_name) AS parent_name
  FROM camp_state cst
  JOIN camp_strategy_explicit se ON se.campaign_id = cst.campaign_id
  LEFT JOIN `onyga-482313`.OI.DE_CAMPAIGN_FAMILY cf ON cf.campaign_id = cst.campaign_id
  LEFT JOIN camp_family_hist fh ON fh.campaign_id = cst.campaign_id
  WHERE cst.state = 'ENABLED'
    -- Only a genuinely-enabled campaign can be "dark". serving_status='ENDED' means the end date passed
    -- (the 4 BOX campaigns Ori confirmed archived, still ENABLED in the stale state feed) and
    -- 'PENDING_START_DATE' means it hasn't started yet — neither is "configured but broken", so they must
    -- not be flagged dark. CAMPAIGN_OUT_OF_BUDGET campaigns are serving, so they're already in served_30d.
    AND cst.serving_status = 'CAMPAIGN_STATUS_ENABLED'
    AND cst.campaign_id NOT IN (SELECT campaign_id FROM served_30d)
),
dark_agg AS (
  SELECT cell_key, COUNT(DISTINCT campaign_id) AS n_dark,
         STRING_AGG(DISTINCT campaign_name, ' | ') AS dark_campaigns
  FROM (
    SELECT campaign_id, campaign_name,
      CASE
        WHEN strategy_id = 'PRODUCT_DEFENSE' THEN 'PRODUCT_DEFENSE|__STORE__'
        WHEN strategy_id IN ('BROAD_SP', 'BROAD_VIDEO', 'BROAD_SPOTLIGHT', 'PHRASE', 'EXACT', 'COMPETITOR', 'BRAND_DEFENSE')
             AND parent_name IS NOT NULL THEN CONCAT(strategy_id, '|', parent_name)
        ELSE NULL   -- AUTO is ASIN-grain (unresolvable without activity); unknown family dropped
      END AS cell_key
    FROM dark
  )
  WHERE cell_key IS NOT NULL
  GROUP BY cell_key
),
-- ── Authoritative asin<->campaign link + WINDOW metrics ──
-- The (asin × campaign) pair IS the product-ad. Metrics are aggregated over the selected window
-- [win_start, win_end] (peak_only additionally restricts to gift-season days). The gate keeps a pair only
-- if it served impressions IN the window, so a pair dark across the whole window isn't counted as coverage for it.
adv AS (
  SELECT asin, campaign_id, impressions, clicks, cost, units
  FROM (
    SELECT advertised_asin AS asin, campaign_id,
      SUM(impressions) AS impressions, SUM(clicks) AS clicks,
      SUM(cost) AS cost, SUM(units_7d) AS units
    FROM `onyga-482313`.OI.V_SRC_AmazonAds_advertised_product
    WHERE date BETWEEN win_start AND win_end
      AND (NOT peak_only OR date IN (SELECT date FROM peak_dates))
    GROUP BY 1, 2
  )
  WHERE impressions > 0
),
-- ── Metric rows, one per (own asin, campaign), from BOTH ad products ──
--   SP: the advertised_product feed (asin<->campaign is native there).
--   SB: FN_COVERAGE_SB — Sponsored Brands don't appear in advertised_product at all, so before
--       this union the whole SB portfolio was invisible to every cell/count/P&L (Ori 2026-07-23).
--       It attributes units by PURCHASED asin and splits campaign cost pro-rata by units.
src_rows AS (
  SELECT p.parent_name, p.asin, p.gp_per_unit, adv.campaign_id,
         adv.impressions, adv.clicks, adv.cost, adv.units
  FROM prod p
  JOIN adv ON adv.asin = p.asin
  UNION ALL
  SELECT parent_name, asin, gp_per_unit, campaign_id, impressions, clicks, cost, units
  FROM `onyga-482313`.OI.FN_COVERAGE_SB(win_start, win_end, peak_only)
  WHERE is_primary_family   -- stray cross-family units must not fake coverage
),
-- ── Live rows: one per (own asin, campaign) with strategy_category + cell_key ──
live_base AS (
  SELECT
    r.parent_name, r.asin, r.gp_per_unit,
    vcr.strategy_category,
    r.campaign_id, cst.state, cst.campaign_name,
    -- "Serving right now?" — an ENDED/PENDING campaign that delivered EARLIER in a wide window would
    -- otherwise be counted as current coverage. Gate n_enabled on the live serving verdict, not stale state.
    (cst.state = 'ENABLED' AND cst.serving_status IN ('CAMPAIGN_STATUS_ENABLED', 'CAMPAIGN_OUT_OF_BUDGET')) AS is_serving,
    r.impressions, r.clicks, r.cost, r.units,
    CASE
      -- AUTO is ASIN-grain; SB no-conversion rows carry a NULL asin, so CONCAT yields NULL and
      -- they are dropped rather than inventing a bogus cell (SB is never AUTO in practice).
      WHEN vcr.strategy_category = 'AUTO' THEN CONCAT('AUTO|', r.asin)
      WHEN vcr.strategy_category = 'PRODUCT_DEFENSE' THEN 'PRODUCT_DEFENSE|__STORE__'
      WHEN vcr.strategy_category IN ('BROAD_SP', 'BROAD_VIDEO', 'BROAD_SPOTLIGHT', 'PHRASE', 'EXACT', 'COMPETITOR', 'BRAND_DEFENSE')
        THEN CONCAT(vcr.strategy_category, '|', r.parent_name)
      ELSE NULL
    END AS cell_key
  FROM src_rows r
  JOIN `onyga-482313`.OI.V_CAMPAIGN_ROLE vcr ON vcr.campaign_id = r.campaign_id
  LEFT JOIN camp_state cst ON cst.campaign_id = r.campaign_id
),
live_agg AS (
  SELECT cell_key,
    COUNT(DISTINCT IF(is_serving, campaign_id, NULL)) AS n_enabled,
    COUNT(DISTINCT campaign_id) AS n_any,
    CAST(SUM(impressions) AS INT64) AS impressions,
    CAST(SUM(clicks) AS INT64) AS clicks,
    CAST(SUM(units) AS INT64) AS units,
    SUM(cost) AS cost,
    ROUND(SAFE_DIVIDE(SUM(units * gp_per_unit), NULLIF(SUM(cost), 0)), 2) AS net_roas,
    ROUND(SUM(units * gp_per_unit) - SUM(cost), 2) AS net_profit,
    STRING_AGG(DISTINCT IF(is_serving, campaign_name, NULL), ' | ') AS campaigns
  FROM live_base
  WHERE cell_key IS NOT NULL
  GROUP BY cell_key
),
-- ── Target universe: every cell that COULD/SHOULD exist, at its grain ──
target AS (
  SELECT 'ASIN' AS grain, parent_name, asin, product_short_name,
    'AUTO' AS strategy, TRUE AS expected, CONCAT('AUTO|', asin) AS cell_key
  FROM prod
  UNION ALL
  SELECT 'FAMILY' AS grain, f.parent_name, CAST(NULL AS STRING) AS asin,
    CAST(NULL AS STRING) AS product_short_name,
    s.strategy, s.expected, CONCAT(s.strategy, '|', f.parent_name) AS cell_key
  FROM fams f
  CROSS JOIN UNNEST([
    -- Ori 2026-07-23: all three Broad formats are REQUIRED per family (SP + Video + Spotlight).
    -- Phrase/Exact/Competitor are EARNED, not required — they get 'none' rather than 'missing'.
    STRUCT('BROAD_SP' AS strategy, TRUE AS expected),
    STRUCT('BROAD_VIDEO' AS strategy, TRUE AS expected),
    STRUCT('BROAD_SPOTLIGHT' AS strategy, TRUE AS expected),
    STRUCT('BRAND_DEFENSE' AS strategy, TRUE AS expected),
    STRUCT('PHRASE' AS strategy, FALSE AS expected),
    STRUCT('EXACT' AS strategy, FALSE AS expected),
    STRUCT('COMPETITOR' AS strategy, FALSE AS expected)
  ]) s
  UNION ALL
  SELECT 'STORE' AS grain, CAST(NULL AS STRING) AS parent_name, CAST(NULL AS STRING) AS asin,
    CAST(NULL AS STRING) AS product_short_name,
    'PRODUCT_DEFENSE' AS strategy, TRUE AS expected, 'PRODUCT_DEFENSE|__STORE__' AS cell_key
),
suppress AS (
  SELECT parent_name, asin, strategy, TRUE AS suppressed
  FROM `onyga-482313`.OI.DE_COVERAGE_EXPECTATION
  WHERE is_active
  GROUP BY parent_name, asin, strategy
),
floors AS (
  SELECT strategy_id, MAX(CAST(threshold_value AS FLOAT64)) AS v
  FROM `onyga-482313`.OI.DE_COACH_THRESHOLDS
  WHERE threshold_key = 'PROFITABLE_ROAS'
  GROUP BY strategy_id
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
  COALESCE(l.cost, 0) AS cost,
  ROUND(SAFE_DIVIDE(l.cost, NULLIF(l.clicks, 0)), 2) AS cpc,
  l.net_roas,
  l.net_profit,
  -- Binary NP verdict (Ori 2026-07-26): positive net profit -> 'profitable' (green),
  -- any spend without positive NP -> 'unprofitable' (red); zero spend -> 'unknown'.
  CASE
    WHEN COALESCE(l.cost, 0) = 0 THEN 'unknown'
    WHEN COALESCE(l.net_roas, 0) > 1 THEN 'profitable'  -- NP>0 <=> net_roas>1 given cost>0
    ELSE 'unprofitable'
  END AS profit_state,
  l.campaigns,
  COALESCE(d.n_dark, 0) AS n_dark,
  d.dark_campaigns,
  COALESCE(sp.suppressed, FALSE) AS suppressed,
  CASE
    WHEN COALESCE(sp.suppressed, FALSE) THEN 'suppressed'
    -- A configured-but-not-delivering campaign exists → 'dark', NOT 'missing'. Without this the
    -- campaign vanishes (no in-window impressions) and the cell reads as if nothing were set up.
    WHEN COALESCE(l.n_enabled, 0) = 0 AND COALESCE(d.n_dark, 0) > 0 THEN 'dark'
    WHEN NOT t.expected THEN
      CASE WHEN COALESCE(l.n_enabled, 0) = 0 THEN 'none'
           WHEN l.n_enabled > 1 THEN 'redundant'
           ELSE 'ok' END
    ELSE
      CASE WHEN COALESCE(l.n_enabled, 0) = 0 THEN 'missing'
           WHEN l.n_enabled > 1 THEN 'redundant'
           ELSE 'ok' END
  END AS status,
  CASE
    WHEN COALESCE(sp.suppressed, FALSE)
      THEN CONCAT('Marked not-expected for ', COALESCE(t.product_short_name, t.parent_name, 'Store'), '.')
    WHEN COALESCE(l.n_enabled, 0) = 0 AND COALESCE(d.n_dark, 0) > 0
      THEN CONCAT(CAST(d.n_dark AS STRING), ' ', t.strategy, ' campaign(s) enabled but NOT delivering for ',
                  COALESCE(t.product_short_name, t.parent_name, 'Store'), ' — ', d.dark_campaigns,
                  ' (no impressions in 30d). Fix budget/bid/eligibility or archive — do NOT build a duplicate.')
    WHEN t.expected AND COALESCE(l.n_enabled, 0) = 0 AND COALESCE(l.n_any, 0) > 0
      THEN CONCAT('No enabled ', t.strategy, ' campaign for ', COALESCE(t.product_short_name, t.parent_name, 'Store'),
                  ' — ', CAST(COALESCE(l.n_any, 0) AS STRING), ' paused/archived in window.')
    WHEN t.expected AND COALESCE(l.n_enabled, 0) = 0 AND COALESCE(l.n_any, 0) = 0
      THEN CONCAT('No ', t.strategy, ' campaign served in-window for ', COALESCE(t.product_short_name, t.parent_name, 'Store'), '.')
    WHEN COALESCE(l.n_enabled, 0) > 1
      THEN CONCAT(CAST(l.n_enabled AS STRING), ' enabled ', t.strategy, ' campaigns competing for ',
                  COALESCE(t.product_short_name, t.parent_name, 'Store'), ' — consider consolidating.')
    WHEN COALESCE(l.n_enabled, 0) = 1
      THEN CONCAT('1 enabled ', t.strategy, ' campaign for ', COALESCE(t.product_short_name, t.parent_name, 'Store'),
                  IFNULL(CONCAT(', ', FORMAT('%.2f', l.net_roas), 'x net ROAS.'), '.'))
    ELSE CONCAT('No ', t.strategy, ' campaign for ', COALESCE(t.product_short_name, t.parent_name, 'Store'),
                ' — optional, not flagged as missing.')
  END AS reason
FROM target t
LEFT JOIN live_agg l USING (cell_key)
LEFT JOIN dark_agg d USING (cell_key)
LEFT JOIN floors fl ON fl.strategy_id = t.strategy
LEFT JOIN suppress sp
  ON sp.parent_name IS NOT DISTINCT FROM t.parent_name
 AND sp.asin IS NOT DISTINCT FROM t.asin
 AND sp.strategy = t.strategy
);
