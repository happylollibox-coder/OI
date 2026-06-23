-- =============================================
-- V_PEAK_KEYWORD_RECS — Peak keyword recommendations (Phase 1: analysis)
-- =============================================
--
-- Two sources, unioned, same output shape (source column distinguishes them):
--   LY_PEAK  — families with a proven peak (V_PEAK_RELEVANCE): recs from LAST YEAR's
--              peak demand × profitability (V_SQP_ADS_BY_TERM over the LY peak window).
--   RESEARCH — active families WITHOUT a trustworthy LY peak (e.g. Bottle/Bunny/LolliME,
--              launched too recently): forward recs from V_RESEARCH_RANKED — high research
--              fit (rank>75) + current market demand. (Segments must be correct — see
--              fact_oi_family_product_identities; Bottle→Social Game, Bunny→Keychain fixed.)
--
-- Buckets (match_bucket): INCREASE (advertised → raise bids) / EXACT (new 1-2w) /
--   PHRASE (new >=3w) / BROAD (new short+high-vol) / BRAND (own-brand). New buckets gated
--   to rank>75 (recommendation=ADD). is_trending = recent-4w market vol >= +20% vs prior-4w.
--
-- Ranking: profit-weighted demand. Grain: (holiday_name, parent_name, search_term).
-- Consumer: PeakKeywordRecs cube → Peak page card. Phase 2: BLITZ coacher actions.
-- =============================================

CREATE OR REPLACE VIEW `onyga-482313.OI.V_PEAK_KEYWORD_RECS` AS

WITH
relevant AS (
  SELECT DISTINCT holiday_name, family AS parent_name
  FROM `onyga-482313.OI.V_PEAK_RELEVANCE`
  WHERE is_relevant_peak = TRUE
),

ly_window AS (
  SELECT h.holiday_name, h_ly.peak_start AS ly_peak_start, h_ly.holiday_date AS ly_peak_end
  FROM `onyga-482313.OI.DIM_US_HOLIDAYS` h
  JOIN `onyga-482313.OI.DIM_US_HOLIDAYS` h_ly
    ON h_ly.holiday_name = h.holiday_name
   AND EXTRACT(YEAR FROM h_ly.holiday_date) = EXTRACT(YEAR FROM h.holiday_date) - 1
  WHERE h.category IN ('gift_season', 'prime_event')
    AND h.holiday_date >= CURRENT_DATE('America/New_York')
),

-- Recent ad presence (last 35d) → EXISTING vs NEW (shared by both sources)
current_ads AS (
  SELECT parent_name, search_term, SUM(ad_impressions) AS recent_ad_impr
  FROM `onyga-482313.OI.V_SQP_ADS_BY_TERM`
  WHERE week_start >= DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL 35 DAY)
  GROUP BY 1, 2
),

-- Trend: recent 4 weeks vs the prior 4 weeks of market volume (shared by both sources)
trend AS (
  SELECT parent_name, search_term,
    SUM(IF(week_start >= DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL 4 WEEK), amazon_impressions, 0)) AS vol_recent,
    SUM(IF(week_start <  DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL 4 WEEK)
       AND week_start >= DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL 8 WEEK), amazon_impressions, 0)) AS vol_prior
  FROM `onyga-482313.OI.V_SQP_ADS_BY_TERM`
  WHERE week_start >= DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL 8 WEEK)
  GROUP BY 1, 2
),

-- ═══ SOURCE 1: LY_PEAK — last year's peak demand for LY-relevant families ═══
ly_demand AS (
  SELECT
    r.holiday_name, t.parent_name, t.search_term,
    SUM(t.orders)             AS ly_peak_orders,
    SUM(t.amazon_impressions) AS amazon_volume,
    SUM(t.amazon_orders)      AS amazon_sales,
    SUM(t.ad_spend)           AS ly_ad_spend,
    SAFE_DIVIDE(SUM(t.ad_gross_profit), NULLIF(SUM(t.ad_spend), 0)) AS net_roas
  FROM `onyga-482313.OI.V_SQP_ADS_BY_TERM` t
  JOIN relevant r  ON r.parent_name = t.parent_name
  JOIN ly_window w ON w.holiday_name = r.holiday_name
  WHERE t.week_start BETWEEN DATE_SUB(w.ly_peak_start, INTERVAL 6 DAY) AND w.ly_peak_end
  GROUP BY 1, 2, 3
),
ly_src AS (
  SELECT 'LY_PEAK' AS source, holiday_name, parent_name, search_term,
    ly_peak_orders, amazon_volume, amazon_sales, ly_ad_spend, net_roas,
    CAST(NULL AS FLOAT64) AS research_rank   -- LY ADD gates on proven LY demand, not rank (avoids a 2nd heavy V_RESEARCH_RANKED scan)
  FROM ly_demand d
  WHERE ly_peak_orders > 0 OR amazon_sales > 0
),

-- ═══ SOURCE 2: RESEARCH — forward recs for active families WITHOUT a trustworthy LY peak ═══
-- Top candidates per family computed ONCE (not per holiday) to avoid a cartesian blow-up.
forward_candidates AS (
  SELECT rr.parent_name, rr.query_text AS search_term,
    rr.weekly_market_impressions AS amazon_volume,
    rr.weekly_market_purchases   AS amazon_sales,
    rr.roas_30d AS net_roas,
    rr.rank AS research_rank
  FROM `onyga-482313.OI.V_RESEARCH_RANKED` rr
  WHERE rr.rank > 75 AND rr.weekly_market_purchases > 0 AND rr.query_text != 'OTHER'
    AND rr.parent_name IN (
      SELECT DISTINCT parent_name FROM `onyga-482313.OI.DIM_PRODUCT`
      WHERE is_active = true AND parent_name IS NOT NULL AND parent_name != 'UNKNOWN'
    )
  QUALIFY ROW_NUMBER() OVER (PARTITION BY rr.parent_name ORDER BY rr.weekly_market_purchases DESC) <= 50
),
-- Forward recs only for (holiday, family) pairs where the family is NOT LY-relevant for
-- that holiday (relevant pairs use the LY source instead).
forward_src AS (
  SELECT 'RESEARCH' AS source, lw.holiday_name, fc.parent_name, fc.search_term,
    0 AS ly_peak_orders, fc.amazon_volume, fc.amazon_sales,
    CAST(NULL AS FLOAT64) AS ly_ad_spend, fc.net_roas, fc.research_rank
  FROM forward_candidates fc
  CROSS JOIN (SELECT DISTINCT holiday_name FROM ly_window) lw
  WHERE NOT EXISTS (
    SELECT 1 FROM relevant r
    WHERE r.holiday_name = lw.holiday_name AND LOWER(r.parent_name) = LOWER(fc.parent_name)
  )
),

combined AS (
  SELECT * FROM ly_src
  UNION ALL
  SELECT * FROM forward_src
),

scored AS (
  SELECT
    c.source, c.holiday_name, c.parent_name, c.search_term,
    c.ly_peak_orders, c.amazon_volume, c.amazon_sales,
    ROUND(c.net_roas, 2) AS ly_net_roas,
    ROUND(c.ly_ad_spend, 2) AS ly_ad_spend,
    ROUND(c.research_rank, 0) AS research_rank,
    (COALESCE(ca.recent_ad_impr, 0) > 0) AS is_currently_advertised,
    REGEXP_CONTAINS(LOWER(c.search_term), r'lolli|happy\s*lolli') AS is_own_brand,
    ARRAY_LENGTH(SPLIT(TRIM(c.search_term), ' ')) AS word_count,
    (COALESCE(tr.vol_recent, 0) >= COALESCE(tr.vol_prior, 0) * 1.2 AND COALESCE(tr.vol_recent, 0) > 200) AS is_trending,
    CASE WHEN COALESCE(ca.recent_ad_impr, 0) > 0 THEN 'EXISTING' ELSE 'NEW' END AS targeting_status,
    CASE
      WHEN COALESCE(ca.recent_ad_impr, 0) > 0 AND COALESCE(c.net_roas, 0) >= 1.0 THEN 'INCREASE'
      WHEN COALESCE(ca.recent_ad_impr, 0) > 0                                     THEN 'INCREASE_CAUTIOUS'
      -- Own-brand terms are DEFENSE-only — never ADD them to a general campaign (brand-negation rule)
      WHEN REGEXP_CONTAINS(LOWER(c.search_term), r'lolli|happy\s*lolli')          THEN 'DEFENSE'
      WHEN c.source = 'RESEARCH' AND COALESCE(c.research_rank, 0) > 75            THEN 'ADD'
      WHEN c.source = 'LY_PEAK'  AND c.amazon_sales >= 100                        THEN 'ADD'
      ELSE 'WATCH'
    END AS recommendation,
    ROUND(
      (LN(1 + c.amazon_sales) * 2 + LN(1 + c.ly_peak_orders) * 3)
      * (0.5 + LEAST(GREATEST(COALESCE(c.net_roas, 0.5), 0), 3))
    , 1) AS priority_score
  FROM combined c
  LEFT JOIN current_ads ca ON ca.parent_name = c.parent_name AND ca.search_term = c.search_term
  LEFT JOIN trend tr       ON tr.parent_name = c.parent_name AND tr.search_term = c.search_term
),

bucketed AS (
  SELECT *,
    CASE
      WHEN is_currently_advertised THEN 'INCREASE'
      WHEN is_own_brand            THEN 'BRAND'
      WHEN amazon_sales >= 1000 AND word_count <= 2 THEN 'BROAD'
      WHEN word_count >= 3         THEN 'PHRASE'
      ELSE 'EXACT'
    END AS match_bucket
  FROM scored
)

SELECT
  source, holiday_name, parent_name, search_term,
  targeting_status, recommendation, match_bucket,
  is_own_brand, is_trending, word_count,
  ly_peak_orders, amazon_volume, amazon_sales,
  ly_net_roas, ly_ad_spend, research_rank,
  is_currently_advertised, priority_score,
  CASE recommendation
    WHEN 'INCREASE'          THEN CONCAT('Advertised + profitable (net ROAS ', CAST(COALESCE(ly_net_roas, 0) AS STRING), ') — raise bid/budget', IF(is_trending, ' · trending up now', ''))
    WHEN 'INCREASE_CAUTIOUS' THEN CONCAT('Advertised but net ROAS ', CAST(COALESCE(ly_net_roas, 0) AS STRING), ' — boost with a bid cap', IF(is_trending, ' · trending up now', ''))
    WHEN 'ADD'               THEN CONCAT(IF(source = 'RESEARCH', 'Not advertised; current market demand (', 'Not advertised; LY-peak demand ('), CAST(amazon_sales AS STRING), ' sales) + fits (rank ', CAST(COALESCE(research_rank, 0) AS STRING), ') — add as ', match_bucket)
    WHEN 'DEFENSE'           THEN CONCAT('Own-brand term (', CAST(amazon_sales AS STRING), ' sales) — keep in a brand-DEFENSE campaign only, do not add to general targeting')
    ELSE                          CONCAT('Not advertised; demand present but fit/rank low (', CAST(COALESCE(research_rank, 0) AS STRING), ') — monitor')
  END AS reason
FROM bucketed
QUALIFY ROW_NUMBER() OVER (PARTITION BY holiday_name, parent_name ORDER BY priority_score DESC) <= 60;
