-- =============================================
-- OI Database Project - V_SEARCH_TERM_OPPORTUNITIES View
-- =============================================
--
-- Purpose: Find high-potential search terms not covered by ads or experiments
--          Prioritized by impression volume, conversion potential, and keyword type
-- Source: FACT_AMAZON_SEARCH_PERFORMANCE_WEEKLY (SQP) + FACT_AMAZON_ADS
-- Prefix: search_ (SQP measures) / search_ads_ (SQP ads columns)
-- Dependencies: FACT_AMAZON_SEARCH_PERFORMANCE_WEEKLY, FACT_AMAZON_ADS, DIM_EXPERIMENT
-- Project: onyga-482313
-- Dataset: OI
--
-- =============================================

CREATE OR REPLACE VIEW `onyga-482313.OI.V_SEARCH_TERM_OPPORTUNITIES`
AS
WITH recent_sqp AS (
  -- Last 8 weeks of SQP data
  SELECT
    ASIN,
    Search_Query,
    SUM(COALESCE(Impressions, 0)) as search_total_impressions,
    SUM(COALESCE(Clicks, 0)) as search_total_clicks,
    SUM(COALESCE(ORDERS, 0)) as search_total_orders,
    SUM(COALESCE(ADS_Impressions, 0)) as search_ads_impressions,
    SUM(COALESCE(ADS_Orders, 0)) as search_ads_orders,
    COUNT(DISTINCT Reporting_Date) as weeks_present,
    MAX(Reporting_Date) as last_seen
  FROM `onyga-482313.OI.FACT_AMAZON_SEARCH_PERFORMANCE_WEEKLY`
  WHERE Reporting_Date >= DATE_SUB(CURRENT_DATE(), INTERVAL 56 DAY)
    AND Search_Query IS NOT NULL
    AND Impressions > 0
  GROUP BY 1, 2
),
-- Search terms currently in active experiments
active_experiment_terms AS (
  SELECT DISTINCT LOWER(search_term) as search_term, asin
  FROM `onyga-482313.OI.V_EXPERIMENT_SEARCH_TERMS`
  WHERE experiment_id IN (
    SELECT experiment_id FROM `onyga-482313.OI.DIM_EXPERIMENT` WHERE status = 'ACTIVE'
  )
),
-- Search terms with recent ads activity (from any campaign)
recent_ads_terms AS (
  SELECT DISTINCT
    LOWER(search_term) as search_term,
    advertised_asins as asin
  FROM `onyga-482313.OI.FACT_AMAZON_ADS`
  WHERE date >= DATE_SUB(CURRENT_DATE(), INTERVAL 14 DAY)
    AND search_term IS NOT NULL
)
SELECT
  s.ASIN,
  s.Search_Query,
  s.search_total_impressions,
  s.search_total_clicks,
  s.search_total_orders,
  s.search_ads_impressions,
  s.search_ads_orders,
  s.search_total_orders - s.search_ads_orders as search_organic_units,
  s.weeks_present,
  s.last_seen,

  -- Rates (SEARCH_ source: SQP)
  ROUND(SAFE_DIVIDE(s.search_total_clicks, s.search_total_impressions) * 100, 2) as search_ctr_pct,
  ROUND(SAFE_DIVIDE(s.search_total_orders, NULLIF(s.search_total_clicks, 0)) * 100, 2) as search_conversion_pct,

  -- Keyword categorization
  CASE
    WHEN LOWER(s.Search_Query) LIKE '%happy lolli%'
      OR LOWER(s.Search_Query) LIKE '%lollime%' THEN 'BRANDED'
    WHEN REGEXP_CONTAINS(LOWER(s.Search_Query), r'\d+\s*year\s*old') THEN 'AGE_SPECIFIC'
    WHEN LOWER(s.Search_Query) LIKE '%gift%'
      OR LOWER(s.Search_Query) LIKE '%christmas%'
      OR LOWER(s.Search_Query) LIKE '%birthday%'
      OR LOWER(s.Search_Query) LIKE '%valentine%' THEN 'GIFT_SEASONAL'
    ELSE 'GENERIC'
  END as keyword_category,

  -- Coverage status
  CASE
    WHEN aet.search_term IS NOT NULL THEN 'IN_ACTIVE_EXPERIMENT'
    WHEN rat.search_term IS NOT NULL THEN 'CURRENTLY_ADVERTISED'
    WHEN s.search_ads_impressions > 0 THEN 'PREVIOUSLY_ADVERTISED'
    ELSE 'NO_ADS_COVERAGE'
  END as coverage_status,

  -- Opportunity type
  CASE
    WHEN s.search_total_impressions > 10000 AND s.search_total_orders = 0 THEN 'HIGH_IMP_ZERO_CONVERSION'
    WHEN s.search_total_impressions > 10000 AND SAFE_DIVIDE(s.search_total_orders, NULLIF(s.search_total_clicks, 0)) > 0.02 THEN 'HIGH_IMP_HIGH_CONVERSION'
    WHEN s.search_total_impressions > 5000 AND s.search_ads_impressions = 0 THEN 'ORGANIC_ONLY_HIGH_VOLUME'
    WHEN s.search_total_orders > 2 AND s.search_ads_impressions = 0 THEN 'PROVEN_ORGANIC_NO_ADS'
    ELSE 'LOW_PRIORITY'
  END as opportunity_type,

  -- Priority score (higher = better opportunity)
  ROUND(
    (COALESCE(SAFE_DIVIDE(s.search_total_orders, NULLIF(s.search_total_clicks, 0)), 0) * 1000)  -- conversion weight
    + (LOG(1 + s.search_total_impressions) * 2)  -- volume weight
    + (CASE WHEN s.search_ads_impressions = 0 THEN 20 ELSE 0 END)  -- no ads bonus
    + (CASE WHEN s.search_total_orders > 0 THEN 30 ELSE 0 END)  -- proven converter bonus
  , 1) as priority_score

FROM recent_sqp s
LEFT JOIN active_experiment_terms aet
  ON LOWER(s.Search_Query) = aet.search_term AND s.ASIN = aet.asin
LEFT JOIN recent_ads_terms rat
  ON LOWER(s.Search_Query) = rat.search_term AND s.ASIN = rat.asin
WHERE s.search_total_impressions >= 100  -- minimum threshold
  AND aet.search_term IS NULL  -- exclude active experiments
ORDER BY priority_score DESC;
