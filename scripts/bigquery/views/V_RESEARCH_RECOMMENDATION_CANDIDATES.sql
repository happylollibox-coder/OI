-- =============================================
-- V_RESEARCH_RECOMMENDATION_CANDIDATES
-- Per family × term candidates for the 4 recommendation types, filtered to
-- "not advertised" (0 ads clicks in last 7 days for the family). Broad rows are
-- seeds only — SP_REFRESH_RESEARCH_RECOMMENDATIONS computes the co-occurrence
-- cluster + >500-sales filter and Phrase coverage. SOP: architecture/RESEARCH_PAGE.md
-- =============================================
CREATE OR REPLACE VIEW `onyga-482313`.OI.V_RESEARCH_RECOMMENDATION_CANDIDATES AS

WITH advertised_7d AS (
  SELECT DISTINCT p.parent_name, LOWER(a.search_term) AS query_text
  FROM `onyga-482313`.OI.FACT_AMAZON_ADS a
  JOIN `onyga-482313`.OI.DIM_PRODUCT p ON a.ASIN_BY_CAMPAIGN_NAME = p.asin
  WHERE a.date >= DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY)
    AND a.Ads_clicks > 0
),
base AS (
  SELECT r.parent_name, r.query_text, r.rank, r.overall_fit,
         r.weekly_market_impressions,
         r.holiday, r.is_holiday_active,
         ARRAY_LENGTH(SPLIT(TRIM(r.query_text), ' ')) AS word_count,
         -- own brand by the detected brand column OR by the term text (brand
         -- detection misses some of our long listing titles)
         (COALESCE(r.brand, '') = 'Happy Lolli'
          OR LOWER(r.query_text) LIKE '%happy lolli%'
          OR LOWER(r.query_text) LIKE '%happylolli%') AS is_own_brand
  FROM `onyga-482313`.OI.FACT_RESEARCH_RANKED r
  LEFT JOIN advertised_7d ad
    ON ad.parent_name = r.parent_name AND ad.query_text = LOWER(r.query_text)
  WHERE ad.query_text IS NULL              -- not advertised
    AND r.query_text != 'OTHER'
    -- off-season holiday terms are rank 0 / not actionable now
    AND (r.holiday IS NULL OR r.is_holiday_active)
)
-- EXACT: not own brand, rank >= 75
SELECT parent_name, query_text, 'EXACT' AS rec_type, 'EXACT' AS match_type,
       query_text AS keyword, rank, overall_fit,
       CAST(weekly_market_impressions AS INT64) AS market_volume,
       rank AS sort_metric
FROM base
WHERE NOT is_own_brand AND rank >= 75
UNION ALL
-- PHRASE: not own brand, rank >= 75, >= 3 words
SELECT parent_name, query_text, 'PHRASE', 'PHRASE',
       query_text, rank, overall_fit,
       CAST(weekly_market_impressions AS INT64),
       rank
FROM base
WHERE NOT is_own_brand AND rank >= 75 AND word_count >= 3
UNION ALL
-- BROAD seeds: not own brand, fit >= 90 (cluster filter in SP)
SELECT parent_name, query_text, 'BROAD', 'BROAD',
       query_text, rank, overall_fit,
       CAST(weekly_market_impressions AS INT64),
       overall_fit
FROM base
WHERE NOT is_own_brand AND overall_fit >= 90
UNION ALL
-- BRAND defense: own brand (by column or text), any rank/fit; ordered by market volume
SELECT parent_name, query_text, 'BRAND', 'PHRASE',
       query_text, rank, overall_fit,
       CAST(weekly_market_impressions AS INT64),
       CAST(weekly_market_impressions AS FLOAT64)
FROM base
WHERE is_own_brand
