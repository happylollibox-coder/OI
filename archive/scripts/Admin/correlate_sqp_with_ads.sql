-- =============================================
-- Correlation Analysis: SQP_ASIN_View_Simple_Week vs V_SRC_AmazonAds_SearchTerms
-- =============================================
-- Purpose: Correlate organic search query insights with paid advertising performance
-- Project: onyga-482313
-- Dataset: OI
-- =============================================

-- ==========================================
-- CORRELATION 1: TOP QUERIES - SQP vs ADS
-- ==========================================
-- Compare top performing queries from organic search (SQP) with paid ads performance
WITH sqp_top_queries AS (
  SELECT 
    Search_Query,
    SUM(Impressions_Total_Count) as sqp_impressions,
    SUM(Clicks_Total_Count) as sqp_clicks,
    SUM(Purchases_Total_Count) as sqp_purchases,
    ROUND(SAFE_DIVIDE(SUM(Clicks_Total_Count), SUM(Impressions_Total_Count)) * 100, 2) as sqp_ctr,
    ROUND(SAFE_DIVIDE(SUM(Purchases_Total_Count), SUM(Clicks_Total_Count)) * 100, 2) as sqp_conversion_rate
  FROM `onyga-482313.OI.SQP_ASIN_View_Simple_Week`
  GROUP BY Search_Query
  HAVING SUM(Purchases_Total_Count) >= 100  -- Top performers threshold
),
ads_query_performance AS (
  SELECT 
    search_term,
    SUM(impressions) as ads_impressions,
    SUM(clicks) as ads_clicks,
    SUM(cost) as ads_cost,
    SUM(orders) as ads_orders,
    SUM(sales) as ads_sales,
    COUNT(DISTINCT campaign_id) as campaign_count,
    COUNT(DISTINCT ad_group_id) as ad_group_count,
    ROUND(SAFE_DIVIDE(SUM(clicks), SUM(impressions)) * 100, 2) as ads_ctr,
    ROUND(SAFE_DIVIDE(SUM(orders), SUM(clicks)) * 100, 2) as ads_conversion_rate,
    ROUND(SAFE_DIVIDE(SUM(cost), SUM(orders)), 2) as ads_cpa,
    ROUND(SAFE_DIVIDE(SUM(sales), SUM(cost)), 2) as ads_roas
  FROM `onyga-482313.OI.V_SRC_AmazonAds_SearchTerms`
  GROUP BY search_term
)
SELECT 
  'TOP_QUERIES_CORRELATION' as analysis_type,
  COALESCE(sqp.Search_Query, ads.search_term) as search_query,
  sqp.sqp_impressions,
  sqp.sqp_clicks,
  sqp.sqp_purchases,
  sqp.sqp_ctr,
  sqp.sqp_conversion_rate,
  ads.ads_impressions,
  ads.ads_clicks,
  ads.ads_orders,
  ads.ads_cost,
  ads.ads_sales,
  ads.ads_ctr,
  ads.ads_conversion_rate,
  ads.ads_cpa,
  ads.ads_roas,
  ads.campaign_count,
  ads.ad_group_count,
  CASE 
    WHEN sqp.Search_Query IS NULL THEN 'ADS_ONLY'
    WHEN ads.search_term IS NULL THEN 'SQP_ONLY'
    ELSE 'BOTH'
  END as data_source,
  -- Calculate coverage ratio
  ROUND(SAFE_DIVIDE(COALESCE(ads.ads_impressions, 0), COALESCE(sqp.sqp_impressions, 1)) * 100, 2) as ads_to_sqp_impression_ratio,
  -- Performance comparison
  ROUND(ads.ads_conversion_rate - sqp.sqp_conversion_rate, 2) as conversion_rate_delta
FROM sqp_top_queries sqp
FULL OUTER JOIN ads_query_performance ads 
  ON LOWER(TRIM(sqp.Search_Query)) = LOWER(TRIM(ads.search_term))
ORDER BY COALESCE(sqp.sqp_purchases, ads.ads_orders) DESC
LIMIT 50;

-- ==========================================
-- CORRELATION 2: HIGH CONVERSION QUERIES
-- ==========================================
-- Identify queries with high conversion in both organic and paid
WITH sqp_high_conv AS (
  SELECT 
    Search_Query,
    SUM(Purchases_Total_Count) as sqp_purchases,
    ROUND(SAFE_DIVIDE(SUM(Purchases_Total_Count), SUM(Clicks_Total_Count)) * 100, 2) as sqp_conversion_rate
  FROM `onyga-482313.OI.SQP_ASIN_View_Simple_Week`
  WHERE Clicks_Total_Count > 0
  GROUP BY Search_Query
  HAVING SUM(Purchases_Total_Count) >= 10 
    AND ROUND(SAFE_DIVIDE(SUM(Purchases_Total_Count), SUM(Clicks_Total_Count)) * 100, 2) >= 15  -- High conversion threshold
),
ads_high_conv AS (
  SELECT 
    search_term,
    SUM(orders) as ads_orders,
    ROUND(SAFE_DIVIDE(SUM(orders), SUM(clicks)) * 100, 2) as ads_conversion_rate,
    ROUND(SAFE_DIVIDE(SUM(sales), SUM(cost)), 2) as roas
  FROM `onyga-482313.OI.V_SRC_AmazonAds_SearchTerms`
  WHERE clicks > 0
  GROUP BY search_term
  HAVING SUM(orders) >= 10 
    AND ROUND(SAFE_DIVIDE(SUM(orders), SUM(clicks)) * 100, 2) >= 10
)
SELECT 
  'HIGH_CONVERSION_CORRELATION' as analysis_type,
  COALESCE(sqp.Search_Query, ads.search_term) as search_query,
  sqp.sqp_purchases,
  sqp.sqp_conversion_rate,
  ads.ads_orders,
  ads.ads_conversion_rate,
  ads.roas,
  CASE 
    WHEN sqp.sqp_conversion_rate >= 20 AND ads.ads_conversion_rate >= 15 THEN 'EXCELLENT_BOTH'
    WHEN sqp.sqp_conversion_rate >= 20 THEN 'EXCELLENT_ORGANIC'
    WHEN ads.ads_conversion_rate >= 15 THEN 'EXCELLENT_PAID'
    ELSE 'GOOD_BOTH'
  END as performance_tier
FROM sqp_high_conv sqp
FULL OUTER JOIN ads_high_conv ads 
  ON LOWER(TRIM(sqp.Search_Query)) = LOWER(TRIM(ads.search_term))
ORDER BY COALESCE(sqp.sqp_conversion_rate, ads.ads_conversion_rate) DESC
LIMIT 50;

-- ==========================================
-- CORRELATION 3: GIFT CARD QUERIES ANALYSIS
-- ==========================================
-- Deep dive into gift card queries (top performer from SQP insights)
WITH sqp_gift_cards AS (
  SELECT 
    Search_Query,
    SUM(Impressions_Total_Count) as sqp_impressions,
    SUM(Clicks_Total_Count) as sqp_clicks,
    SUM(Purchases_Total_Count) as sqp_purchases,
    ROUND(SAFE_DIVIDE(SUM(Purchases_Total_Count), SUM(Clicks_Total_Count)) * 100, 2) as sqp_conversion_rate
  FROM `onyga-482313.OI.SQP_ASIN_View_Simple_Week`
  WHERE LOWER(Search_Query) LIKE '%gift card%' OR LOWER(Search_Query) LIKE '%giftcard%'
  GROUP BY Search_Query
),
ads_gift_cards AS (
  SELECT 
    search_term,
    campaign_name,
    SUM(impressions) as ads_impressions,
    SUM(clicks) as ads_clicks,
    SUM(cost) as ads_cost,
    SUM(orders) as ads_orders,
    SUM(sales) as ads_sales,
    ROUND(SAFE_DIVIDE(SUM(clicks), SUM(impressions)) * 100, 2) as ads_ctr,
    ROUND(SAFE_DIVIDE(SUM(orders), SUM(clicks)) * 100, 2) as ads_conversion_rate,
    ROUND(SAFE_DIVIDE(SUM(sales), SUM(cost)), 2) as roas
  FROM `onyga-482313.OI.V_SRC_AmazonAds_SearchTerms`
  WHERE LOWER(search_term) LIKE '%gift card%' OR LOWER(search_term) LIKE '%giftcard%'
  GROUP BY search_term, campaign_name
)
SELECT 
  'GIFT_CARD_ANALYSIS' as analysis_type,
  COALESCE(sqp.Search_Query, ads.search_term) as search_query,
  ads.campaign_name,
  sqp.sqp_impressions,
  sqp.sqp_clicks,
  sqp.sqp_purchases,
  sqp.sqp_conversion_rate,
  ads.ads_impressions,
  ads.ads_clicks,
  ads.ads_orders,
  ads.ads_cost,
  ads.ads_sales,
  ads.ads_conversion_rate,
  ads.roas,
  CASE 
    WHEN sqp.sqp_conversion_rate > 20 AND ads.ads_conversion_rate > 10 THEN 'PRIORITY_INVEST'
    WHEN sqp.sqp_conversion_rate > 20 THEN 'INVEST_IN_ADS'
    WHEN ads.ads_conversion_rate > 15 THEN 'LEVERAGE_ORGANIC'
    ELSE 'MONITOR'
  END as recommendation
FROM sqp_gift_cards sqp
FULL OUTER JOIN ads_gift_cards ads 
  ON LOWER(TRIM(sqp.Search_Query)) = LOWER(TRIM(ads.search_term))
ORDER BY COALESCE(sqp.sqp_purchases, ads.ads_orders) DESC
LIMIT 30;

-- ==========================================
-- CORRELATION 4: CAMPAIGN EFFECTIVENESS BY QUERY TYPE
-- ==========================================
-- Analyze which campaigns are most effective for top SQP queries
WITH sqp_top_20 AS (
  SELECT 
    Search_Query,
    SUM(Purchases_Total_Count) as sqp_purchases,
    ROUND(SAFE_DIVIDE(SUM(Purchases_Total_Count), SUM(Clicks_Total_Count)) * 100, 2) as sqp_conversion_rate
  FROM `onyga-482313.OI.SQP_ASIN_View_Simple_Week`
  GROUP BY Search_Query
  ORDER BY SUM(Purchases_Total_Count) DESC
  LIMIT 20
),
ads_campaign_performance AS (
  SELECT 
    search_term,
    campaign_name,
    COUNT(DISTINCT campaign_id) as campaign_count,
    SUM(impressions) as ads_impressions,
    SUM(clicks) as ads_clicks,
    SUM(cost) as ads_cost,
    SUM(orders) as ads_orders,
    SUM(sales) as ads_sales,
    ROUND(SAFE_DIVIDE(SUM(orders), SUM(clicks)) * 100, 2) as ads_conversion_rate,
    ROUND(SAFE_DIVIDE(SUM(sales), SUM(cost)), 2) as roas
  FROM `onyga-482313.OI.V_SRC_AmazonAds_SearchTerms`
  GROUP BY search_term, campaign_name
)
SELECT 
  'CAMPAIGN_EFFECTIVENESS' as analysis_type,
  sqp.Search_Query,
  sqp.sqp_purchases,
  sqp.sqp_conversion_rate,
  ads.campaign_name,
  ads.ads_impressions,
  ads.ads_clicks,
  ads.ads_orders,
  ads.ads_cost,
  ads.ads_sales,
  ads.ads_conversion_rate,
  ads.roas,
  CASE 
    WHEN ads.roas >= 4.0 THEN 'HIGH_ROI'
    WHEN ads.roas >= 2.0 THEN 'GOOD_ROI'
    WHEN ads.roas >= 1.0 THEN 'BREAK_EVEN'
    ELSE 'LOW_ROI'
  END as roi_tier
FROM sqp_top_20 sqp
LEFT JOIN ads_campaign_performance ads 
  ON LOWER(TRIM(sqp.Search_Query)) = LOWER(TRIM(ads.search_term))
ORDER BY sqp.sqp_purchases DESC, ads.roas DESC;

-- ==========================================
-- CORRELATION 5: OPPORTUNITY GAP ANALYSIS
-- ==========================================
-- Identify high-performing SQP queries with no/low ad spend (opportunities)
WITH sqp_opportunities AS (
  SELECT 
    Search_Query,
    SUM(Impressions_Total_Count) as sqp_impressions,
    SUM(Clicks_Total_Count) as sqp_clicks,
    SUM(Purchases_Total_Count) as sqp_purchases,
    ROUND(SAFE_DIVIDE(SUM(Purchases_Total_Count), SUM(Clicks_Total_Count)) * 100, 2) as sqp_conversion_rate
  FROM `onyga-482313.OI.SQP_ASIN_View_Simple_Week`
  GROUP BY Search_Query
  HAVING SUM(Purchases_Total_Count) >= 50  -- Minimum threshold
),
ads_coverage AS (
  SELECT 
    search_term,
    SUM(impressions) as ads_impressions,
    SUM(cost) as ads_cost,
    SUM(orders) as ads_orders
  FROM `onyga-482313.OI.V_SRC_AmazonAds_SearchTerms`
  GROUP BY search_term
)
SELECT 
  'OPPORTUNITY_GAP_ANALYSIS' as analysis_type,
  sqp.Search_Query,
  sqp.sqp_impressions,
  sqp.sqp_clicks,
  sqp.sqp_purchases,
  sqp.sqp_conversion_rate,
  COALESCE(ads.ads_impressions, 0) as ads_impressions,
  COALESCE(ads.ads_cost, 0) as ads_cost,
  COALESCE(ads.ads_orders, 0) as ads_orders,
  ROUND(SAFE_DIVIDE(COALESCE(ads.ads_impressions, 0), sqp.sqp_impressions) * 100, 2) as ads_coverage_pct,
  CASE 
    WHEN ads.ads_cost IS NULL OR ads.ads_cost = 0 THEN 'NO_ADS_INVESTMENT'
    WHEN ads.ads_impressions < sqp.sqp_impressions * 0.1 THEN 'UNDER_INVESTED'
    WHEN ads.ads_impressions >= sqp.sqp_impressions * 0.5 THEN 'WELL_COVERED'
    ELSE 'PARTIAL_COVERAGE'
  END as coverage_status,
  CASE 
    WHEN sqp.sqp_conversion_rate >= 20 AND (ads.ads_cost IS NULL OR ads.ads_cost = 0) THEN 'HIGH_PRIORITY_INVEST'
    WHEN sqp.sqp_conversion_rate >= 15 AND (ads.ads_cost IS NULL OR ads.ads_cost = 0) THEN 'MEDIUM_PRIORITY_INVEST'
    WHEN sqp.sqp_conversion_rate >= 10 AND ads.ads_impressions < sqp.sqp_impressions * 0.1 THEN 'INCREASE_SPEND'
    ELSE 'MONITOR'
  END as recommendation
FROM sqp_opportunities sqp
LEFT JOIN ads_coverage ads 
  ON LOWER(TRIM(sqp.Search_Query)) = LOWER(TRIM(ads.search_term))
WHERE ads.ads_cost IS NULL OR ads.ads_cost < 100  -- Low/no ad spend
ORDER BY sqp.sqp_conversion_rate DESC, sqp.sqp_purchases DESC
LIMIT 50;

-- ==========================================
-- CORRELATION 6: PERFORMANCE VALIDATION
-- ==========================================
-- Validate SQP insights with actual ad performance
WITH sqp_insights AS (
  SELECT 
    Search_Query,
    SUM(Impressions_Total_Count) as sqp_impressions,
    SUM(Clicks_Total_Count) as sqp_clicks,
    SUM(Purchases_Total_Count) as sqp_purchases,
    ROUND(SAFE_DIVIDE(SUM(Purchases_Total_Count), SUM(Clicks_Total_Count)) * 100, 2) as sqp_conversion_rate
  FROM `onyga-482313.OI.SQP_ASIN_View_Simple_Week`
  GROUP BY Search_Query
  HAVING SUM(Purchases_Total_Count) >= 100  -- Significant volume
),
ads_validation AS (
  SELECT 
    search_term,
    SUM(impressions) as ads_impressions,
    SUM(clicks) as ads_clicks,
    SUM(orders) as ads_orders,
    SUM(cost) as ads_cost,
    ROUND(SAFE_DIVIDE(SUM(orders), SUM(clicks)) * 100, 2) as ads_conversion_rate,
    ROUND(SAFE_DIVIDE(SUM(sales), SUM(cost)), 2) as roas
  FROM `onyga-482313.OI.V_SRC_AmazonAds_SearchTerms`
  GROUP BY search_term
)
SELECT 
  'VALIDATION_ANALYSIS' as analysis_type,
  sqp.Search_Query,
  sqp.sqp_conversion_rate,
  ads.ads_conversion_rate,
  ads.roas,
  ROUND(ads.ads_conversion_rate - sqp.sqp_conversion_rate, 2) as conversion_delta,
  CASE 
    WHEN ads.ads_conversion_rate > sqp.sqp_conversion_rate * 1.2 THEN 'ADS_OUTPERFORMING'
    WHEN ads.ads_conversion_rate < sqp.sqp_conversion_rate * 0.8 THEN 'ADS_UNDERPERFORMING'
    ELSE 'CONSISTENT_PERFORMANCE'
  END as performance_comparison,
  CASE 
    WHEN ads.roas >= 3.0 AND ads.ads_conversion_rate >= sqp.sqp_conversion_rate * 0.9 THEN 'VALIDATED_HIGH_VALUE'
    WHEN ads.roas >= 2.0 AND ads.ads_conversion_rate >= sqp.sqp_conversion_rate * 0.8 THEN 'VALIDATED_GOOD_VALUE'
    WHEN ads.roas < 1.5 THEN 'NEEDS_OPTIMIZATION'
    ELSE 'MONITOR'
  END as validation_status
FROM sqp_insights sqp
INNER JOIN ads_validation ads 
  ON LOWER(TRIM(sqp.Search_Query)) = LOWER(TRIM(ads.search_term))
ORDER BY sqp.sqp_purchases DESC
LIMIT 50;
