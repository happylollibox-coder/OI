-- =============================================
-- FIND STRONGEST CORRELATIONS - Actionable Insights
-- =============================================
--
-- This query identifies the strongest correlations that provide business value
-- Focuses on actionable opportunities
--
-- Project: onyga-482313
-- Dataset: OI
--
-- =============================================

-- ==========================================
-- STRONGEST CORRELATIONS BY SEARCH TERM
-- ==========================================

WITH term_correlation AS (
  SELECT 
    COALESCE(org.ASIN, paid.asin) AS asin,
    UPPER(TRIM(COALESCE(org.Search_Query, paid.search_term))) AS normalized_search_term,
    
    -- Aggregate metrics
    SUM(COALESCE(org.ORDERS, 0)) AS total_organic_orders,
    SUM(COALESCE(paid.orders, 0)) AS total_paid_orders,
    SUM(COALESCE(org.Impressions, 0)) AS total_organic_impressions,
    SUM(COALESCE(paid.impressions, 0)) AS total_paid_impressions,
    SUM(COALESCE(org.Clicks, 0)) AS total_organic_clicks,
    SUM(COALESCE(paid.clicks, 0)) AS total_paid_clicks,
    
    -- Weekly data for correlation calculation
    ARRAY_AGG(STRUCT(
      COALESCE(org.Reporting_Date, paid.week_end_date) AS week_date,
      COALESCE(org.ORDERS, 0) AS organic_orders_week,
      COALESCE(paid.orders, 0) AS paid_orders_week
    ) ORDER BY COALESCE(org.Reporting_Date, paid.week_end_date)) AS weekly_data,
    
    COUNT(DISTINCT COALESCE(org.Reporting_Date, paid.week_end_date)) AS weeks_active,
    
    -- Flags
    MAX(CASE WHEN org.Search_Query IS NOT NULL THEN 1 ELSE 0 END) AS has_organic,
    MAX(CASE WHEN paid.search_term IS NOT NULL THEN 1 ELSE 0 END) AS has_paid
    
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
  GROUP BY 1, 2
  HAVING total_organic_impressions > 0 OR total_paid_impressions > 0
),
term_with_correlation AS (
  SELECT 
    *,
    -- Calculate correlation using weekly data
    (SELECT CORR(CAST(w.organic_orders_week AS FLOAT64), CAST(w.paid_orders_week AS FLOAT64))
     FROM UNNEST(weekly_data) w
     WHERE w.organic_orders_week > 0 OR w.paid_orders_week > 0) AS correlation_coefficient,
    
    -- Calculate conversion rates
    CASE 
      WHEN total_organic_clicks > 0 
      THEN total_organic_orders / total_organic_clicks 
      ELSE 0 
    END AS organic_cvr,
    CASE 
      WHEN total_paid_clicks > 0 
      THEN total_paid_orders / total_paid_clicks 
      ELSE 0 
    END AS paid_cvr,
    
    -- Calculate gaps
    total_paid_orders - total_organic_orders AS order_gap,
    total_paid_impressions - total_organic_impressions AS impression_gap
    
  FROM term_correlation
  WHERE weeks_active >= 3  -- Minimum 3 weeks for meaningful correlation
)
SELECT 
  asin,
  normalized_search_term AS search_term,
  
  -- Performance metrics
  total_organic_orders,
  total_paid_orders,
  total_organic_impressions,
  total_paid_impressions,
  
  -- Correlation metrics
  ROUND(correlation_coefficient, 4) AS correlation_coefficient,
  weeks_active,
  has_organic,
  has_paid,
  
  -- Conversion rates
  ROUND(organic_cvr, 4) AS organic_conversion_rate,
  ROUND(paid_cvr, 4) AS paid_conversion_rate,
  
  -- Gaps
  order_gap,
  impression_gap,
  
  -- Strength classification
  CASE 
    WHEN ABS(correlation_coefficient) >= 0.7 THEN 'VERY STRONG'
    WHEN ABS(correlation_coefficient) >= 0.5 THEN 'STRONG'
    WHEN ABS(correlation_coefficient) >= 0.3 THEN 'MODERATE'
    WHEN ABS(correlation_coefficient) >= 0.1 THEN 'WEAK'
    ELSE 'NO CORRELATION'
  END AS correlation_strength,
  
  -- Value indicator
  CASE 
    WHEN correlation_coefficient > 0.5 
      AND total_paid_orders > 0 
      AND total_organic_orders < total_paid_orders * 0.5 
    THEN 'HIGH VALUE - Strong Positive Correlation, Low Organic'
    
    WHEN correlation_coefficient > 0.5 
      AND total_paid_orders > 0 
      AND total_organic_orders > 0 
    THEN 'GOOD CORRELATION - Both Performing'
    
    WHEN correlation_coefficient > 0.3 
      AND total_paid_orders > 5 
      AND total_organic_orders = 0 
    THEN 'OPPORTUNITY - No Organic, Strong Paid'
    
    WHEN correlation_coefficient < -0.3 
    THEN 'NEGATIVE - Investigate'
    
    ELSE 'MONITOR'
  END AS value_category,
  
  -- Investment priority (higher = better)
  (
    ABS(correlation_coefficient) * 100 * 0.4 +  -- Correlation strength
    GREATEST(0, total_paid_orders - total_organic_orders) * 0.3 +  -- Gap size
    total_paid_orders * 0.2 +  -- Paid performance
    weeks_active * 0.1  -- Consistency
  ) AS investment_priority_score
  
FROM term_with_correlation
WHERE 
  -- Focus on meaningful correlations or high-value opportunities
  (ABS(correlation_coefficient) >= 0.3 OR total_paid_orders > 5)
  AND total_paid_orders > 0
ORDER BY 
  -- Prioritize strong correlations with high value
  CASE 
    WHEN ABS(correlation_coefficient) >= 0.5 AND total_paid_orders > total_organic_orders THEN 0
    WHEN ABS(correlation_coefficient) >= 0.3 THEN 1
    WHEN total_paid_orders > 10 AND total_organic_orders = 0 THEN 2
    ELSE 3
  END,
  investment_priority_score DESC
LIMIT 200;
