-- =============================================
-- AGGRESSIVE CORRELATION HUNT
-- =============================================
-- This query uses multiple strategies to find strong correlations
-- Tests different thresholds, time windows, and aggregation methods
--
-- Project: onyga-482313
-- Dataset: OI
-- =============================================

-- ==========================================
-- STRATEGY 1: Lower Thresholds - Find More Correlations
-- ==========================================
WITH weekly_term_data AS (
  SELECT 
    COALESCE(org.Reporting_Date, paid.week_end_date) AS week_end_date,
    COALESCE(org.ASIN, paid.asin) AS asin,
    UPPER(TRIM(COALESCE(org.Search_Query, paid.search_term))) AS normalized_search_term,
    SUM(COALESCE(org.ORDERS, 0)) AS organic_orders,
    SUM(COALESCE(paid.orders, 0)) AS paid_orders,
    SUM(COALESCE(org.Impressions, 0)) AS organic_impressions,
    SUM(COALESCE(paid.impressions, 0)) AS paid_impressions
  FROM `onyga-482313.OI.FACT_AMAZON_SEARCH_PERFORMANCE_WEEKLY` org
  FULL OUTER JOIN `onyga-482313.OI.V_AMAZON_ADS_TOP_SEARCH_QUERY_TERMS_WEEKLY` paid
    ON org.Reporting_Date = paid.week_end_date
    AND org.ASIN = paid.asin
    AND UPPER(TRIM(COALESCE(org.Search_Query, ''))) = UPPER(TRIM(COALESCE(paid.search_term, '')))
  WHERE 
    (org.Search_Query IS NOT NULL OR paid.search_term IS NOT NULL)
    AND (org.ASIN IS NOT NULL OR paid.asin IS NOT NULL)
    AND NOT REGEXP_CONTAINS(UPPER(TRIM(COALESCE(org.Search_Query, paid.search_term, ''))), r'^B[0-9A-Z]{9}$')
    AND NOT REGEXP_CONTAINS(UPPER(TRIM(COALESCE(org.Search_Query, paid.search_term, ''))), r'^ASIN')
  GROUP BY 1, 2, 3
),
term_correlations AS (
  SELECT 
    asin,
    normalized_search_term,
    COUNT(*) AS weeks_active,
    SUM(organic_orders) AS total_organic_orders,
    SUM(paid_orders) AS total_paid_orders,
    SUM(organic_impressions) AS total_organic_impressions,
    SUM(paid_impressions) AS total_paid_impressions,
    CORR(CAST(organic_orders AS FLOAT64), CAST(paid_orders AS FLOAT64)) AS correlation_orders,
    CORR(CAST(organic_impressions AS FLOAT64), CAST(paid_impressions AS FLOAT64)) AS correlation_impressions
  FROM weekly_term_data
  GROUP BY 1, 2
  HAVING 
    weeks_active >= 2  -- Lower threshold: 2 weeks instead of 3
    AND (total_paid_orders > 0 OR total_organic_orders > 0)
)
SELECT 
  'STRATEGY 1: Lower Thresholds' AS strategy,
  COUNT(*) AS total_terms,
  COUNT(CASE WHEN ABS(correlation_orders) >= 0.7 THEN 1 END) AS very_strong_count,
  COUNT(CASE WHEN ABS(correlation_orders) >= 0.5 THEN 1 END) AS strong_count,
  COUNT(CASE WHEN ABS(correlation_orders) >= 0.3 THEN 1 END) AS moderate_count,
  MAX(ABS(correlation_orders)) AS max_correlation,
  AVG(ABS(correlation_orders)) AS avg_correlation
FROM term_correlations
WHERE correlation_orders IS NOT NULL;

-- ==========================================
-- STRATEGY 2: ASIN-Level Aggregation (More Data Points)
-- ==========================================
WITH asin_weekly AS (
  SELECT 
    COALESCE(org.Reporting_Date, paid.week_end_date) AS week_end_date,
    COALESCE(org.ASIN, paid.asin) AS asin,
    SUM(COALESCE(org.ORDERS, 0)) AS organic_orders,
    SUM(COALESCE(paid.orders, 0)) AS paid_orders,
    SUM(COALESCE(org.Impressions, 0)) AS organic_impressions,
    SUM(COALESCE(paid.impressions, 0)) AS paid_impressions
  FROM `onyga-482313.OI.FACT_AMAZON_SEARCH_PERFORMANCE_WEEKLY` org
  FULL OUTER JOIN `onyga-482313.OI.V_AMAZON_ADS_TOP_SEARCH_QUERY_TERMS_WEEKLY` paid
    ON org.Reporting_Date = paid.week_end_date
    AND org.ASIN = paid.asin
  WHERE 
    (org.ASIN IS NOT NULL OR paid.asin IS NOT NULL)
    AND (org.Search_Query IS NOT NULL OR paid.search_term IS NOT NULL)
    AND NOT REGEXP_CONTAINS(UPPER(TRIM(COALESCE(org.Search_Query, paid.search_term, ''))), r'^B[0-9A-Z]{9}$')
    AND NOT REGEXP_CONTAINS(UPPER(TRIM(COALESCE(org.Search_Query, paid.search_term, ''))), r'^ASIN')
  GROUP BY 1, 2
),
asin_correlations AS (
  SELECT 
    asin,
    COUNT(*) AS weeks_active,
    SUM(organic_orders) AS total_organic_orders,
    SUM(paid_orders) AS total_paid_orders,
    CORR(CAST(organic_orders AS FLOAT64), CAST(paid_orders AS FLOAT64)) AS correlation_orders
  FROM asin_weekly
  GROUP BY asin
  HAVING weeks_active >= 3 AND (total_paid_orders > 0 OR total_organic_orders > 0)
)
SELECT 
  'STRATEGY 2: ASIN-Level' AS strategy,
  COUNT(*) AS total_asins,
  COUNT(CASE WHEN ABS(correlation_orders) >= 0.7 THEN 1 END) AS very_strong_count,
  COUNT(CASE WHEN ABS(correlation_orders) >= 0.5 THEN 1 END) AS strong_count,
  COUNT(CASE WHEN ABS(correlation_orders) >= 0.3 THEN 1 END) AS moderate_count,
  MAX(ABS(correlation_orders)) AS max_correlation,
  AVG(ABS(correlation_orders)) AS avg_correlation
FROM asin_correlations
WHERE correlation_orders IS NOT NULL;

-- ==========================================
-- STRATEGY 3: High-Volume Terms Only
-- ==========================================
WITH high_volume_terms AS (
  SELECT 
    COALESCE(org.Reporting_Date, paid.week_end_date) AS week_end_date,
    COALESCE(org.ASIN, paid.asin) AS asin,
    UPPER(TRIM(COALESCE(org.Search_Query, paid.search_term))) AS normalized_search_term,
    SUM(COALESCE(org.ORDERS, 0)) AS organic_orders,
    SUM(COALESCE(paid.orders, 0)) AS paid_orders
  FROM `onyga-482313.OI.FACT_AMAZON_SEARCH_PERFORMANCE_WEEKLY` org
  FULL OUTER JOIN `onyga-482313.OI.V_AMAZON_ADS_TOP_SEARCH_QUERY_TERMS_WEEKLY` paid
    ON org.Reporting_Date = paid.week_end_date
    AND org.ASIN = paid.asin
    AND UPPER(TRIM(COALESCE(org.Search_Query, ''))) = UPPER(TRIM(COALESCE(paid.search_term, '')))
  WHERE 
    (org.Search_Query IS NOT NULL OR paid.search_term IS NOT NULL)
    AND (org.ASIN IS NOT NULL OR paid.asin IS NOT NULL)
    AND NOT REGEXP_CONTAINS(UPPER(TRIM(COALESCE(org.Search_Query, paid.search_term, ''))), r'^B[0-9A-Z]{9}$')
    AND NOT REGEXP_CONTAINS(UPPER(TRIM(COALESCE(org.Search_Query, paid.search_term, ''))), r'^ASIN')
  GROUP BY 1, 2, 3
),
term_totals AS (
  SELECT 
    asin,
    normalized_search_term,
    COUNT(*) AS weeks_active,
    SUM(organic_orders) AS total_organic_orders,
    SUM(paid_orders) AS total_paid_orders,
    CORR(CAST(organic_orders AS FLOAT64), CAST(paid_orders AS FLOAT64)) AS correlation_orders
  FROM high_volume_terms
  GROUP BY 1, 2
  HAVING 
    (total_paid_orders >= 3 OR total_organic_orders >= 3)  -- Higher volume threshold
    AND weeks_active >= 2
)
SELECT 
  'STRATEGY 3: High-Volume Terms' AS strategy,
  COUNT(*) AS total_terms,
  COUNT(CASE WHEN ABS(correlation_orders) >= 0.7 THEN 1 END) AS very_strong_count,
  COUNT(CASE WHEN ABS(correlation_orders) >= 0.5 THEN 1 END) AS strong_count,
  COUNT(CASE WHEN ABS(correlation_orders) >= 0.3 THEN 1 END) AS moderate_count,
  MAX(ABS(correlation_orders)) AS max_correlation,
  AVG(ABS(correlation_orders)) AS avg_correlation
FROM term_totals
WHERE correlation_orders IS NOT NULL;

-- ==========================================
-- STRATEGY 4: Recent Data Only (Last 8 Weeks)
-- ==========================================
WITH recent_data AS (
  SELECT 
    COALESCE(org.Reporting_Date, paid.week_end_date) AS week_end_date,
    COALESCE(org.ASIN, paid.asin) AS asin,
    UPPER(TRIM(COALESCE(org.Search_Query, paid.search_term))) AS normalized_search_term,
    SUM(COALESCE(org.ORDERS, 0)) AS organic_orders,
    SUM(COALESCE(paid.orders, 0)) AS paid_orders
  FROM `onyga-482313.OI.FACT_AMAZON_SEARCH_PERFORMANCE_WEEKLY` org
  FULL OUTER JOIN `onyga-482313.OI.V_AMAZON_ADS_TOP_SEARCH_QUERY_TERMS_WEEKLY` paid
    ON org.Reporting_Date = paid.week_end_date
    AND org.ASIN = paid.asin
    AND UPPER(TRIM(COALESCE(org.Search_Query, ''))) = UPPER(TRIM(COALESCE(paid.search_term, '')))
  WHERE 
    COALESCE(org.Reporting_Date, paid.week_end_date) >= DATE_SUB(CURRENT_DATE(), INTERVAL 8 WEEK)
    AND (org.Search_Query IS NOT NULL OR paid.search_term IS NOT NULL)
    AND (org.ASIN IS NOT NULL OR paid.asin IS NOT NULL)
    AND NOT REGEXP_CONTAINS(UPPER(TRIM(COALESCE(org.Search_Query, paid.search_term, ''))), r'^B[0-9A-Z]{9}$')
    AND NOT REGEXP_CONTAINS(UPPER(TRIM(COALESCE(org.Search_Query, paid.search_term, ''))), r'^ASIN')
  GROUP BY 1, 2, 3
),
recent_correlations AS (
  SELECT 
    asin,
    normalized_search_term,
    COUNT(*) AS weeks_active,
    SUM(organic_orders) AS total_organic_orders,
    SUM(paid_orders) AS total_paid_orders,
    CORR(CAST(organic_orders AS FLOAT64), CAST(paid_orders AS FLOAT64)) AS correlation_orders
  FROM recent_data
  GROUP BY 1, 2
  HAVING weeks_active >= 2 AND (total_paid_orders > 0 OR total_organic_orders > 0)
)
SELECT 
  'STRATEGY 4: Recent Data (8 weeks)' AS strategy,
  COUNT(*) AS total_terms,
  COUNT(CASE WHEN ABS(correlation_orders) >= 0.7 THEN 1 END) AS very_strong_count,
  COUNT(CASE WHEN ABS(correlation_orders) >= 0.5 THEN 1 END) AS strong_count,
  COUNT(CASE WHEN ABS(correlation_orders) >= 0.3 THEN 1 END) AS moderate_count,
  MAX(ABS(correlation_orders)) AS max_correlation,
  AVG(ABS(correlation_orders)) AS avg_correlation
FROM recent_correlations
WHERE correlation_orders IS NOT NULL;

-- ==========================================
-- STRATEGY 5: TOP STRONGEST CORRELATIONS FOUND
-- ==========================================
WITH all_term_data AS (
  SELECT 
    COALESCE(org.Reporting_Date, paid.week_end_date) AS week_end_date,
    COALESCE(org.ASIN, paid.asin) AS asin,
    UPPER(TRIM(COALESCE(org.Search_Query, paid.search_term))) AS normalized_search_term,
    SUM(COALESCE(org.ORDERS, 0)) AS organic_orders,
    SUM(COALESCE(paid.orders, 0)) AS paid_orders,
    SUM(COALESCE(org.Impressions, 0)) AS organic_impressions,
    SUM(COALESCE(paid.impressions, 0)) AS paid_impressions
  FROM `onyga-482313.OI.FACT_AMAZON_SEARCH_PERFORMANCE_WEEKLY` org
  FULL OUTER JOIN `onyga-482313.OI.V_AMAZON_ADS_TOP_SEARCH_QUERY_TERMS_WEEKLY` paid
    ON org.Reporting_Date = paid.week_end_date
    AND org.ASIN = paid.asin
    AND UPPER(TRIM(COALESCE(org.Search_Query, ''))) = UPPER(TRIM(COALESCE(paid.search_term, '')))
  WHERE 
    (org.Search_Query IS NOT NULL OR paid.search_term IS NOT NULL)
    AND (org.ASIN IS NOT NULL OR paid.asin IS NOT NULL)
    AND NOT REGEXP_CONTAINS(UPPER(TRIM(COALESCE(org.Search_Query, paid.search_term, ''))), r'^B[0-9A-Z]{9}$')
    AND NOT REGEXP_CONTAINS(UPPER(TRIM(COALESCE(org.Search_Query, paid.search_term, ''))), r'^ASIN')
  GROUP BY 1, 2, 3
),
strong_correlations AS (
  SELECT 
    asin,
    normalized_search_term,
    COUNT(*) AS weeks_active,
    SUM(organic_orders) AS total_organic_orders,
    SUM(paid_orders) AS total_paid_orders,
    SUM(organic_impressions) AS total_organic_impressions,
    SUM(paid_impressions) AS total_paid_impressions,
    CORR(CAST(organic_orders AS FLOAT64), CAST(paid_orders AS FLOAT64)) AS correlation_orders,
    CORR(CAST(organic_impressions AS FLOAT64), CAST(paid_impressions AS FLOAT64)) AS correlation_impressions
  FROM all_term_data
  GROUP BY 1, 2
  HAVING 
    weeks_active >= 2
    AND (total_paid_orders > 0 OR total_organic_orders > 0)
    AND CORR(CAST(organic_orders AS FLOAT64), CAST(paid_orders AS FLOAT64)) IS NOT NULL
)
SELECT 
  asin,
  normalized_search_term AS search_term,
  weeks_active,
  total_organic_orders,
  total_paid_orders,
  total_organic_impressions,
  total_paid_impressions,
  ROUND(correlation_orders, 4) AS correlation_orders,
  ROUND(correlation_impressions, 4) AS correlation_impressions,
  CASE 
    WHEN ABS(correlation_orders) >= 0.7 THEN '🔥 VERY STRONG'
    WHEN ABS(correlation_orders) >= 0.5 THEN '✅ STRONG'
    WHEN ABS(correlation_orders) >= 0.3 THEN '💡 MODERATE'
    ELSE '📊 WEAK'
  END AS strength,
  total_paid_orders - total_organic_orders AS order_gap,
  CASE 
    WHEN correlation_orders >= 0.5 AND total_paid_orders > total_organic_orders 
    THEN 'INVEST IN ORGANIC'
    WHEN correlation_orders >= 0.5 
    THEN 'BOTH WORKING'
    WHEN total_paid_orders > 5 AND total_organic_orders = 0 
    THEN 'SEO OPPORTUNITY'
    ELSE 'MONITOR'
  END AS recommendation
FROM strong_correlations
WHERE ABS(correlation_orders) >= 0.3  -- Show all moderate+ correlations
ORDER BY ABS(correlation_orders) DESC, total_paid_orders DESC
LIMIT 100;
