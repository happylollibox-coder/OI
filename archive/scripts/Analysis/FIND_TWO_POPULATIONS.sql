-- =============================================
-- FIND TWO POPULATIONS: Organic Performers & Paid-Driven Organic
-- =============================================
-- Purpose: 
--   Population 1: ASIN + search terms that sell mostly organically (very few paid clicks)
--   Population 2: ASIN + search terms where paid clicks drive organic orders
--
-- Both show monthly clicks per order (smaller is better)
--
-- Project: onyga-482313
-- Dataset: OI
-- =============================================

-- ==========================================
-- POPULATION 1: Mostly Organic Performers
-- ==========================================
-- Criteria: 
--   - At least 20 orders in last 6 months
--   - Very few paid clicks (mostly organic)
--   - Show monthly clicks per order
-- ==========================================

WITH monthly_data AS (
  SELECT 
    COALESCE(org.Reporting_Date, paid.week_end_date) AS week_end_date,
    COALESCE(org.ASIN, paid.asin) AS asin,
    UPPER(TRIM(COALESCE(org.Search_Query, paid.search_term))) AS normalized_search_term,
    
    -- Extract month and year
    EXTRACT(YEAR FROM COALESCE(org.Reporting_Date, paid.week_end_date)) AS year,
    EXTRACT(MONTH FROM COALESCE(org.Reporting_Date, paid.week_end_date)) AS month,
    FORMAT_DATE('%Y-%m', COALESCE(org.Reporting_Date, paid.week_end_date)) AS year_month,
    
    -- Paid metrics
    SUM(COALESCE(paid.clicks, 0)) AS paid_clicks,
    SUM(COALESCE(paid.orders, 0)) AS paid_orders,
    
    -- Organic metrics
    SUM(COALESCE(org.Clicks, 0)) AS organic_clicks,
    SUM(COALESCE(org.ORDERS, 0)) AS organic_orders,
    
    -- Combined metrics
    SUM(COALESCE(org.ORDERS, 0) + COALESCE(paid.orders, 0)) AS total_orders
    
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
    -- Last 6 months
    AND COALESCE(org.Reporting_Date, paid.week_end_date) >= DATE_SUB(CURRENT_DATE(), INTERVAL 6 MONTH)
  GROUP BY 1, 2, 3, 4, 5, 6
),

-- Aggregate by month for each ASIN + search term
monthly_aggregates AS (
  SELECT 
    asin,
    normalized_search_term,
    year,
    month,
    year_month,
    SUM(paid_clicks) AS monthly_paid_clicks,
    SUM(paid_orders) AS monthly_paid_orders,
    SUM(organic_clicks) AS monthly_organic_clicks,
    SUM(organic_orders) AS monthly_organic_orders,
    SUM(total_orders) AS monthly_total_orders,
    
    -- Calculate clicks per order for this month
    CASE 
      WHEN SUM(total_orders) > 0 
      THEN ROUND((SUM(paid_clicks) + SUM(organic_clicks)) / SUM(total_orders), 2)
      ELSE NULL
    END AS monthly_clicks_per_order,
    
    -- Calculate organic clicks per order
    CASE 
      WHEN SUM(organic_orders) > 0 
      THEN ROUND(SUM(organic_clicks) / SUM(organic_orders), 2)
      ELSE NULL
    END AS monthly_organic_clicks_per_order
    
  FROM monthly_data
  GROUP BY 1, 2, 3, 4, 5
),

-- Calculate 6-month totals for filtering
six_month_totals AS (
  SELECT 
    asin,
    normalized_search_term,
    SUM(monthly_total_orders) AS total_orders_6m,
    SUM(monthly_paid_clicks) AS total_paid_clicks_6m,
    SUM(monthly_organic_orders) AS total_organic_orders_6m,
    SUM(monthly_organic_clicks) AS total_organic_clicks_6m,
    
    -- Overall clicks per order
    CASE 
      WHEN SUM(monthly_total_orders) > 0 
      THEN ROUND((SUM(monthly_paid_clicks) + SUM(monthly_organic_clicks)) / SUM(monthly_total_orders), 2)
      ELSE NULL
    END AS overall_clicks_per_order,
    
    -- % of orders from organic
    ROUND(SUM(monthly_organic_orders) / SUM(monthly_total_orders) * 100, 2) AS pct_organic_orders
    
  FROM monthly_aggregates
  GROUP BY 1, 2
)

-- POPULATION 1: Mostly Organic Performers
SELECT 
  'POPULATION_1_MOSTLY_ORGANIC' AS population_type,
  ma.asin,
  ma.normalized_search_term AS search_term,
  ma.year_month,
  ma.month,
  ma.year,
  
  -- Monthly metrics
  ma.monthly_paid_clicks,
  ma.monthly_organic_clicks,
  ma.monthly_paid_orders,
  ma.monthly_organic_orders,
  ma.monthly_total_orders,
  
  -- KEY METRIC: Clicks per order (smaller is better)
  ma.monthly_clicks_per_order,
  ma.monthly_organic_clicks_per_order,
  
  -- 6-month totals
  smt.total_orders_6m,
  smt.total_paid_clicks_6m,
  smt.total_organic_orders_6m,
  smt.overall_clicks_per_order,
  smt.pct_organic_orders,
  
  -- Status
  CASE 
    WHEN ma.monthly_clicks_per_order <= 3 THEN '🔥 EXCELLENT (≤3 clicks/order)'
    WHEN ma.monthly_clicks_per_order <= 5 THEN '✅ GOOD (≤5 clicks/order)'
    WHEN ma.monthly_clicks_per_order <= 10 THEN '💡 MODERATE (≤10 clicks/order)'
    ELSE '📊 HIGH (>10 clicks/order)'
  END AS efficiency_status
  
FROM monthly_aggregates ma
INNER JOIN six_month_totals smt
  ON ma.asin = smt.asin
  AND ma.normalized_search_term = smt.normalized_search_term
WHERE 
  -- Population 1 criteria: At least 20 orders, mostly organic (very few paid clicks)
  smt.total_orders_6m >= 20
  AND smt.total_paid_clicks_6m <= 50  -- Very few paid clicks (mostly organic)
  AND smt.pct_organic_orders >= 80  -- At least 80% of orders from organic

ORDER BY 
  smt.overall_clicks_per_order ASC,  -- Best efficiency first (smallest clicks per order)
  smt.total_orders_6m DESC,  -- Then by volume
  ma.year_month DESC;  -- Most recent months first

-- ==========================================
-- POPULATION 2: Paid Clicks Drive Organic Orders
-- ==========================================
-- Criteria:
--   - At least 20 orders in last 6 months
--   - At least 100 paid clicks in last 6 months
--   - Show correlation: when paid clicks increase, organic orders increase
--   - Show monthly clicks per order
-- ==========================================

WITH monthly_data_p2 AS (
  SELECT 
    COALESCE(org.Reporting_Date, paid.week_end_date) AS week_end_date,
    COALESCE(org.ASIN, paid.asin) AS asin,
    UPPER(TRIM(COALESCE(org.Search_Query, paid.search_term))) AS normalized_search_term,
    
    -- Extract month and year
    EXTRACT(YEAR FROM COALESCE(org.Reporting_Date, paid.week_end_date)) AS year,
    EXTRACT(MONTH FROM COALESCE(org.Reporting_Date, paid.week_end_date)) AS month,
    FORMAT_DATE('%Y-%m', COALESCE(org.Reporting_Date, paid.week_end_date)) AS year_month,
    
    -- Paid metrics
    SUM(COALESCE(paid.clicks, 0)) AS paid_clicks,
    SUM(COALESCE(paid.orders, 0)) AS paid_orders,
    
    -- Organic metrics
    SUM(COALESCE(org.Clicks, 0)) AS organic_clicks,
    SUM(COALESCE(org.ORDERS, 0)) AS organic_orders,
    
    -- Combined metrics
    SUM(COALESCE(org.ORDERS, 0) + COALESCE(paid.orders, 0)) AS total_orders
    
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
    -- Last 6 months
    AND COALESCE(org.Reporting_Date, paid.week_end_date) >= DATE_SUB(CURRENT_DATE(), INTERVAL 6 MONTH)
  GROUP BY 1, 2, 3, 4, 5, 6
),

-- Aggregate by month
monthly_aggregates_p2 AS (
  SELECT 
    asin,
    normalized_search_term,
    year,
    month,
    year_month,
    SUM(paid_clicks) AS monthly_paid_clicks,
    SUM(paid_orders) AS monthly_paid_orders,
    SUM(organic_clicks) AS monthly_organic_clicks,
    SUM(organic_orders) AS monthly_organic_orders,
    SUM(total_orders) AS monthly_total_orders,
    
    -- Calculate clicks per order for this month
    CASE 
      WHEN SUM(total_orders) > 0 
      THEN ROUND((SUM(paid_clicks) + SUM(organic_clicks)) / SUM(total_orders), 2)
      ELSE NULL
    END AS monthly_clicks_per_order,
    
    -- Paid clicks per order
    CASE 
      WHEN SUM(total_orders) > 0 
      THEN ROUND(SUM(paid_clicks) / SUM(total_orders), 2)
      ELSE NULL
    END AS monthly_paid_clicks_per_order
    
  FROM monthly_data_p2
  GROUP BY 1, 2, 3, 4, 5
),

-- Calculate 6-month totals and correlation
six_month_totals_p2 AS (
  SELECT 
    asin,
    normalized_search_term,
    SUM(monthly_total_orders) AS total_orders_6m,
    SUM(monthly_paid_clicks) AS total_paid_clicks_6m,
    SUM(monthly_organic_orders) AS total_organic_orders_6m,
    SUM(monthly_paid_orders) AS total_paid_orders_6m,
    
    -- Overall clicks per order
    CASE 
      WHEN SUM(monthly_total_orders) > 0 
      THEN ROUND((SUM(monthly_paid_clicks) + SUM(monthly_organic_clicks)) / SUM(monthly_total_orders), 2)
      ELSE NULL
    END AS overall_clicks_per_order,
    
    -- Correlation: Do organic orders increase when paid clicks increase?
    CORR(CAST(monthly_paid_clicks AS FLOAT64), CAST(monthly_organic_orders AS FLOAT64)) AS correlation_paid_clicks_to_organic_orders
    
  FROM monthly_aggregates_p2
  GROUP BY 1, 2
)

-- POPULATION 2: Paid Clicks Drive Organic Orders
SELECT 
  'POPULATION_2_PAID_DRIVES_ORGANIC' AS population_type,
  ma.asin,
  ma.normalized_search_term AS search_term,
  ma.year_month,
  ma.month,
  ma.year,
  
  -- Monthly metrics
  ma.monthly_paid_clicks,
  ma.monthly_organic_clicks,
  ma.monthly_paid_orders,
  ma.monthly_organic_orders,
  ma.monthly_total_orders,
  
  -- KEY METRIC: Clicks per order (smaller is better)
  ma.monthly_clicks_per_order,
  ma.monthly_paid_clicks_per_order,
  
  -- 6-month totals
  smt.total_orders_6m,
  smt.total_paid_clicks_6m,
  smt.total_organic_orders_6m,
  smt.total_paid_orders_6m,
  smt.overall_clicks_per_order,
  
  -- Correlation metric
  ROUND(smt.correlation_paid_clicks_to_organic_orders, 4) AS correlation_paid_to_organic,
  
  -- Correlation interpretation
  CASE 
    WHEN smt.correlation_paid_clicks_to_organic_orders >= 0.5 THEN '🔥 STRONG - Paid clicks drive organic orders'
    WHEN smt.correlation_paid_clicks_to_organic_orders >= 0.3 THEN '✅ MODERATE - Some relationship'
    WHEN smt.correlation_paid_clicks_to_organic_orders >= 0.1 THEN '💡 WEAK - Some connection'
    WHEN smt.correlation_paid_clicks_to_organic_orders < 0 THEN '⚠️ NEGATIVE - Investigate'
    ELSE '📊 NO CORRELATION'
  END AS correlation_status,
  
  -- Efficiency status
  CASE 
    WHEN ma.monthly_clicks_per_order <= 3 THEN '🔥 EXCELLENT (≤3 clicks/order)'
    WHEN ma.monthly_clicks_per_order <= 5 THEN '✅ GOOD (≤5 clicks/order)'
    WHEN ma.monthly_clicks_per_order <= 10 THEN '💡 MODERATE (≤10 clicks/order)'
    ELSE '📊 HIGH (>10 clicks/order)'
  END AS efficiency_status
  
FROM monthly_aggregates_p2 ma
INNER JOIN six_month_totals_p2 smt
  ON ma.asin = smt.asin
  AND ma.normalized_search_term = smt.normalized_search_term
WHERE 
  -- Population 2 criteria: At least 20 orders AND 100 paid clicks
  smt.total_orders_6m >= 20
  AND smt.total_paid_clicks_6m >= 100
  -- Prefer positive correlation (paid clicks help organic)
  AND smt.correlation_paid_clicks_to_organic_orders >= 0.1

ORDER BY 
  smt.correlation_paid_clicks_to_organic_orders DESC,  -- Best correlation first
  smt.overall_clicks_per_order ASC,  -- Then best efficiency
  smt.total_orders_6m DESC,  -- Then by volume
  ma.year_month DESC;  -- Most recent months first
