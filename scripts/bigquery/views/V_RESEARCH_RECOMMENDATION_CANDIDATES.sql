-- =============================================
-- V_RESEARCH_RECOMMENDATION_CANDIDATES
-- Per family × term candidates for the 4 recommendation types. "Not advertised"
-- is now KEYWORD-based and per match type: a term is excluded from a type only
-- if we already run a keyword of THAT match type on it (targeting text = term,
-- spend in last 7d). A term served only via broad/auto with no dedicated keyword
-- is still recommendable. Broad rows are seeds only — SP_REFRESH_RESEARCH_RECOMMENDATIONS
-- computes the co-occurrence cluster + >500-sales filter and Phrase coverage.
-- SOP: architecture/RESEARCH_PAGE.md
-- =============================================
CREATE OR REPLACE VIEW `onyga-482313`.OI.V_RESEARCH_RECOMMENDATION_CANDIDATES AS

WITH base AS (
  SELECT r.parent_name, r.query_text, r.rank, r.overall_fit,
         r.weekly_market_impressions,
         r.holiday, r.is_holiday_active,
         ARRAY_LENGTH(SPLIT(TRIM(r.query_text), ' ')) AS word_count,
         -- per-match-type keyword spend in last 7d (0 = we don't run that keyword)
         COALESCE(r.exact_kw_cost_7d, 0)  AS exact_kw_cost_7d,
         COALESCE(r.phrase_kw_cost_7d, 0) AS phrase_kw_cost_7d,
         COALESCE(r.broad_kw_cost_7d, 0)  AS broad_kw_cost_7d,
         -- real market demand: terms with no market purchases over 104w are
         -- phantoms whose rank is inflated purely by seg_fit (purchase_rank NULL
         -- → rank collapses to overall_fit). Recommendations must be searchable.
         COALESCE(t.market_purchases, 0) AS market_purchases,
         -- own brand by the detected brand column OR by the term text (brand
         -- detection misses some of our long listing titles)
         (COALESCE(r.brand, '') = 'Happy Lolli'
          OR LOWER(r.query_text) LIKE '%happy lolli%'
          OR LOWER(r.query_text) LIKE '%happylolli%') AS is_own_brand
  FROM `onyga-482313`.OI.FACT_RESEARCH_RANKED r
  LEFT JOIN `onyga-482313`.OI.FACT_RESEARCH_TERMS t
    ON LOWER(t.query_text) = LOWER(r.query_text)
  WHERE r.query_text != 'OTHER'
    -- off-season holiday terms are rank 0 / not actionable now
    AND (r.holiday IS NULL OR r.is_holiday_active)
)
-- EXACT: not own brand, real demand, rank >= 75, no EXACT keyword running
SELECT parent_name, query_text, 'EXACT' AS rec_type, 'EXACT' AS match_type,
       query_text AS keyword, rank, overall_fit,
       CAST(weekly_market_impressions AS INT64) AS market_volume,
       rank AS sort_metric
FROM base
WHERE NOT is_own_brand AND market_purchases > 0 AND rank >= 75
  AND exact_kw_cost_7d = 0
UNION ALL
-- PHRASE: not own brand, real demand, rank >= 75, >= 3 words, no PHRASE keyword running
SELECT parent_name, query_text, 'PHRASE', 'PHRASE',
       query_text, rank, overall_fit,
       CAST(weekly_market_impressions AS INT64),
       rank
FROM base
WHERE NOT is_own_brand AND market_purchases > 0 AND rank >= 75 AND word_count >= 3
  AND phrase_kw_cost_7d = 0
UNION ALL
-- BROAD seeds: gated like PHRASE — real market demand + rank >= 75 (NOT fit-only), no BROAD
-- keyword running. (Ori 2026-06-13: "broad similar to phrase". The old fit>=90-only bar
-- produced ~39k seeds, 98% with zero market demand — phantom high-seg-fit terms.) word_count>=3
-- is intentionally OMITTED here (unlike phrase): broad is a discovery match and benefits from
-- short 1-2 word seeds, which then expand into an ASIN co-occurrence cluster in the SP.
SELECT parent_name, query_text, 'BROAD', 'BROAD',
       query_text, rank, overall_fit,
       CAST(weekly_market_impressions AS INT64),
       rank
FROM base
WHERE NOT is_own_brand AND market_purchases > 0 AND rank >= 75
  AND broad_kw_cost_7d = 0
UNION ALL
-- BRAND defense: own brand, real demand, FIT >= 75 (relevance — brand terms have
-- low market volume so rank under-scores them); gate on EXACT keyword spend (per Ori)
SELECT parent_name, query_text, 'BRAND', 'PHRASE',
       query_text, rank, overall_fit,
       CAST(weekly_market_impressions AS INT64),
       CAST(weekly_market_impressions AS FLOAT64)
FROM base
WHERE is_own_brand AND market_purchases > 0 AND overall_fit >= 75
  AND exact_kw_cost_7d = 0
