-- =============================================
-- FIND PILOT CANDIDATES: 5 Clicks = 1 Order
-- =============================================
-- Purpose: Find best candidates for pilot campaigns based on:
--          1. Order ratio >= 0.2 (5 clicks = 1 order)
--          2. Consistency over last 6 months
--          3. Seasonality (performance vs same month last year)
--
-- Project: onyga-482313
-- Dataset: OI
-- =============================================

WITH base_data AS (
  SELECT 
    COALESCE(org.Reporting_Date, paid.week_end_date) AS week_end_date,
    COALESCE(org.ASIN, paid.asin) AS asin,
    UPPER(TRIM(COALESCE(org.Search_Query, paid.search_term))) AS normalized_search_term,
    
    -- Extract month and year for seasonality
    EXTRACT(YEAR FROM COALESCE(org.Reporting_Date, paid.week_end_date)) AS year,
    EXTRACT(MONTH FROM COALESCE(org.Reporting_Date, paid.week_end_date)) AS month,
    
    -- Paid metrics
    SUM(COALESCE(paid.clicks, 0)) AS paid_clicks,
    SUM(COALESCE(paid.orders, 0)) AS paid_orders,
    SUM(COALESCE(paid.impressions, 0)) AS paid_impressions,
    
    -- Organic metrics
    SUM(COALESCE(org.ORDERS, 0)) AS organic_orders,
    SUM(COALESCE(org.Clicks, 0)) AS organic_clicks,
    
    -- Campaign context
    MAX(paid.campaign_type) AS campaign_type,
    MAX(paid.inferred_sales_module) AS sales_module
    
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
    -- Last 6 months + same month last year for comparison
    AND COALESCE(org.Reporting_Date, paid.week_end_date) >= DATE_SUB(CURRENT_DATE(), INTERVAL 13 MONTH)
  GROUP BY 1, 2, 3, 4, 5
),

-- Calculate monthly performance for seasonality
monthly_performance AS (
  SELECT 
    asin,
    normalized_search_term,
    year,
    month,
    SUM(paid_clicks) AS monthly_paid_clicks,
    SUM(paid_orders) AS monthly_paid_orders,
    SUM(organic_orders) AS monthly_organic_orders,
    SUM(paid_orders + organic_orders) AS monthly_combined_orders,
    CASE 
      WHEN SUM(paid_clicks) > 0 
      THEN SUM(paid_orders + organic_orders) / SUM(paid_clicks)
      ELSE 0
    END AS monthly_orders_per_click,
    CASE 
      WHEN SUM(paid_clicks) >= 5 
      THEN SUM(paid_orders + organic_orders) / SUM(paid_clicks) >= 0.2
      ELSE FALSE
    END AS monthly_meets_5_to_1
  FROM base_data
  GROUP BY 1, 2, 3, 4
),

-- Last 6 months analysis
last_6_months AS (
  SELECT 
    asin,
    normalized_search_term,
    SUM(monthly_paid_clicks) AS total_paid_clicks_6m,
    SUM(monthly_paid_orders) AS total_paid_orders_6m,
    SUM(monthly_organic_orders) AS total_organic_orders_6m,
    SUM(monthly_combined_orders) AS total_combined_orders_6m,
    COUNT(DISTINCT CONCAT(year, '-', LPAD(CAST(month AS STRING), 2, '0'))) AS months_active_6m,
    
    -- Overall ratio for last 6 months
    CASE 
      WHEN SUM(monthly_paid_clicks) > 0 
      THEN SUM(monthly_combined_orders) / SUM(monthly_paid_clicks)
      ELSE 0
    END AS orders_per_click_6m,
    
    -- How many months met 5:1 ratio
    SUM(CASE WHEN monthly_meets_5_to_1 THEN 1 ELSE 0 END) AS months_meeting_5_to_1_6m,
    
    -- Consistency score (0-1)
    CASE 
      WHEN COUNT(DISTINCT CONCAT(year, '-', LPAD(CAST(month AS STRING), 2, '0'))) > 0
      THEN SUM(CASE WHEN monthly_meets_5_to_1 THEN 1 ELSE 0 END) / 
           COUNT(DISTINCT CONCAT(year, '-', LPAD(CAST(month AS STRING), 2, '0')))
      ELSE 0
    END AS consistency_score_6m
    
  FROM monthly_performance
  WHERE 
    -- Last 6 months
    (year = EXTRACT(YEAR FROM CURRENT_DATE()) 
     AND month >= EXTRACT(MONTH FROM DATE_SUB(CURRENT_DATE(), INTERVAL 6 MONTH)))
    OR (year = EXTRACT(YEAR FROM DATE_SUB(CURRENT_DATE(), INTERVAL 6 MONTH))
        AND month >= EXTRACT(MONTH FROM DATE_SUB(CURRENT_DATE(), INTERVAL 6 MONTH)))
  GROUP BY 1, 2
  HAVING SUM(monthly_paid_clicks) >= 25  -- Minimum 25 clicks in 6 months
),

-- Current month (most recent)
current_month_data AS (
  SELECT 
    asin,
    normalized_search_term,
    monthly_paid_clicks,
    monthly_combined_orders,
    monthly_orders_per_click,
    monthly_meets_5_to_1
  FROM monthly_performance
  WHERE 
    year = EXTRACT(YEAR FROM CURRENT_DATE())
    AND month = EXTRACT(MONTH FROM CURRENT_DATE())
),

-- Same month last year (for seasonality)
same_month_last_year AS (
  SELECT 
    asin,
    normalized_search_term,
    monthly_paid_clicks AS last_year_paid_clicks,
    monthly_combined_orders AS last_year_combined_orders,
    monthly_orders_per_click AS last_year_orders_per_click,
    monthly_meets_5_to_1 AS last_year_meets_5_to_1
  FROM monthly_performance
  WHERE 
    year = EXTRACT(YEAR FROM DATE_SUB(CURRENT_DATE(), INTERVAL 1 YEAR))
    AND month = EXTRACT(MONTH FROM CURRENT_DATE())
)

SELECT 
  l6m.asin,
  l6m.normalized_search_term AS search_term,
  
  -- Last 6 months performance
  l6m.total_paid_clicks_6m,
  l6m.total_paid_orders_6m,
  l6m.total_organic_orders_6m,
  l6m.total_combined_orders_6m,
  l6m.months_active_6m,
  l6m.months_meeting_5_to_1_6m,
  ROUND(l6m.consistency_score_6m, 4) AS consistency_score_6m,
  ROUND(l6m.orders_per_click_6m, 4) AS orders_per_click_6m,
  ROUND(l6m.orders_per_click_6m * 100, 2) AS conversion_rate_pct_6m,
  
  -- Current month performance
  COALESCE(curr.monthly_paid_clicks, 0) AS current_month_paid_clicks,
  COALESCE(curr.monthly_combined_orders, 0) AS current_month_orders,
  COALESCE(curr.monthly_orders_per_click, 0) AS current_month_ratio,
  COALESCE(curr.monthly_meets_5_to_1, FALSE) AS current_month_meets_target,
  
  -- Same month last year (seasonality)
  COALESCE(lyr.last_year_paid_clicks, 0) AS last_year_same_month_clicks,
  COALESCE(lyr.last_year_combined_orders, 0) AS last_year_same_month_orders,
  COALESCE(lyr.last_year_orders_per_click, 0) AS last_year_same_month_ratio,
  COALESCE(lyr.last_year_meets_5_to_1, FALSE) AS last_year_meets_target,
  
  -- Seasonality comparison
  CASE 
    WHEN lyr.last_year_orders_per_click > 0 
    THEN ROUND((l6m.orders_per_click_6m - lyr.last_year_orders_per_click) / lyr.last_year_orders_per_click * 100, 2)
    ELSE NULL
  END AS seasonality_improvement_pct,
  
  CASE 
    WHEN lyr.last_year_orders_per_click > 0 
      AND l6m.orders_per_click_6m > lyr.last_year_orders_per_click 
    THEN TRUE
    WHEN lyr.last_year_orders_per_click = 0 
      AND l6m.orders_per_click_6m > 0.2 
    THEN TRUE
    ELSE FALSE
  END AS better_than_last_year,
  
  -- PILOT CANDIDATE SCORING
  -- Score 1: Ratio quality (0-40 points)
  CASE 
    WHEN l6m.orders_per_click_6m >= 0.3 THEN 40  -- Excellent (better than 3.3:1)
    WHEN l6m.orders_per_click_6m >= 0.25 THEN 35  -- Very good (4:1)
    WHEN l6m.orders_per_click_6m >= 0.2 THEN 30  -- Meets target (5:1)
    WHEN l6m.orders_per_click_6m >= 0.15 THEN 20  -- Close (6.7:1)
    ELSE 10
  END AS ratio_score,
  
  -- Score 2: Consistency (0-30 points)
  CASE 
    WHEN l6m.consistency_score_6m >= 0.8 THEN 30  -- 80%+ months met target
    WHEN l6m.consistency_score_6m >= 0.6 THEN 25  -- 60-80%
    WHEN l6m.consistency_score_6m >= 0.4 THEN 20  -- 40-60%
    WHEN l6m.consistency_score_6m >= 0.2 THEN 15  -- 20-40%
    ELSE 10
  END AS consistency_score_points,
  
  -- Score 3: Seasonality (0-20 points)
  CASE 
    WHEN better_than_last_year = TRUE 
      AND lyr.last_year_orders_per_click > 0 
      AND seasonality_improvement_pct > 20 
    THEN 20  -- 20%+ better than last year
    WHEN better_than_last_year = TRUE 
      AND lyr.last_year_orders_per_click > 0 
      AND seasonality_improvement_pct > 10 
    THEN 15  -- 10-20% better
    WHEN better_than_last_year = TRUE THEN 10  -- Better but <10%
    WHEN lyr.last_year_orders_per_click = 0 
      AND l6m.orders_per_click_6m >= 0.2 
    THEN 15  -- No last year data but meets target
    ELSE 5
  END AS seasonality_score_points,
  
  -- Score 4: Volume (0-10 points)
  CASE 
    WHEN l6m.total_paid_clicks_6m >= 100 THEN 10
    WHEN l6m.total_paid_clicks_6m >= 50 THEN 8
    WHEN l6m.total_paid_clicks_6m >= 25 THEN 6
    ELSE 4
  END AS volume_score,
  
  -- TOTAL PILOT SCORE (0-100)
  (
    CASE 
      WHEN l6m.orders_per_click_6m >= 0.3 THEN 40
      WHEN l6m.orders_per_click_6m >= 0.25 THEN 35
      WHEN l6m.orders_per_click_6m >= 0.2 THEN 30
      WHEN l6m.orders_per_click_6m >= 0.15 THEN 20
      ELSE 10
    END +
    CASE 
      WHEN l6m.consistency_score_6m >= 0.8 THEN 30
      WHEN l6m.consistency_score_6m >= 0.6 THEN 25
      WHEN l6m.consistency_score_6m >= 0.4 THEN 20
      WHEN l6m.consistency_score_6m >= 0.2 THEN 15
      ELSE 10
    END +
    CASE 
      WHEN better_than_last_year = TRUE 
        AND lyr.last_year_orders_per_click > 0 
        AND seasonality_improvement_pct > 20 
      THEN 20
      WHEN better_than_last_year = TRUE 
        AND lyr.last_year_orders_per_click > 0 
        AND seasonality_improvement_pct > 10 
      THEN 15
      WHEN better_than_last_year = TRUE THEN 10
      WHEN lyr.last_year_orders_per_click = 0 
        AND l6m.orders_per_click_6m >= 0.2 
      THEN 15
      ELSE 5
    END +
    CASE 
      WHEN l6m.total_paid_clicks_6m >= 100 THEN 10
      WHEN l6m.total_paid_clicks_6m >= 50 THEN 8
      WHEN l6m.total_paid_clicks_6m >= 25 THEN 6
      ELSE 4
    END
  ) AS pilot_candidate_score,
  
  -- Status indicators
  CASE 
    WHEN l6m.orders_per_click_6m >= 0.2 THEN '✅ MEETS TARGET'
    WHEN l6m.orders_per_click_6m >= 0.15 THEN '💡 CLOSE TO TARGET'
    ELSE '❌ BELOW TARGET'
  END AS ratio_status,
  
  CASE 
    WHEN l6m.consistency_score_6m >= 0.8 THEN '🔥 VERY CONSISTENT'
    WHEN l6m.consistency_score_6m >= 0.6 THEN '✅ CONSISTENT'
    WHEN l6m.consistency_score_6m >= 0.4 THEN '💡 MODERATE'
    ELSE '📊 INCONSISTENT'
  END AS consistency_status,
  
  CASE 
    WHEN better_than_last_year = TRUE 
      AND seasonality_improvement_pct > 20 
    THEN '🔥 MUCH BETTER THAN LAST YEAR'
    WHEN better_than_last_year = TRUE 
    THEN '✅ BETTER THAN LAST YEAR'
    WHEN lyr.last_year_orders_per_click = 0 
    THEN '💡 NO LAST YEAR DATA'
    ELSE '📊 SIMILAR/WORSE'
  END AS seasonality_status,
  
  -- Overall pilot recommendation
  CASE 
    WHEN l6m.orders_per_click_6m >= 0.2 
      AND l6m.consistency_score_6m >= 0.6 
      AND better_than_last_year = TRUE 
    THEN '🔥 EXCELLENT PILOT CANDIDATE'
    WHEN l6m.orders_per_click_6m >= 0.2 
      AND l6m.consistency_score_6m >= 0.6 
    THEN '✅ STRONG PILOT CANDIDATE'
    WHEN l6m.orders_per_click_6m >= 0.2 
      AND l6m.consistency_score_6m >= 0.4 
    THEN '💡 GOOD PILOT CANDIDATE'
    WHEN l6m.orders_per_click_6m >= 0.15 
      AND l6m.consistency_score_6m >= 0.6 
    THEN '💡 MODERATE - Optimize to reach 0.2'
    ELSE '📊 MONITOR - Needs improvement'
  END AS pilot_recommendation
  
FROM last_6_months l6m
LEFT JOIN current_month_data curr
  ON l6m.asin = curr.asin
  AND l6m.normalized_search_term = curr.normalized_search_term
LEFT JOIN same_month_last_year lyr
  ON l6m.asin = lyr.asin
  AND l6m.normalized_search_term = lyr.normalized_search_term
WHERE 
  -- Minimum criteria for pilot consideration
  l6m.orders_per_click_6m >= 0.15  -- At least close to target
  AND l6m.total_paid_clicks_6m >= 25  -- Minimum volume
ORDER BY 
  -- Prioritize by pilot candidate score
  pilot_candidate_score DESC,
  l6m.orders_per_click_6m DESC,
  l6m.consistency_score_6m DESC
LIMIT 200;
