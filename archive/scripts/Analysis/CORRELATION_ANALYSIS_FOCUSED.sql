-- =============================================
-- FOCUSED CORRELATION ANALYSIS: Organic vs Paid Search Performance
-- =============================================
--
-- Purpose: Find correlations between FACT_AMAZON_SEARCH_PERFORMANCE_WEEKLY (organic)
--          and V_AMAZON_ADS_TOP_SEARCH_QUERY_TERMS_WEEKLY (paid)
--
-- Key Focus: Correlation between paid and organic performance metrics
--
-- Project: onyga-482313
-- Dataset: OI
--
-- =============================================

-- ==========================================
-- CORRELATION ANALYSIS: Search Term Level
-- ==========================================

-- This query aggregates by search term and ASIN to calculate correlations
WITH term_performance AS (
  SELECT 
    -- Match keys: normalized search terms and ASIN
    COALESCE(org.ASIN, paid.asin) AS asin,
    UPPER(TRIM(COALESCE(org.Search_Query, paid.search_term))) AS normalized_search_term,
    
    -- Organic metrics (aggregated)
    SUM(COALESCE(org.Impressions, 0)) AS total_organic_impressions,
    SUM(COALESCE(org.Clicks, 0)) AS total_organic_clicks,
    SUM(COALESCE(org.ORDERS, 0)) AS total_organic_orders,
    SUM(COALESCE(org.AMAZON_ORDERS, 0)) AS total_organic_amazon_orders,
    AVG(COALESCE(org.Search_Query_Score, 0)) AS avg_organic_search_score,
    
    -- Calculate conversion rates
    CASE 
      WHEN SUM(COALESCE(org.Impressions, 0)) > 0 
      THEN SUM(COALESCE(org.Clicks, 0)) / SUM(org.Impressions) 
      ELSE 0 
    END AS organic_ctr,
    CASE 
      WHEN SUM(COALESCE(org.Clicks, 0)) > 0 
      THEN SUM(COALESCE(org.ORDERS, 0)) / SUM(org.Clicks) 
      ELSE 0 
    END AS organic_conversion_rate,
    
    -- Paid metrics (aggregated)
    SUM(COALESCE(paid.impressions, 0)) AS total_paid_impressions,
    SUM(COALESCE(paid.clicks, 0)) AS total_paid_clicks,
    SUM(COALESCE(paid.orders, 0)) AS total_paid_orders,
    SUM(COALESCE(paid.units, 0)) AS total_paid_units,
    
    -- Calculate paid conversion rates
    CASE 
      WHEN SUM(COALESCE(paid.impressions, 0)) > 0 
      THEN SUM(COALESCE(paid.clicks, 0)) / SUM(paid.impressions) 
      ELSE 0 
    END AS paid_ctr,
    CASE 
      WHEN SUM(COALESCE(paid.clicks, 0)) > 0 
      THEN SUM(COALESCE(paid.orders, 0)) / SUM(paid.clicks) 
      ELSE 0 
    END AS paid_conversion_rate,
    
    -- Count weeks of activity
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
    -- Filter out NULL search terms and ASINs
    (org.Search_Query IS NOT NULL OR paid.search_term IS NOT NULL)
    AND (org.ASIN IS NOT NULL OR paid.asin IS NOT NULL)
    -- Filter out ASIN patterns (product page visits, not search terms)
    AND NOT REGEXP_CONTAINS(UPPER(TRIM(COALESCE(org.Search_Query, paid.search_term, ''))), r'^B[0-9A-Z]{9}$')
    AND NOT REGEXP_CONTAINS(UPPER(TRIM(COALESCE(org.Search_Query, paid.search_term, ''))), r'^ASIN')
  GROUP BY 1, 2
  HAVING total_organic_impressions > 0 OR total_paid_impressions > 0
)
SELECT 
  -- Basic identifiers
  asin,
  normalized_search_term AS search_term,
  
  -- Organic metrics
  total_organic_impressions,
  total_organic_clicks,
  total_organic_orders,
  organic_ctr,
  organic_conversion_rate,
  avg_organic_search_score,
  
  -- Paid metrics
  total_paid_impressions,
  total_paid_clicks,
  total_paid_orders,
  total_paid_units,
  paid_ctr,
  paid_conversion_rate,
  
  -- Correlation indicators
  weeks_active,
  has_organic,
  has_paid,
  
  -- Gap analysis (positive = paid higher, negative = organic higher)
  total_paid_impressions - total_organic_impressions AS impression_gap,
  total_paid_orders - total_organic_orders AS order_gap,
  paid_conversion_rate - organic_conversion_rate AS conversion_rate_gap,
  
  -- Opportunity scoring
  CASE 
    WHEN has_organic = 0 AND has_paid = 1 AND total_paid_orders > 0 THEN 'High Opportunity - No Organic'
    WHEN has_organic = 1 AND has_paid = 1 AND total_paid_orders > total_organic_orders * 2 THEN 'High Opportunity - Paid Dominant'
    WHEN has_organic = 1 AND has_paid = 1 AND organic_conversion_rate > paid_conversion_rate * 1.5 THEN 'Efficiency Opportunity - Organic Better'
    WHEN has_organic = 1 AND has_paid = 1 THEN 'Both Present - Monitor'
    WHEN has_organic = 1 AND has_paid = 0 THEN 'Organic Only'
    ELSE 'Other'
  END AS opportunity_category,
  
  -- Investment priority score (higher = better opportunity)
  (
    total_paid_orders * 0.4 +                                    -- Paid performance
    paid_conversion_rate * 100 * 0.3 +                           -- Paid efficiency
    GREATEST(0, total_paid_orders - total_organic_orders) * 0.2 + -- Gap size
    weeks_active * 0.1                                            -- Consistency
  ) AS investment_priority_score
  
FROM term_performance
ORDER BY 
  -- Prioritize terms with both paid and organic for correlation analysis
  CASE WHEN has_organic = 1 AND has_paid = 1 THEN 0 ELSE 1 END,
  investment_priority_score DESC;

-- ==========================================
-- STATISTICAL CORRELATION COEFFICIENTS
-- ==========================================

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

-- ==========================================
-- ASIN-LEVEL CORRELATION SUMMARY
-- ==========================================

-- Aggregate correlation metrics by ASIN
WITH asin_performance AS (
  SELECT 
    COALESCE(org.ASIN, paid.asin) AS asin,
    
    -- Organic totals
    SUM(COALESCE(org.Impressions, 0)) AS total_organic_impressions,
    SUM(COALESCE(org.Clicks, 0)) AS total_organic_clicks,
    SUM(COALESCE(org.ORDERS, 0)) AS total_organic_orders,
    COUNT(DISTINCT org.Search_Query) AS unique_organic_terms,
    
    -- Paid totals
    SUM(COALESCE(paid.impressions, 0)) AS total_paid_impressions,
    SUM(COALESCE(paid.clicks, 0)) AS total_paid_clicks,
    SUM(COALESCE(paid.orders, 0)) AS total_paid_orders,
    SUM(COALESCE(paid.units, 0)) AS total_paid_units,
    COUNT(DISTINCT paid.search_term) AS unique_paid_terms,
    
    -- Matched terms (appear in both)
    COUNT(DISTINCT CASE 
      WHEN org.Search_Query IS NOT NULL AND paid.search_term IS NOT NULL 
      THEN UPPER(TRIM(COALESCE(org.Search_Query, paid.search_term))) 
    END) AS matched_terms_count
    
  FROM `onyga-482313.OI.FACT_AMAZON_SEARCH_PERFORMANCE_WEEKLY` org
  FULL OUTER JOIN `onyga-482313.OI.V_AMAZON_ADS_TOP_SEARCH_QUERY_TERMS_WEEKLY` paid
    ON org.Reporting_Date = paid.week_end_date
    AND org.ASIN = paid.asin
    AND UPPER(TRIM(COALESCE(org.Search_Query, ''))) = UPPER(TRIM(COALESCE(paid.search_term, '')))
  WHERE 
    (org.ASIN IS NOT NULL OR paid.asin IS NOT NULL)
    AND (org.Search_Query IS NOT NULL OR paid.search_term IS NOT NULL)
    AND NOT REGEXP_CONTAINS(UPPER(TRIM(COALESCE(org.Search_Query, paid.search_term, ''))), r'^B[0-9A-Z]{9}$')
    AND NOT REGEXP_CONTAINS(UPPER(TRIM(COALESCE(org.Search_Query, paid.search_term, ''))), r'^ASIN')
  GROUP BY 1
  HAVING total_organic_impressions > 0 OR total_paid_impressions > 0
)
SELECT 
  asin,
  
  -- Volume metrics
  total_organic_impressions,
  total_paid_impressions,
  total_organic_orders,
  total_paid_orders,
  
  -- Term diversity
  unique_organic_terms,
  unique_paid_terms,
  matched_terms_count,
  ROUND(matched_terms_count / NULLIF(unique_paid_terms, 0) * 100, 2) AS pct_paid_terms_with_organic,
  
  -- Conversion rates
  CASE 
    WHEN total_organic_clicks > 0 
    THEN total_organic_orders / total_organic_clicks 
    ELSE 0 
  END AS organic_conversion_rate,
  CASE 
    WHEN total_paid_clicks > 0 
    THEN total_paid_orders / total_paid_clicks 
    ELSE 0 
  END AS paid_conversion_rate,
  
  -- Correlation indicators
  total_paid_orders - total_organic_orders AS order_gap,
  unique_paid_terms - unique_organic_terms AS term_gap,
  
  -- ASIN-level opportunity score
  (
    total_paid_orders * 0.4 +
    (unique_paid_terms - unique_organic_terms) * 0.3 +
    (CASE WHEN total_paid_clicks > 0 THEN total_paid_orders / total_paid_clicks ELSE 0 END) * 100 * 0.2 +
    matched_terms_count * 0.1
  ) AS asin_opportunity_score
  
FROM asin_performance
WHERE total_paid_orders > 0  -- Focus on ASINs with paid activity
ORDER BY asin_opportunity_score DESC
LIMIT 50;

-- ==========================================
-- CORRELATION BY SEARCH TERM (Top Opportunities)
-- ==========================================

-- Find search terms with strong paid performance but weak/no organic
WITH term_analysis AS (
  SELECT 
    COALESCE(org.ASIN, paid.asin) AS asin,
    UPPER(TRIM(COALESCE(org.Search_Query, paid.search_term))) AS normalized_search_term,
    SUM(COALESCE(org.ORDERS, 0)) AS total_organic_orders,
    SUM(COALESCE(paid.orders, 0)) AS total_paid_orders,
    SUM(COALESCE(paid.units, 0)) AS total_paid_units,
    COUNT(DISTINCT COALESCE(org.Reporting_Date, paid.week_end_date)) AS weeks_active,
    MAX(CASE WHEN org.Search_Query IS NOT NULL THEN 1 ELSE 0 END) AS has_organic
  FROM `onyga-482313.OI.FACT_AMAZON_SEARCH_PERFORMANCE_WEEKLY` org
  FULL OUTER JOIN `onyga-482313.OI.V_AMAZON_ADS_TOP_SEARCH_QUERY_TERMS_WEEKLY` paid
    ON org.Reporting_Date = paid.week_end_date
    AND org.ASIN = paid.asin
    AND UPPER(TRIM(COALESCE(org.Search_Query, ''))) = UPPER(TRIM(COALESCE(paid.search_term, '')))
  WHERE 
    (org.ASIN IS NOT NULL OR paid.asin IS NOT NULL)
    AND (org.Search_Query IS NOT NULL OR paid.search_term IS NOT NULL)
    AND NOT REGEXP_CONTAINS(UPPER(TRIM(COALESCE(org.Search_Query, paid.search_term, ''))), r'^B[0-9A-Z]{9}$')
    AND NOT REGEXP_CONTAINS(UPPER(TRIM(COALESCE(org.Search_Query, paid.search_term, ''))), r'^ASIN')
  GROUP BY 1, 2
  HAVING total_paid_orders > 0  -- Only terms with paid orders
)
SELECT 
  asin,
  normalized_search_term AS search_term,
  total_organic_orders,
  total_paid_orders,
  total_paid_units,
  weeks_active,
  has_organic,
  
  -- Opportunity metrics
  total_paid_orders - total_organic_orders AS order_gap,
  CASE 
    WHEN has_organic = 0 THEN 'No Organic - High Opportunity'
    WHEN total_paid_orders > total_organic_orders * 3 THEN 'Paid 3x Higher - High Opportunity'
    WHEN total_paid_orders > total_organic_orders * 2 THEN 'Paid 2x Higher - Medium Opportunity'
    ELSE 'Monitor'
  END AS opportunity_level,
  
  -- Priority score for investment
  (total_paid_orders * 0.5 + 
   (total_paid_orders - total_organic_orders) * 0.3 + 
   weeks_active * 0.2) AS investment_priority
  
FROM term_analysis
ORDER BY investment_priority DESC
LIMIT 100;
