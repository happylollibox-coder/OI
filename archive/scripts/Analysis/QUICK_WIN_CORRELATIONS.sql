-- =============================================
-- QUICK WIN: Find Strongest Correlations Immediately
-- =============================================
--
-- This query is optimized to quickly find the strongest correlations
-- that provide immediate business value
--
-- Project: onyga-482313
-- Dataset: OI
--
-- =============================================

-- ==========================================
-- TOP 50 STRONGEST CORRELATIONS WITH VALUE
-- ==========================================

WITH weekly_term_data AS (
  SELECT 
    COALESCE(org.Reporting_Date, paid.week_end_date) AS week_end_date,
    COALESCE(org.ASIN, paid.asin) AS asin,
    UPPER(TRIM(COALESCE(org.Search_Query, paid.search_term))) AS normalized_search_term,
    SUM(COALESCE(org.ORDERS, 0)) AS organic_orders,
    SUM(COALESCE(paid.orders, 0)) AS paid_orders,
    SUM(COALESCE(org.Impressions, 0)) AS organic_impressions,
    SUM(COALESCE(paid.impressions, 0)) AS paid_impressions,
    SUM(COALESCE(org.Clicks, 0)) AS organic_clicks,
    SUM(COALESCE(paid.clicks, 0)) AS paid_clicks
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
term_aggregates AS (
  SELECT 
    asin,
    normalized_search_term,
    COUNT(*) AS weeks_active,
    SUM(organic_orders) AS total_organic_orders,
    SUM(paid_orders) AS total_paid_orders,
    SUM(organic_impressions) AS total_organic_impressions,
    SUM(paid_impressions) AS total_paid_impressions,
    SUM(organic_clicks) AS total_organic_clicks,
    SUM(paid_clicks) AS total_paid_clicks,
    -- Calculate correlation
    CORR(CAST(organic_orders AS FLOAT64), CAST(paid_orders AS FLOAT64)) AS correlation_orders,
    CORR(CAST(organic_impressions AS FLOAT64), CAST(paid_impressions AS FLOAT64)) AS correlation_impressions,
    -- Flags
    MAX(CASE WHEN organic_orders > 0 THEN 1 ELSE 0 END) AS has_organic,
    MAX(CASE WHEN paid_orders > 0 THEN 1 ELSE 0 END) AS has_paid
  FROM weekly_term_data
  GROUP BY 1, 2
  HAVING 
    weeks_active >= 3  -- Minimum 3 weeks
    AND (total_paid_orders > 0 OR total_organic_orders > 0)
)
SELECT 
  asin,
  normalized_search_term AS search_term,
  
  -- Correlation metrics (THE KEY METRICS)
  ROUND(correlation_orders, 4) AS correlation_orders,
  ROUND(correlation_impressions, 4) AS correlation_impressions,
  
  -- Performance metrics
  total_organic_orders,
  total_paid_orders,
  total_organic_impressions,
  total_paid_impressions,
  weeks_active,
  
  -- Conversion rates
  ROUND(CASE WHEN total_organic_clicks > 0 THEN total_organic_orders / total_organic_clicks ELSE 0 END, 4) AS organic_cvr,
  ROUND(CASE WHEN total_paid_clicks > 0 THEN total_paid_orders / total_paid_clicks ELSE 0 END, 4) AS paid_cvr,
  
  -- Gaps (opportunity indicators)
  total_paid_orders - total_organic_orders AS order_gap,
  total_paid_impressions - total_organic_impressions AS impression_gap,
  
  -- Strength classification
  CASE 
    WHEN ABS(correlation_orders) >= 0.7 THEN 'VERY STRONG ⭐⭐⭐'
    WHEN ABS(correlation_orders) >= 0.5 THEN 'STRONG ⭐⭐'
    WHEN ABS(correlation_orders) >= 0.3 THEN 'MODERATE ⭐'
    ELSE 'WEAK'
  END AS correlation_strength,
  
  -- Value assessment
  CASE 
    -- Very strong positive correlation with opportunity
    WHEN correlation_orders >= 0.7 
      AND total_paid_orders > 5 
      AND total_organic_orders < total_paid_orders * 0.5 
    THEN '🔥 EXCELLENT - Very Strong Correlation, High Opportunity'
    
    -- Strong positive correlation
    WHEN correlation_orders >= 0.5 
      AND total_paid_orders > 3 
      AND total_organic_orders < total_paid_orders 
    THEN '✅ STRONG - Good Correlation, Clear Opportunity'
    
    -- Strong correlation, both performing
    WHEN correlation_orders >= 0.5 
      AND total_paid_orders > 0 
      AND total_organic_orders > 0 
    THEN '✅ GOOD - Strong Correlation, Both Channels Working'
    
    -- Moderate correlation with high paid performance
    WHEN correlation_orders >= 0.3 
      AND total_paid_orders > 10 
      AND total_organic_orders = 0 
    THEN '💡 OPPORTUNITY - No Organic, Strong Paid Performance'
    
    -- Moderate correlation
    WHEN correlation_orders >= 0.3 
      AND total_paid_orders > 5 
    THEN '💡 MODERATE - Some Correlation, Worth Monitoring'
    
    -- Negative correlation (investigate)
    WHEN correlation_orders < -0.3 
    THEN '⚠️ NEGATIVE - Investigate This'
    
    ELSE '📊 MONITOR'
  END AS value_assessment,
  
  -- Investment priority (0-100+ scale)
  ROUND((
    ABS(correlation_orders) * 100 * 0.4 +  -- Correlation strength (most important)
    GREATEST(0, total_paid_orders - total_organic_orders) * 0.3 +  -- Opportunity gap
    LEAST(total_paid_orders, 20) * 0.2 +  -- Paid performance (capped at 20)
    LEAST(weeks_active, 10) * 0.1  -- Consistency (capped at 10)
  ), 2) AS investment_priority_score,
  
  -- Quick action recommendation
  CASE 
    WHEN correlation_orders >= 0.5 AND total_paid_orders > total_organic_orders * 2 
    THEN 'INVEST IN ORGANIC - Strong correlation, paid leading'
    WHEN correlation_orders >= 0.5 AND total_organic_orders > total_paid_orders * 2 
    THEN 'REDUCE PAID - Organic performing better'
    WHEN correlation_orders >= 0.3 AND total_paid_orders > 5 AND total_organic_orders = 0 
    THEN 'TARGET FOR SEO - No organic presence, strong paid'
    WHEN correlation_orders >= 0.5 
    THEN 'MAINTAIN STRATEGY - Both channels working well'
    WHEN correlation_orders < -0.3 
    THEN 'INVESTIGATE - Negative correlation detected'
    ELSE 'MONITOR'
  END AS recommendation
  
FROM term_aggregates
WHERE 
  -- Focus on meaningful correlations or high-value opportunities
  (
    ABS(correlation_orders) >= 0.3  -- At least moderate correlation
    OR (total_paid_orders > 10 AND total_organic_orders = 0)  -- High-value opportunity
  )
  AND total_paid_orders > 0  -- Must have paid activity
ORDER BY 
  -- Prioritize by correlation strength and value
  CASE 
    WHEN ABS(correlation_orders) >= 0.7 THEN 0  -- Very strong first
    WHEN ABS(correlation_orders) >= 0.5 THEN 1  -- Strong second
    WHEN ABS(correlation_orders) >= 0.3 THEN 2  -- Moderate third
    ELSE 3
  END,
  investment_priority_score DESC
LIMIT 50;
