-- =============================================
-- DEEP CORRELATION ANALYSIS: Finding Solid Correlations
-- =============================================
--
-- This analysis digs deeper to find the strongest correlations between
-- paid and organic performance that can drive business value
--
-- Project: onyga-482313
-- Dataset: OI
--
-- =============================================

-- ==========================================
-- ANALYSIS 1: Time-Lagged Correlation
-- ==========================================
-- Does paid investment in week N lead to organic growth in week N+1, N+2, etc.?

WITH weekly_paid AS (
  SELECT 
    paid.week_end_date,
    paid.asin,
    UPPER(TRIM(paid.search_term)) AS normalized_search_term,
    SUM(paid.impressions) AS paid_impressions,
    SUM(paid.clicks) AS paid_clicks,
    SUM(paid.orders) AS paid_orders,
    SUM(paid.units) AS paid_units
  FROM `onyga-482313.OI.V_AMAZON_ADS_TOP_SEARCH_QUERY_TERMS_WEEKLY` paid
  WHERE paid.search_term IS NOT NULL
    AND paid.asin IS NOT NULL
    AND NOT REGEXP_CONTAINS(UPPER(TRIM(paid.search_term)), r'^B[0-9A-Z]{9}$')
    AND NOT REGEXP_CONTAINS(UPPER(TRIM(paid.search_term)), r'^ASIN')
  GROUP BY 1, 2, 3
),
weekly_organic AS (
  SELECT 
    org.Reporting_Date AS week_end_date,
    org.ASIN AS asin,
    UPPER(TRIM(org.Search_Query)) AS normalized_search_term,
    SUM(org.Impressions) AS organic_impressions,
    SUM(org.Clicks) AS organic_clicks,
    SUM(org.ORDERS) AS organic_orders
  FROM `onyga-482313.OI.FACT_AMAZON_SEARCH_PERFORMANCE_WEEKLY` org
  WHERE org.Search_Query IS NOT NULL
    AND org.ASIN IS NOT NULL
    AND NOT REGEXP_CONTAINS(UPPER(TRIM(org.Search_Query)), r'^B[0-9A-Z]{9}$')
    AND NOT REGEXP_CONTAINS(UPPER(TRIM(org.Search_Query)), r'^ASIN')
  GROUP BY 1, 2, 3
),
lagged_correlation AS (
  SELECT 
    paid.week_end_date AS paid_week,
    DATE_ADD(paid.week_end_date, INTERVAL 1 WEEK) AS organic_week,
    paid.asin,
    paid.normalized_search_term,
    paid.paid_orders,
    paid.paid_impressions,
    org.organic_orders,
    org.organic_impressions,
    -- Calculate if paid investment led to organic growth
    CASE 
      WHEN org.organic_orders > 0 AND paid.paid_orders > 0 THEN 1
      ELSE 0
    END AS has_lagged_growth
  FROM weekly_paid paid
  LEFT JOIN weekly_organic org
    ON DATE_ADD(paid.week_end_date, INTERVAL 1 WEEK) = org.week_end_date
    AND paid.asin = org.asin
    AND paid.normalized_search_term = org.normalized_search_term
  WHERE paid.paid_orders > 0
)
SELECT 
  'LAGGED CORRELATION (1 Week Lag)' AS analysis_type,
  COUNT(*) AS total_paid_weeks,
  SUM(has_lagged_growth) AS weeks_with_organic_growth,
  ROUND(SUM(has_lagged_growth) / COUNT(*) * 100, 2) AS pct_with_growth,
  AVG(paid_orders) AS avg_paid_orders_when_invested,
  AVG(CASE WHEN has_lagged_growth = 1 THEN organic_orders ELSE 0 END) AS avg_organic_orders_after_investment,
  -- Correlation: paid orders vs next week organic orders
  CORR(CAST(paid_orders AS FLOAT64), CAST(organic_orders AS FLOAT64)) AS lagged_correlation_coefficient
FROM lagged_correlation
WHERE organic_orders IS NOT NULL;

-- ==========================================
-- ANALYSIS 2: Cumulative Investment Effect
-- ==========================================
-- Does cumulative paid investment over multiple weeks correlate with organic growth?

WITH weekly_metrics AS (
  SELECT 
    COALESCE(paid.week_end_date, org.Reporting_Date) AS week_end_date,
    COALESCE(paid.asin, org.ASIN) AS asin,
    UPPER(TRIM(COALESCE(paid.search_term, org.Search_Query))) AS normalized_search_term,
    SUM(COALESCE(paid.orders, 0)) AS paid_orders,
    SUM(COALESCE(org.ORDERS, 0)) AS organic_orders,
    SUM(COALESCE(paid.impressions, 0)) AS paid_impressions,
    SUM(COALESCE(org.Impressions, 0)) AS organic_impressions
  FROM `onyga-482313.OI.V_AMAZON_ADS_TOP_SEARCH_QUERY_TERMS_WEEKLY` paid
  FULL OUTER JOIN `onyga-482313.OI.FACT_AMAZON_SEARCH_PERFORMANCE_WEEKLY` org
    ON paid.week_end_date = org.Reporting_Date
    AND paid.asin = org.ASIN
    AND UPPER(TRIM(COALESCE(paid.search_term, ''))) = UPPER(TRIM(COALESCE(org.Search_Query, '')))
  WHERE 
    (paid.search_term IS NOT NULL OR org.Search_Query IS NOT NULL)
    AND (paid.asin IS NOT NULL OR org.ASIN IS NOT NULL)
    AND NOT REGEXP_CONTAINS(UPPER(TRIM(COALESCE(paid.search_term, org.Search_Query, ''))), r'^B[0-9A-Z]{9}$')
    AND NOT REGEXP_CONTAINS(UPPER(TRIM(COALESCE(paid.search_term, org.Search_Query, ''))), r'^ASIN')
  GROUP BY 1, 2, 3
),
cumulative_metrics AS (
  SELECT 
    week_end_date,
    asin,
    normalized_search_term,
    paid_orders,
    organic_orders,
    paid_impressions,
    organic_impressions,
    -- Calculate cumulative paid investment over last 4 weeks
    SUM(paid_orders) OVER (
      PARTITION BY asin, normalized_search_term 
      ORDER BY week_end_date 
      ROWS BETWEEN 3 PRECEDING AND CURRENT ROW
    ) AS cumulative_paid_orders_4wk,
    SUM(paid_impressions) OVER (
      PARTITION BY asin, normalized_search_term 
      ORDER BY week_end_date 
      ROWS BETWEEN 3 PRECEDING AND CURRENT ROW
    ) AS cumulative_paid_impressions_4wk
  FROM weekly_metrics
  WHERE paid_orders > 0 OR organic_orders > 0
)
SELECT 
  'CUMULATIVE INVESTMENT CORRELATION' AS analysis_type,
  COUNT(*) AS sample_size,
  CORR(CAST(cumulative_paid_orders_4wk AS FLOAT64), CAST(organic_orders AS FLOAT64)) AS correlation_cumulative_orders,
  CORR(CAST(cumulative_paid_impressions_4wk AS FLOAT64), CAST(organic_impressions AS FLOAT64)) AS correlation_cumulative_impressions,
  AVG(cumulative_paid_orders_4wk) AS avg_cumulative_paid_orders,
  AVG(organic_orders) AS avg_organic_orders,
  -- Calculate ratio: organic orders per cumulative paid order
  CASE 
    WHEN SUM(cumulative_paid_orders_4wk) > 0 
    THEN SUM(organic_orders) / SUM(cumulative_paid_orders_4wk)
    ELSE 0
  END AS organic_to_paid_ratio
FROM cumulative_metrics
WHERE cumulative_paid_orders_4wk > 0;

-- ==========================================
-- ANALYSIS 3: High-Performance Term Correlation
-- ==========================================
-- Focus on search terms that perform well in paid - do they correlate with organic?

WITH high_performance_paid AS (
  SELECT 
    paid.asin,
    UPPER(TRIM(paid.search_term)) AS normalized_search_term,
    SUM(paid.orders) AS total_paid_orders,
    SUM(paid.impressions) AS total_paid_impressions,
    SUM(paid.clicks) AS total_paid_clicks,
    CASE 
      WHEN SUM(paid.clicks) > 0 
      THEN SUM(paid.orders) / SUM(paid.clicks) 
      ELSE 0 
    END AS paid_conversion_rate,
    COUNT(DISTINCT paid.week_end_date) AS weeks_active
  FROM `onyga-482313.OI.V_AMAZON_ADS_TOP_SEARCH_QUERY_TERMS_WEEKLY` paid
  WHERE paid.search_term IS NOT NULL
    AND paid.asin IS NOT NULL
    AND NOT REGEXP_CONTAINS(UPPER(TRIM(paid.search_term)), r'^B[0-9A-Z]{9}$')
    AND NOT REGEXP_CONTAINS(UPPER(TRIM(paid.search_term)), r'^ASIN')
  GROUP BY 1, 2
  HAVING SUM(paid.orders) >= 5  -- Minimum threshold for "high performance"
),
organic_for_high_performance AS (
  SELECT 
    org.ASIN AS asin,
    UPPER(TRIM(org.Search_Query)) AS normalized_search_term,
    SUM(org.ORDERS) AS total_organic_orders,
    SUM(org.Impressions) AS total_organic_impressions,
    SUM(org.Clicks) AS total_organic_clicks,
    CASE 
      WHEN SUM(org.Clicks) > 0 
      THEN SUM(org.ORDERS) / SUM(org.Clicks) 
      ELSE 0 
    END AS organic_conversion_rate
  FROM `onyga-482313.OI.FACT_AMAZON_SEARCH_PERFORMANCE_WEEKLY` org
  WHERE org.Search_Query IS NOT NULL
    AND org.ASIN IS NOT NULL
    AND NOT REGEXP_CONTAINS(UPPER(TRIM(org.Search_Query)), r'^B[0-9A-Z]{9}$')
    AND NOT REGEXP_CONTAINS(UPPER(TRIM(org.Search_Query)), r'^ASIN')
  GROUP BY 1, 2
)
SELECT 
  'HIGH PERFORMANCE TERM CORRELATION' AS analysis_type,
  COUNT(*) AS high_performance_terms,
  SUM(CASE WHEN org.total_organic_orders > 0 THEN 1 ELSE 0 END) AS terms_with_organic_presence,
  ROUND(SUM(CASE WHEN org.total_organic_orders > 0 THEN 1 ELSE 0 END) / COUNT(*) * 100, 2) AS pct_with_organic,
  
  -- Correlation metrics
  CORR(CAST(paid.total_paid_orders AS FLOAT64), CAST(COALESCE(org.total_organic_orders, 0) AS FLOAT64)) AS correlation_orders,
  CORR(paid.paid_conversion_rate, COALESCE(org.organic_conversion_rate, 0)) AS correlation_conversion_rate,
  
  -- Performance metrics
  AVG(paid.total_paid_orders) AS avg_paid_orders,
  AVG(COALESCE(org.total_organic_orders, 0)) AS avg_organic_orders,
  AVG(paid.paid_conversion_rate) AS avg_paid_cvr,
  AVG(COALESCE(org.organic_conversion_rate, 0)) AS avg_organic_cvr,
  
  -- Opportunity metrics
  SUM(paid.total_paid_orders) AS total_paid_orders_all_terms,
  SUM(COALESCE(org.total_organic_orders, 0)) AS total_organic_orders_all_terms,
  SUM(paid.total_paid_orders) - SUM(COALESCE(org.total_organic_orders, 0)) AS total_order_gap,
  
  -- Terms with strong correlation (both performing)
  COUNT(CASE 
    WHEN org.total_organic_orders > 0 
      AND paid.total_paid_orders > org.total_organic_orders * 1.5 
    THEN 1 
  END) AS terms_paid_dominant,
  COUNT(CASE 
    WHEN org.total_organic_orders > 0 
      AND org.total_organic_orders > paid.total_paid_orders * 1.5 
    THEN 1 
  END) AS terms_organic_dominant,
  COUNT(CASE 
    WHEN org.total_organic_orders = 0 
      AND paid.total_paid_orders > 0 
    THEN 1 
  END) AS terms_no_organic_opportunity
  
FROM high_performance_paid paid
LEFT JOIN organic_for_high_performance org
  ON paid.asin = org.asin
  AND paid.normalized_search_term = org.normalized_search_term;

-- ==========================================
-- ANALYSIS 4: ASIN-Level Strong Correlation
-- ==========================================
-- Find ASINs where paid and organic show strong correlation

WITH asin_weekly AS (
  SELECT 
    COALESCE(paid.week_end_date, org.Reporting_Date) AS week_end_date,
    COALESCE(paid.asin, org.ASIN) AS asin,
    SUM(COALESCE(paid.orders, 0)) AS paid_orders,
    SUM(COALESCE(org.ORDERS, 0)) AS organic_orders,
    SUM(COALESCE(paid.impressions, 0)) AS paid_impressions,
    SUM(COALESCE(org.Impressions, 0)) AS organic_impressions
  FROM `onyga-482313.OI.V_AMAZON_ADS_TOP_SEARCH_QUERY_TERMS_WEEKLY` paid
  FULL OUTER JOIN `onyga-482313.OI.FACT_AMAZON_SEARCH_PERFORMANCE_WEEKLY` org
    ON paid.week_end_date = org.Reporting_Date
    AND paid.asin = org.ASIN
  WHERE 
    (paid.asin IS NOT NULL OR org.ASIN IS NOT NULL)
    AND (paid.search_term IS NOT NULL OR org.Search_Query IS NOT NULL)
    AND NOT REGEXP_CONTAINS(UPPER(TRIM(COALESCE(paid.search_term, org.Search_Query, ''))), r'^B[0-9A-Z]{9}$')
    AND NOT REGEXP_CONTAINS(UPPER(TRIM(COALESCE(paid.search_term, org.Search_Query, ''))), r'^ASIN')
  GROUP BY 1, 2
),
asin_correlation AS (
  SELECT 
    asin,
    COUNT(*) AS weeks_with_data,
    SUM(paid_orders) AS total_paid_orders,
    SUM(organic_orders) AS total_organic_orders,
    SUM(paid_impressions) AS total_paid_impressions,
    SUM(organic_impressions) AS total_organic_impressions,
    -- Calculate correlation per ASIN
    CORR(CAST(paid_orders AS FLOAT64), CAST(organic_orders AS FLOAT64)) AS asin_correlation_orders,
    CORR(CAST(paid_impressions AS FLOAT64), CAST(organic_impressions AS FLOAT64)) AS asin_correlation_impressions,
    -- Calculate ratios
    CASE 
      WHEN SUM(paid_orders) > 0 
      THEN SUM(organic_orders) / SUM(paid_orders) 
      ELSE 0 
    END AS organic_to_paid_ratio
  FROM asin_weekly
  WHERE paid_orders > 0 OR organic_orders > 0
  GROUP BY asin
  HAVING COUNT(*) >= 4  -- Minimum 4 weeks of data for correlation
)
SELECT 
  'ASIN-LEVEL STRONG CORRELATIONS' AS analysis_type,
  asin,
  weeks_with_data,
  total_paid_orders,
  total_organic_orders,
  total_paid_impressions,
  total_organic_impressions,
  asin_correlation_orders,
  asin_correlation_impressions,
  organic_to_paid_ratio,
  -- Strength indicator
  CASE 
    WHEN ABS(asin_correlation_orders) >= 0.7 THEN 'VERY STRONG'
    WHEN ABS(asin_correlation_orders) >= 0.5 THEN 'STRONG'
    WHEN ABS(asin_correlation_orders) >= 0.3 THEN 'MODERATE'
    ELSE 'WEAK'
  END AS correlation_strength,
  -- Opportunity indicator
  CASE 
    WHEN asin_correlation_orders > 0.5 AND total_paid_orders > total_organic_orders THEN 'INVEST MORE - Positive Correlation'
    WHEN asin_correlation_orders > 0.5 AND total_organic_orders > total_paid_orders THEN 'ORGANIC LEADING - Reduce Paid'
    WHEN asin_correlation_orders < -0.3 THEN 'NEGATIVE - Investigate'
    ELSE 'MONITOR'
  END AS recommendation
FROM asin_correlation
WHERE ABS(asin_correlation_orders) >= 0.3  -- Focus on meaningful correlations
ORDER BY ABS(asin_correlation_orders) DESC
LIMIT 50;

-- ==========================================
-- ANALYSIS 5: Search Term Velocity Correlation
-- ==========================================
-- Do search terms that grow fast in paid also grow fast in organic?

WITH term_velocity AS (
  SELECT 
    COALESCE(paid.asin, org.ASIN) AS asin,
    UPPER(TRIM(COALESCE(paid.search_term, org.Search_Query))) AS normalized_search_term,
    COALESCE(paid.week_end_date, org.Reporting_Date) AS week_end_date,
    SUM(COALESCE(paid.orders, 0)) AS paid_orders,
    SUM(COALESCE(org.ORDERS, 0)) AS organic_orders
  FROM `onyga-482313.OI.V_AMAZON_ADS_TOP_SEARCH_QUERY_TERMS_WEEKLY` paid
  FULL OUTER JOIN `onyga-482313.OI.FACT_AMAZON_SEARCH_PERFORMANCE_WEEKLY` org
    ON paid.week_end_date = org.Reporting_Date
    AND paid.asin = org.ASIN
    AND UPPER(TRIM(COALESCE(paid.search_term, ''))) = UPPER(TRIM(COALESCE(org.Search_Query, '')))
  WHERE 
    (paid.search_term IS NOT NULL OR org.Search_Query IS NOT NULL)
    AND (paid.asin IS NOT NULL OR org.ASIN IS NOT NULL)
    AND NOT REGEXP_CONTAINS(UPPER(TRIM(COALESCE(paid.search_term, org.Search_Query, ''))), r'^B[0-9A-Z]{9}$')
    AND NOT REGEXP_CONTAINS(UPPER(TRIM(COALESCE(paid.search_term, org.Search_Query, ''))), r'^ASIN')
  GROUP BY 1, 2, 3
),
term_growth AS (
  SELECT 
    asin,
    normalized_search_term,
    week_end_date,
    paid_orders,
    organic_orders,
    -- Calculate week-over-week growth
    LAG(paid_orders) OVER (PARTITION BY asin, normalized_search_term ORDER BY week_end_date) AS prev_paid_orders,
    LAG(organic_orders) OVER (PARTITION BY asin, normalized_search_term ORDER BY week_end_date) AS prev_organic_orders,
    -- Calculate growth rate
    CASE 
      WHEN LAG(paid_orders) OVER (PARTITION BY asin, normalized_search_term ORDER BY week_end_date) > 0
      THEN (paid_orders - LAG(paid_orders) OVER (PARTITION BY asin, normalized_search_term ORDER BY week_end_date)) 
           / LAG(paid_orders) OVER (PARTITION BY asin, normalized_search_term ORDER BY week_end_date)
      ELSE 0
    END AS paid_growth_rate,
    CASE 
      WHEN LAG(organic_orders) OVER (PARTITION BY asin, normalized_search_term ORDER BY week_end_date) > 0
      THEN (organic_orders - LAG(organic_orders) OVER (PARTITION BY asin, normalized_search_term ORDER BY week_end_date)) 
           / LAG(organic_orders) OVER (PARTITION BY asin, normalized_search_term ORDER BY week_end_date)
      ELSE 0
    END AS organic_growth_rate
  FROM term_velocity
)
SELECT 
  'GROWTH VELOCITY CORRELATION' AS analysis_type,
  COUNT(*) AS weeks_with_growth_data,
  CORR(paid_growth_rate, organic_growth_rate) AS correlation_growth_rates,
  AVG(paid_growth_rate) AS avg_paid_growth_rate,
  AVG(organic_growth_rate) AS avg_organic_growth_rate,
  COUNT(CASE WHEN paid_growth_rate > 0 AND organic_growth_rate > 0 THEN 1 END) AS weeks_both_growing,
  COUNT(CASE WHEN paid_growth_rate > 0 AND organic_growth_rate <= 0 THEN 1 END) AS weeks_paid_growing_organic_not,
  COUNT(CASE WHEN paid_growth_rate <= 0 AND organic_growth_rate > 0 THEN 1 END) AS weeks_organic_growing_paid_not
FROM term_growth
WHERE prev_paid_orders IS NOT NULL 
  AND prev_organic_orders IS NOT NULL
  AND ABS(paid_growth_rate) < 10  -- Filter out extreme outliers
  AND ABS(organic_growth_rate) < 10;
