-- Statistical Correlation Coefficients
-- Calculate Pearson correlation coefficients for matched terms
WITH matched_terms AS (
  SELECT 
    COALESCE(org.ASIN, paid.asin) AS asin,
    UPPER(TRIM(COALESCE(org.Search_Query, paid.search_term))) AS normalized_search_term,
    SUM(COALESCE(org.Impressions, 0)) AS total_organic_impressions,
    SUM(COALESCE(org.ORDERS, 0)) AS total_organic_orders,
    SUM(COALESCE(paid.impressions, 0)) AS total_paid_impressions,
    SUM(COALESCE(paid.orders, 0)) AS total_paid_orders,
    CASE 
      WHEN SUM(COALESCE(org.Clicks, 0)) > 0 
      THEN SUM(COALESCE(org.ORDERS, 0)) / SUM(org.Clicks) 
      ELSE 0 
    END AS organic_cvr,
    CASE 
      WHEN SUM(COALESCE(paid.clicks, 0)) > 0 
      THEN SUM(COALESCE(paid.orders, 0)) / SUM(paid.clicks) 
      ELSE 0 
    END AS paid_cvr
  FROM `onyga-482313.OI.FACT_AMAZON_SEARCH_PERFORMANCE_WEEKLY` org
  INNER JOIN `onyga-482313.OI.V_AMAZON_ADS_TOP_SEARCH_QUERY_TERMS_WEEKLY` paid
    ON org.Reporting_Date = paid.week_end_date
    AND org.ASIN = paid.asin
    AND UPPER(TRIM(org.Search_Query)) = UPPER(TRIM(paid.search_term))
  WHERE 
    org.Search_Query IS NOT NULL
    AND paid.search_term IS NOT NULL
    AND org.ASIN IS NOT NULL
    AND paid.asin IS NOT NULL
    AND NOT REGEXP_CONTAINS(UPPER(TRIM(org.Search_Query)), r'^B[0-9A-Z]{9}$')
    AND NOT REGEXP_CONTAINS(UPPER(TRIM(org.Search_Query)), r'^ASIN')
  GROUP BY 1, 2
  HAVING total_organic_impressions > 0 AND total_paid_impressions > 0
)
SELECT 
  'CORRELATION ANALYSIS RESULTS' AS analysis_type,
  COUNT(*) AS sample_size,
  
  -- Impressions correlation
  CORR(CAST(total_organic_impressions AS FLOAT64), CAST(total_paid_impressions AS FLOAT64)) AS correlation_impressions,
  
  -- Orders correlation
  CORR(CAST(total_organic_orders AS FLOAT64), CAST(total_paid_orders AS FLOAT64)) AS correlation_orders,
  
  -- Conversion rate correlation
  CORR(organic_cvr, paid_cvr) AS correlation_conversion_rate,
  
  -- Descriptive statistics
  AVG(total_organic_impressions) AS avg_organic_impressions,
  AVG(total_paid_impressions) AS avg_paid_impressions,
  AVG(total_organic_orders) AS avg_organic_orders,
  AVG(total_paid_orders) AS avg_paid_orders,
  AVG(organic_cvr) AS avg_organic_cvr,
  AVG(paid_cvr) AS avg_paid_cvr,
  
  -- Standard deviations
  STDDEV(CAST(total_organic_impressions AS FLOAT64)) AS stddev_organic_impressions,
  STDDEV(CAST(total_paid_impressions AS FLOAT64)) AS stddev_paid_impressions,
  STDDEV(CAST(total_organic_orders AS FLOAT64)) AS stddev_organic_orders,
  STDDEV(CAST(total_paid_orders AS FLOAT64)) AS stddev_paid_orders,
  STDDEV(organic_cvr) AS stddev_organic_cvr,
  STDDEV(paid_cvr) AS stddev_paid_cvr
  
FROM matched_terms;
