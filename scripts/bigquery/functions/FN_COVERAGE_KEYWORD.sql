-- FN_COVERAGE_KEYWORD(win_start, win_end, peak_only) — window-parameterized keyword coverage.
--
-- Table-function version of V_COVERAGE_KEYWORD: identical status/orphan/brand logic, but every
-- RUNNING measure (clicks, cost, cpc, units_7d, net_roas, target_cpc, profit_state) is aggregated
-- over the caller-supplied [win_start, win_end] (peak_only=TRUE additionally restricts to
-- gift-season days). Mirrors FN_COVERAGE_CAMPAIGN so the whole cockpit answers to one time filter.
--
-- Grain: one row per (parent_name × match_type × keyword_text).
-- RUNNING keywords come from V_KEYWORD_DAILY over the window; MISSING (recommended-but-not-advertised),
-- relevance and intent routing are NOT windowed — they are research state, not period performance.
--
-- net_roas   := SUM(units_7d) × family_gp / SUM(cost) over the window — the REAL per-keyword ad net
--   ROAS (V_INTENT_KEYWORDS.ads_net_roas is an intent/family aggregate and is kept only for reference).
-- target_cpc := cvr × family_gp / INTENT floor = units_7d × gp / (clicks × floor) — the CPC that lands
--   the keyword on the floor GIVEN THE WINDOW'S conversion rate. NULL under 10 window clicks.
-- net_profit := SUM(net_proxy) = sales_14d − cost: directional only (14d-rolling, no COGS).
CREATE OR REPLACE TABLE FUNCTION `onyga-482313.OI.FN_COVERAGE_KEYWORD`(win_start DATE, win_end DATE, peak_only BOOL) AS (
WITH
-- gift-season days (for peak_only); harmless when peak_only=FALSE.
peak_dates AS (
  SELECT DISTINCT d AS date
  FROM `onyga-482313`.OI.DIM_US_HOLIDAYS h, UNNEST(GENERATE_DATE_ARRAY(h.boost_start, h.cooldown_end)) d
  WHERE h.category = 'gift_season'
),
-- ── RUNNING: live keyword×day rolled to (family, keyword, match) over THE WINDOW ──
running AS (
  SELECT
    parent_name,
    LOWER(keyword_text) AS keyword_text,
    match_type,
    CAST(SUM(clicks) AS INT64) AS clicks,
    SUM(cost) AS cost,
    CAST(SUM(units_7d) AS INT64) AS units_7d,                       -- clean 7d click-attributed
    SUM(net_proxy) AS net_profit,                                   -- see header caveat
    ARRAY_AGG(ad_keyword_status ORDER BY date DESC LIMIT 1)[OFFSET(0)] AS kw_status,
    MAX(date) AS last_seen,
    ARRAY_AGG(DISTINCT campaign_id IGNORE NULLS) AS campaign_ids
  FROM `onyga-482313.OI.V_KEYWORD_DAILY`
  WHERE date BETWEEN win_start AND win_end
    AND (NOT peak_only OR date IN (SELECT date FROM peak_dates))
    AND parent_name IS NOT NULL
    AND keyword_text IS NOT NULL
    AND match_type IS NOT NULL
  GROUP BY parent_name, LOWER(keyword_text), match_type
),
-- ── Family-average gross-profit-per-unit (for real per-keyword net ROAS) ──
fam_gp AS (
  SELECT dp.parent_name,
    AVG(ROUND(lc.price - COALESCE(ch.TOTAL_COST_PER_UNIT, 0), 2)) AS gp
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
  GROUP BY dp.parent_name
),
-- ── MISSING: recommended-but-not-advertised, latest research week only (NOT windowed) ──
missing AS (
  SELECT
    parent_name,
    LOWER(query_text) AS keyword_text,
    match_type,
    MAX(rank) AS rec_rank,               -- best rank across dupes (higher rank = higher priority)
    ANY_VALUE(rec_type) AS rec_type
  FROM `onyga-482313.OI.FACT_RESEARCH_RECOMMENDATIONS`
  WHERE status = 'NEW'
    AND week_start = (SELECT MAX(week_start)
                      FROM `onyga-482313.OI.FACT_RESEARCH_RECOMMENDATIONS`
                      WHERE status = 'NEW')
    AND parent_name IS NOT NULL
    AND query_text IS NOT NULL
    AND match_type IS NOT NULL
  GROUP BY parent_name, LOWER(query_text), match_type
),
-- ── RELEVANCE: one row per (family, term), match-agnostic ──
relevance AS (
  SELECT
    parent_name,
    LOWER(query_text) AS keyword_text,
    CAST(MAX(rank) AS INT64) AS research_rank,
    CAST(MAX(overall_fit) AS FLOAT64) AS overall_fit,
    ANY_VALUE(brand) AS brand_name          -- brand NAME per family×term (NULL = generic)
  FROM `onyga-482313.OI.FACT_RESEARCH_RANKED`
  WHERE parent_name IS NOT NULL AND query_text IS NOT NULL
  GROUP BY parent_name, LOWER(query_text)
),
-- ── INTENT relevance flag + ad return, one row per (family, term) ──
intent_rel AS (
  SELECT
    parent_name,
    LOWER(query_text) AS keyword_text,
    LOGICAL_OR(is_relevant) AS is_relevant,
    MAX(ads_net_roas) AS ads_net_roas
  FROM `onyga-482313.OI.V_INTENT_KEYWORDS`
  WHERE parent_name IS NOT NULL AND query_text IS NOT NULL
  GROUP BY parent_name, LOWER(query_text)
),
-- ── INTENT PROFITABLE_ROAS floor (the ads-net-ROAS target keywords are bid toward) ──
floor AS (
  SELECT MAX(CAST(threshold_value AS FLOAT64)) AS v
  FROM `onyga-482313`.OI.DE_COACH_THRESHOLDS
  WHERE threshold_key = 'PROFITABLE_ROAS' AND strategy_id = 'BROAD_SP'
),
-- ── INTENT routing: specificity-routed intent per (family, term), one row each ──
kw_intent AS (
  SELECT parent_name, LOWER(query_text) AS keyword_text,
         ANY_VALUE(intent_key) AS intent_key, ANY_VALUE(label) AS intent_label
  FROM `onyga-482313.OI.V_INTENT_KEYWORDS`
  WHERE parent_name IS NOT NULL AND query_text IS NOT NULL
  GROUP BY parent_name, LOWER(query_text)
),
-- ── Universe: every (family, match, term) that is running IN-WINDOW OR recommended ──
keys AS (
  SELECT DISTINCT parent_name, match_type, keyword_text
  FROM (
    SELECT parent_name, match_type, keyword_text FROM running
    UNION ALL
    SELECT parent_name, match_type, keyword_text FROM missing
  )
)
SELECT
  k.parent_name,
  k.match_type,
  k.keyword_text,
  (r.keyword_text IS NOT NULL) AS is_running,
  COALESCE(r.kw_status = 'ENABLED', FALSE) AS is_enabled,
  (m.keyword_text IS NOT NULL) AS is_recommended,
  COALESCE(r.clicks, 0) AS clicks,
  r.cost,
  ROUND(SAFE_DIVIDE(r.cost, NULLIF(r.clicks, 0)), 2) AS cpc,
  r.net_profit,
  rel.research_rank,
  rel.overall_fit,
  rel.brand_name AS brand_name,
  -- own-brand: ranked term is our brand, OR it's a BRAND-type recommendation (brand terms → Brand Defense only)
  COALESCE((rel.brand_name = 'Happy Lolli') OR (m.rec_type = 'BRAND'), FALSE) AS is_brand,
  ir.is_relevant,
  ir.ads_net_roas,   -- intent/family-level aggregate (kept for reference; NOT per-keyword)
  -- REAL per-keyword net ROAS over the window = units_7d × family_gp / cost
  ROUND(SAFE_DIVIDE(r.units_7d * fg.gp, NULLIF(r.cost, 0)), 2) AS net_roas,
  -- ── TARGET CPC (window-scoped): the CPC at which this keyword hits the INTENT net-ROAS floor,
  --    given the WINDOW'S conversion rate + family gross profit per unit.
  --      target_cpc = cvr × gp / floor = units_7d × gp / (clicks × floor).
  --    Below current cpc → overbidding (cut the bid); above → room to raise. NULL when the
  --    signal is thin (clicks < 10 in-window). $0 = no conversions in the window (negate/probe).
  CASE
    WHEN COALESCE(r.clicks, 0) < 10 OR fg.gp IS NULL THEN NULL
    ELSE ROUND(SAFE_DIVIDE(r.units_7d * fg.gp, r.clicks * (SELECT v FROM floor)), 2)
  END AS target_cpc,
  ki.intent_key,
  ki.intent_label,
  -- ── PROFIT VERDICT: REAL per-keyword net-ROAS vs INTENT floor (clicks<10 → unknown) ──
  CASE
    WHEN COALESCE(r.clicks, 0) < 10 THEN 'unknown'
    WHEN r.units_7d IS NULL OR r.cost IS NULL OR fg.gp IS NULL THEN 'unknown'
    WHEN SAFE_DIVIDE(r.units_7d * fg.gp, NULLIF(r.cost, 0)) >= (SELECT v FROM floor)
      THEN 'profitable'
    ELSE 'unprofitable'
  END AS profit_state,
  m.rec_type,
  r.last_seen,
  CASE
    WHEN (r.keyword_text IS NOT NULL) AND COALESCE(r.kw_status = 'ENABLED', FALSE)
         AND (ir.is_relevant = FALSE OR rel.research_rank IS NULL) THEN 'orphan'
    WHEN (r.keyword_text IS NOT NULL) AND COALESCE(r.kw_status = 'ENABLED', FALSE) THEN 'running'
    WHEN (r.keyword_text IS NOT NULL) AND NOT COALESCE(r.kw_status = 'ENABLED', FALSE) THEN 'paused'
    WHEN (r.keyword_text IS NULL) AND (m.keyword_text IS NOT NULL) THEN 'missing'
    ELSE 'other'
  END AS status,
  CONCAT('BROAD_SP|', k.parent_name) AS cell_key
FROM keys k
LEFT JOIN running    r  ON r.parent_name = k.parent_name
                       AND r.match_type  = k.match_type
                       AND r.keyword_text = k.keyword_text
LEFT JOIN missing    m  ON m.parent_name = k.parent_name
                       AND m.match_type  = k.match_type
                       AND m.keyword_text = k.keyword_text
LEFT JOIN relevance  rel ON rel.parent_name = k.parent_name
                        AND rel.keyword_text = k.keyword_text
LEFT JOIN intent_rel ir  ON ir.parent_name = k.parent_name
                        AND ir.keyword_text = k.keyword_text
LEFT JOIN kw_intent  ki  ON ki.parent_name = k.parent_name
                        AND ki.keyword_text = k.keyword_text
LEFT JOIN fam_gp     fg  ON fg.parent_name = k.parent_name
);
