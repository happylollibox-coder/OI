-- =============================================
-- ASIN Tables Insights Analysis
-- =============================================
-- Purpose: Generate actionable business insights from ASIN performance data
-- Project: onyga-482313
-- Dataset: OI
-- =============================================

-- ==========================================
-- INSIGHT 1: HIGH-PERFORMING SEARCH QUERIES
-- ==========================================
-- Identifies search queries with best conversion rates and purchase volume
WITH query_performance AS (
  SELECT 
    Search_Query,
    COUNT(DISTINCT SKU) as sku_count,
    SUM(Impressions_Total_Count) as total_impressions,
    SUM(Clicks_Total_Count) as total_clicks,
    SUM(Cart_Adds_Total_Count) as total_cart_adds,
    SUM(Purchases_Total_Count) as total_purchases,
    AVG(Search_Query_Score) as avg_query_score,
    MAX(Search_Query_Volume) as max_query_volume,
    ROUND(SAFE_DIVIDE(SUM(Clicks_Total_Count), SUM(Impressions_Total_Count)) * 100, 2) as ctr_pct,
    ROUND(SAFE_DIVIDE(SUM(Purchases_Total_Count), SUM(Clicks_Total_Count)) * 100, 2) as conversion_rate_pct,
    ROUND(SAFE_DIVIDE(SUM(Cart_Adds_Total_Count), SUM(Clicks_Total_Count)) * 100, 2) as cart_add_rate_pct
  FROM `onyga-482313.OI.SQP_ASIN_View_Simple_Week`
  WHERE Purchases_Total_Count > 0
  GROUP BY Search_Query
)
SELECT 
  'HIGH_PERFORMING_QUERIES' as insight_type,
  Search_Query,
  total_purchases,
  conversion_rate_pct,
  ctr_pct,
  total_impressions,
  total_clicks,
  avg_query_score,
  max_query_volume,
  ROUND(total_purchases * 100.0 / SUM(total_purchases) OVER(), 2) as pct_of_total_purchases
FROM query_performance
WHERE total_purchases >= 10  -- Minimum threshold
ORDER BY total_purchases DESC, conversion_rate_pct DESC
LIMIT 50;

-- ==========================================
-- INSIGHT 2: UNDERPERFORMING SEARCH QUERIES
-- ==========================================
-- Identifies queries with high volume but low conversion (optimization opportunities)
WITH query_performance AS (
  SELECT 
    Search_Query,
    SUM(Impressions_Total_Count) as total_impressions,
    SUM(Clicks_Total_Count) as total_clicks,
    SUM(Purchases_Total_Count) as total_purchases,
    MAX(Search_Query_Volume) as query_volume,
    ROUND(SAFE_DIVIDE(SUM(Clicks_Total_Count), SUM(Impressions_Total_Count)) * 100, 2) as ctr_pct,
    ROUND(SAFE_DIVIDE(SUM(Purchases_Total_Count), SUM(Clicks_Total_Count)) * 100, 2) as conversion_rate_pct
  FROM `onyga-482313.OI.SQP_ASIN_View_Simple_Week`
  WHERE Impressions_Total_Count >= 1000  -- Significant traffic
  GROUP BY Search_Query
)
SELECT 
  'UNDERPERFORMING_QUERIES' as insight_type,
  Search_Query,
  total_impressions,
  total_clicks,
  total_purchases,
  query_volume,
  ctr_pct,
  conversion_rate_pct,
  CASE 
    WHEN conversion_rate_pct < 1 THEN 'LOW_CONVERSION'
    WHEN ctr_pct < 2 THEN 'LOW_CTR'
    ELSE 'NEEDS_OPTIMIZATION'
  END as issue_type
FROM query_performance
WHERE (conversion_rate_pct < 2.0 OR ctr_pct < 3.0) 
  AND total_purchases < 5
ORDER BY total_impressions DESC
LIMIT 30;

-- ==========================================
-- INSIGHT 3: TOP PRODUCTS (SKUs) BY PERFORMANCE
-- ==========================================
SELECT 
  'TOP_SKUS_BY_PURCHASES' as insight_type,
  SKU,
  COUNT(DISTINCT Search_Query) as unique_queries,
  SUM(Impressions_Total_Count) as total_impressions,
  SUM(Clicks_Total_Count) as total_clicks,
  SUM(Cart_Adds_Total_Count) as total_cart_adds,
  SUM(Purchases_Total_Count) as total_purchases,
  ROUND(SAFE_DIVIDE(SUM(Purchases_Total_Count), SUM(Clicks_Total_Count)) * 100, 2) as conversion_rate_pct,
  ROUND(AVG(Clicks_Price_Median), 2) as avg_price,
  COUNT(DISTINCT Year || '-' || Week) as weeks_active
FROM `onyga-482313.OI.SQP_ASIN_View_Simple_Week`
GROUP BY SKU
HAVING total_purchases > 0
ORDER BY total_purchases DESC
LIMIT 20;

-- ==========================================
-- INSIGHT 4: SHIPPING SPEED IMPACT ON CONVERSION
-- ==========================================
SELECT 
  'SHIPPING_SPEED_ANALYSIS' as insight_type,
  'Same Day' as shipping_speed,
  SUM(Clicks_Same_Day_Shipping_Speed) as clicks,
  SUM(Purchases_Same_Day_Shipping_Speed) as purchases,
  ROUND(SAFE_DIVIDE(SUM(Purchases_Same_Day_Shipping_Speed), SUM(Clicks_Same_Day_Shipping_Speed)) * 100, 2) as conversion_pct
FROM `onyga-482313.OI.SQP_ASIN_View_Simple_Week`
WHERE Clicks_Same_Day_Shipping_Speed > 0
UNION ALL
SELECT 
  'SHIPPING_SPEED_ANALYSIS' as insight_type,
  '1 Day' as shipping_speed,
  SUM(Clicks_1D_Shipping_Speed) as clicks,
  SUM(Purchases_1D_Shipping_Speed) as purchases,
  ROUND(SAFE_DIVIDE(SUM(Purchases_1D_Shipping_Speed), SUM(Clicks_1D_Shipping_Speed)) * 100, 2) as conversion_pct
FROM `onyga-482313.OI.SQP_ASIN_View_Simple_Week`
WHERE Clicks_1D_Shipping_Speed > 0
UNION ALL
SELECT 
  'SHIPPING_SPEED_ANALYSIS' as insight_type,
  '2 Day' as shipping_speed,
  SUM(Clicks_2D_Shipping_Speed) as clicks,
  SUM(Purchases_2D_Shipping_Speed) as purchases,
  ROUND(SAFE_DIVIDE(SUM(Purchases_2D_Shipping_Speed), SUM(Clicks_2D_Shipping_Speed)) * 100, 2) as conversion_pct
FROM `onyga-482313.OI.SQP_ASIN_View_Simple_Week`
WHERE Clicks_2D_Shipping_Speed > 0;

-- ==========================================
-- INSIGHT 5: WEEKLY TRENDS AND PATTERNS
-- ==========================================
SELECT 
  'WEEKLY_TRENDS' as insight_type,
  Year,
  Week,
  PARSE_DATE('%d/%m/%Y', Week_Start_date) as week_start_date,
  COUNT(DISTINCT SKU) as active_skus,
  COUNT(DISTINCT Search_Query) as active_queries,
  SUM(Impressions_Total_Count) as total_impressions,
  SUM(Clicks_Total_Count) as total_clicks,
  SUM(Purchases_Total_Count) as total_purchases,
  ROUND(SAFE_DIVIDE(SUM(Clicks_Total_Count), SUM(Impressions_Total_Count)) * 100, 2) as avg_ctr_pct,
  ROUND(SAFE_DIVIDE(SUM(Purchases_Total_Count), SUM(Clicks_Total_Count)) * 100, 2) as avg_conversion_pct,
  LAG(SUM(Purchases_Total_Count)) OVER (ORDER BY Year, Week) as prev_week_purchases,
  ROUND(
    (SUM(Purchases_Total_Count) - LAG(SUM(Purchases_Total_Count)) OVER (ORDER BY Year, Week)) * 100.0 / 
    NULLIF(LAG(SUM(Purchases_Total_Count)) OVER (ORDER BY Year, Week), 0),
    2
  ) as week_over_week_change_pct
FROM `onyga-482313.OI.SQP_ASIN_View_Simple_Week`
GROUP BY Year, Week, Week_Start_date
ORDER BY Year DESC, Week DESC
LIMIT 26;  -- Last 6 months

-- ==========================================
-- INSIGHT 6: PRICE SENSITIVITY ANALYSIS
-- ==========================================
SELECT 
  'PRICE_SENSITIVITY' as insight_type,
  CASE 
    WHEN Clicks_Price_Median < 15 THEN '< $15'
    WHEN Clicks_Price_Median < 25 THEN '$15-$25'
    WHEN Clicks_Price_Median < 35 THEN '$25-$35'
    WHEN Clicks_Price_Median < 50 THEN '$35-$50'
    ELSE '> $50'
  END as price_range,
  COUNT(*) as query_sku_combinations,
  SUM(Clicks_Total_Count) as total_clicks,
  SUM(Purchases_Total_Count) as total_purchases,
  ROUND(AVG(Clicks_Price_Median), 2) as avg_price,
  ROUND(SAFE_DIVIDE(SUM(Purchases_Total_Count), SUM(Clicks_Total_Count)) * 100, 2) as conversion_rate_pct,
  ROUND(SAFE_DIVIDE(SUM(Cart_Adds_Total_Count), SUM(Clicks_Total_Count)) * 100, 2) as cart_add_rate_pct
FROM `onyga-482313.OI.SQP_ASIN_View_Simple_Week`
WHERE Clicks_Price_Median IS NOT NULL AND Clicks_Price_Median > 0
GROUP BY price_range
ORDER BY 
  CASE price_range
    WHEN '< $15' THEN 1
    WHEN '$15-$25' THEN 2
    WHEN '$25-$35' THEN 3
    WHEN '$35-$50' THEN 4
    ELSE 5
  END;

-- ==========================================
-- INSIGHT 7: SEARCH QUERY SCORE VS PERFORMANCE
-- ==========================================
SELECT 
  'QUERY_SCORE_PERFORMANCE' as insight_type,
  CASE 
    WHEN Search_Query_Score >= 90 THEN 'Excellent (90+)'
    WHEN Search_Query_Score >= 70 THEN 'Good (70-89)'
    WHEN Search_Query_Score >= 50 THEN 'Fair (50-69)'
    WHEN Search_Query_Score >= 30 THEN 'Poor (30-49)'
    ELSE 'Very Poor (<30)'
  END as score_category,
  COUNT(*) as query_count,
  SUM(Purchases_Total_Count) as total_purchases,
  ROUND(AVG(Search_Query_Score), 1) as avg_score,
  ROUND(SAFE_DIVIDE(SUM(Purchases_Total_Count), SUM(Clicks_Total_Count)) * 100, 2) as conversion_rate_pct
FROM `onyga-482313.OI.SQP_ASIN_View_Simple_Week`
WHERE Search_Query_Score IS NOT NULL
GROUP BY score_category
ORDER BY 
  CASE score_category
    WHEN 'Excellent (90+)' THEN 1
    WHEN 'Good (70-89)' THEN 2
    WHEN 'Fair (50-69)' THEN 3
    WHEN 'Poor (30-49)' THEN 4
    ELSE 5
  END;

-- ==========================================
-- INSIGHT 8: PRODUCT-SPECIFIC OPPORTUNITIES
-- ==========================================
-- Products with high impressions but low purchases (optimization opportunities)
SELECT 
  'PRODUCT_OPTIMIZATION_OPPORTUNITIES' as insight_type,
  SKU,
  SUM(Impressions_Total_Count) as total_impressions,
  SUM(Clicks_Total_Count) as total_clicks,
  SUM(Purchases_Total_Count) as total_purchases,
  ROUND(SAFE_DIVIDE(SUM(Clicks_Total_Count), SUM(Impressions_Total_Count)) * 100, 2) as ctr_pct,
  ROUND(SAFE_DIVIDE(SUM(Purchases_Total_Count), SUM(Clicks_Total_Count)) * 100, 2) as conversion_rate_pct,
  CASE 
    WHEN SAFE_DIVIDE(SUM(Clicks_Total_Count), SUM(Impressions_Total_Count)) < 0.03 THEN 'LOW_CTR'
    WHEN SAFE_DIVIDE(SUM(Purchases_Total_Count), SUM(Clicks_Total_Count)) < 2.0 THEN 'LOW_CONVERSION'
    ELSE 'NEEDS_REVIEW'
  END as optimization_area,
  COUNT(DISTINCT Search_Query) as query_count
FROM `onyga-482313.OI.SQP_ASIN_View_Simple_Week`
GROUP BY SKU
HAVING total_impressions >= 10000 AND total_purchases < 50
ORDER BY total_impressions DESC
LIMIT 20;

-- ==========================================
-- INSIGHT 9: SEASONAL/TREND ANALYSIS (by Week)
-- ==========================================
SELECT 
  'SEASONAL_ANALYSIS' as insight_type,
  EXTRACT(MONTH FROM PARSE_DATE('%d/%m/%Y', Week_Start_date)) as month,
  EXTRACT(DAYOFWEEK FROM PARSE_DATE('%d/%m/%Y', Week_Start_date)) as day_of_week,
  COUNT(DISTINCT Year || '-' || Week) as week_count,
  AVG(total_purchases) as avg_weekly_purchases,
  AVG(avg_conversion) as avg_conversion_rate
FROM (
  SELECT 
    Year,
    Week,
    Week_Start_date,
    SUM(Purchases_Total_Count) as total_purchases,
    ROUND(SAFE_DIVIDE(SUM(Purchases_Total_Count), SUM(Clicks_Total_Count)) * 100, 2) as avg_conversion
  FROM `onyga-482313.OI.SQP_ASIN_View_Simple_Week`
  GROUP BY Year, Week, Week_Start_date
)
GROUP BY month, day_of_week
ORDER BY month, day_of_week;

-- ==========================================
-- INSIGHT 10: CART ABANDONMENT ANALYSIS
-- ==========================================
SELECT 
  'CART_ABANDONMENT' as insight_type,
  SUM(Cart_Adds_Total_Count) as total_cart_adds,
  SUM(Purchases_Total_Count) as total_purchases,
  SUM(Cart_Adds_Total_Count) - SUM(Purchases_Total_Count) as abandoned_carts,
  ROUND(SAFE_DIVIDE(SUM(Purchases_Total_Count), SUM(Cart_Adds_Total_Count)) * 100, 2) as cart_to_purchase_rate_pct,
  ROUND(SAFE_DIVIDE(SUM(Cart_Adds_Total_Count) - SUM(Purchases_Total_Count), SUM(Cart_Adds_Total_Count)) * 100, 2) as abandonment_rate_pct,
  ROUND(AVG(Cart_Adds_Price_Median), 2) as avg_cart_price,
  ROUND(AVG(Purchases_Price_Median), 2) as avg_purchase_price
FROM `onyga-482313.OI.SQP_ASIN_View_Simple_Week`
WHERE Cart_Adds_Total_Count > 0;

-- ==========================================
-- INSIGHT 11: ASIN-LEVEL PERFORMANCE (SCP Table)
-- ==========================================
-- Only if SCP_ASIN_View_Week table exists
SELECT 
  'ASIN_LEVEL_PERFORMANCE' as insight_type,
  ASIN,
  ASIN_Title,
  Category,
  COUNT(DISTINCT Year || '-' || Week) as weeks_active,
  SUM(Impressions_Impressions) as total_impressions,
  SUM(Clicks_Clicks) as total_clicks,
  SUM(Purchases_Purchases) as total_purchases,
  SUM(Purchases_Search_Traffic_Sales) as total_sales,
  ROUND(AVG(Clicks_Click_Rate_CTR), 2) as avg_ctr_pct,
  ROUND(AVG(Purchases_Conversion_Rate_Percent), 2) as avg_conversion_pct,
  ROUND(AVG(Purchases_Price_Median), 2) as avg_price,
  ROUND(AVG(Impressions_Rating_Median), 1) as avg_rating
FROM `onyga-482313.OI.SCP_ASIN_View_Week`
WHERE ASIN IS NOT NULL
GROUP BY ASIN, ASIN_Title, Category
HAVING total_purchases > 0
ORDER BY total_purchases DESC
LIMIT 20;
