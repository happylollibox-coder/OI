-- =============================================
-- Week 51 Comparison Queries
-- Week: Dec 14-20, 2025
-- =============================================

-- Query 1: STG_SCD_WEEKLY - All Search Traffic (Organic + Paid)
-- =============================================
SELECT 
  'STG_SCD_WEEKLY' as source,
  'All Search Traffic (Organic + Paid)' as scope,
  week_start_date,
  week_end_date,
  Year,
  Week,
  COUNT(DISTINCT ASIN) as asin_count,
  SUM(impression_data_impression_count) as impressions,
  SUM(click_data_click_count) as clicks,
  SUM(purchase_data_search_traffic_sales_amount) as sales,
  SUM(purchase_data_purchase_count) as purchase_count
FROM `onyga-482313.OI.STG_SCD_WEEKLY`
WHERE week_start_date = '2025-12-14'
  AND week_end_date = '2025-12-20'
GROUP BY week_start_date, week_end_date, Year, Week;

-- =============================================
-- Query 2: V_SRC_AmazonAds_SearchTerms - Module #1 (Paid Search Only)
-- =============================================
SELECT 
  'V_SRC_AmazonAds_SearchTerms' as source,
  'Module #1 - Paid Search Only' as scope,
  DATE_TRUNC(DATE(date), WEEK(MONDAY)) as week_start_date,
  DATE_ADD(DATE_TRUNC(DATE(date), WEEK(MONDAY)), INTERVAL 6 DAY) as week_end_date,
  COUNT(*) as row_count,
  COUNT(DISTINCT date) as days_in_week,
  COUNT(DISTINCT campaign_id) as campaign_count,
  SUM(impressions) as impressions,
  SUM(clicks) as clicks,
  SUM(sales) as sales,
  SUM(orders) as orders,
  SUM(cost) as cost
FROM `onyga-482313.OI.V_SRC_AmazonAds_SearchTerms`
WHERE inferred_sales_module = 'Module #1 - Paid Search (Text Search Term)'
  AND date >= '2025-12-14' 
  AND date <= '2025-12-20'
  AND DATE_TRUNC(DATE(date), WEEK(MONDAY)) = '2025-12-15'
GROUP BY week_start_date;

-- =============================================
-- Query 3: Combined Comparison (Side by Side)
-- =============================================
WITH stg_data AS (
  SELECT 
    week_start_date,
    week_end_date,
    SUM(impression_data_impression_count) as stg_impressions,
    SUM(click_data_click_count) as stg_clicks,
    SUM(purchase_data_search_traffic_sales_amount) as stg_sales,
    COUNT(DISTINCT ASIN) as stg_asin_count
  FROM `onyga-482313.OI.STG_SCD_WEEKLY`
  WHERE week_start_date = '2025-12-14'
    AND week_end_date = '2025-12-20'
  GROUP BY week_start_date, week_end_date
),
st_data AS (
  SELECT 
    DATE_TRUNC(DATE(date), WEEK(MONDAY)) as week_start_date,
    SUM(impressions) as st_impressions,
    SUM(clicks) as st_clicks,
    SUM(sales) as st_sales,
    COUNT(*) as st_row_count
  FROM `onyga-482313.OI.V_SRC_AmazonAds_SearchTerms`
  WHERE inferred_sales_module = 'Module #1 - Paid Search (Text Search Term)'
    AND date >= '2025-12-14' 
    AND date <= '2025-12-20'
    AND DATE_TRUNC(DATE(date), WEEK(MONDAY)) = '2025-12-15'
  GROUP BY week_start_date
)
SELECT 
  'Week 51: Dec 14-20, 2025' as week_period,
  -- STG Metrics
  s1.stg_impressions,
  s1.stg_clicks,
  s1.stg_sales,
  s1.stg_asin_count,
  -- Module #1 Metrics
  s2.st_impressions,
  s2.st_clicks,
  s2.st_sales,
  s2.st_row_count,
  -- Comparisons (%)
  ROUND(100.0 * s2.st_impressions / NULLIF(s1.stg_impressions, 0), 2) as impressions_pct,
  ROUND(100.0 * s2.st_clicks / NULLIF(s1.stg_clicks, 0), 2) as clicks_pct,
  ROUND(100.0 * s2.st_sales / NULLIF(s1.stg_sales, 0), 2) as sales_pct,
  -- Is Module #1 Smaller?
  CASE WHEN s2.st_impressions < s1.stg_impressions THEN 'YES ✅' ELSE 'NO ❌' END as impressions_smaller,
  CASE WHEN s2.st_clicks < s1.stg_clicks THEN 'YES ✅' ELSE 'NO ❌' END as clicks_smaller,
  CASE WHEN s2.st_sales < s1.stg_sales THEN 'YES ✅' ELSE 'NO ❌' END as sales_smaller
FROM stg_data s1
CROSS JOIN st_data s2;

-- =============================================
-- Query 4: STG_SCD_WEEKLY - Detailed by ASIN
-- =============================================
SELECT 
  ASIN,
  week_start_date,
  week_end_date,
  impression_data_impression_count as impressions,
  click_data_click_count as clicks,
  purchase_data_search_traffic_sales_amount as sales,
  purchase_data_purchase_count as purchases
FROM `onyga-482313.OI.STG_SCD_WEEKLY`
WHERE week_start_date = '2025-12-14'
  AND week_end_date = '2025-12-20'
ORDER BY purchase_data_search_traffic_sales_amount DESC;

-- =============================================
-- Query 5: V_SRC_AmazonAds_SearchTerms - Sample rows for verification
-- =============================================
SELECT 
  date,
  campaign_id,
  campaign_name,
  search_term,
  inferred_sales_module,
  placement_type,
  impressions,
  clicks,
  sales,
  orders,
  cost
FROM `onyga-482313.OI.V_SRC_AmazonAds_SearchTerms`
WHERE inferred_sales_module = 'Module #1 - Paid Search (Text Search Term)'
  AND date >= '2025-12-14' 
  AND date <= '2025-12-20'
ORDER BY date DESC, sales DESC
LIMIT 50;
