-- =============================================
-- Comparison: V_SRC_sales_and_traffic_business_sku_report_daily vs STG_AMAZON_ADS
-- Per date and child_asin
-- =============================================
--
-- Purpose: Compare sales/traffic measures from Seller Central with Amazon Ads performance
--          to understand attribution and overlap
-- 
-- Key Findings:
-- - "Both" data source: ASINs that appear in both datasets (891 records, 10 unique ASINs)
-- - "Ads Only": ASINs only in Amazon Ads (51 records, 9 unique ASINs)
-- - "Sales Only": ASINs only in Sales & Traffic (2,462 records, 22 unique ASINs)
--
-- Attribution Insights:
-- - For "Both" records: ads_orders represent 0-450% of total sales_orders (varies by ASIN/date)
-- - Some ASINs show ads_orders > sales_orders (attribution window differences)
-- - ads_sales represent 0-1179% of total sales_amount (some extreme values due to attribution)
--
-- =============================================

-- DETAILED COMPARISON: All records with both data sources
WITH 
-- Aggregate STG_AMAZON_ADS by date and ASIN (split comma-separated advertised_asins)
stg_amazon_ads_by_asin AS (
  SELECT 
    date,
    TRIM(asin) AS asin,
    SUM(clicks) AS ads_clicks,
    SUM(impressions) AS ads_impressions,
    SUM(cost) AS ads_cost,
    SUM(orders) AS ads_orders,
    SUM(units) AS ads_units,
    SUM(sales) AS ads_sales,
    COUNT(*) AS ads_record_count
  FROM `onyga-482313.OI.STG_AMAZON_ADS`,
  UNNEST(SPLIT(COALESCE(advertised_asins, ''), ',')) AS asin
  WHERE advertised_asins IS NOT NULL
    AND advertised_asins != ''
    AND TRIM(asin) != ''
  GROUP BY date, TRIM(asin)
),
-- Get sales and traffic data
sales_traffic AS (
  SELECT 
    child_asin,
    date,
    SALES_QUANTITY,
    SALES_AMOUNT,
    SALES_ORDERS,
    CLICKS_DAILY_UNIQUE,
    CLICKS AS traffic_clicks
  FROM `onyga-482313.OI.V_SRC_sales_and_traffic_business_sku_report_daily`
  WHERE child_asin IS NOT NULL
)
-- Full outer join to compare both sides
SELECT 
  COALESCE(st.child_asin, ads.asin) AS asin,
  COALESCE(st.date, ads.date) AS date,
  
  -- Sales & Traffic measures
  st.SALES_QUANTITY AS sales_quantity,
  st.SALES_AMOUNT AS sales_amount,
  st.SALES_ORDERS AS sales_orders,
  st.CLICKS_DAILY_UNIQUE AS traffic_sessions,
  st.traffic_clicks AS traffic_page_views,
  
  -- Amazon Ads measures
  ads.ads_clicks,
  ads.ads_impressions,
  ads.ads_cost,
  ads.ads_orders,
  ads.ads_units,
  ads.ads_sales,
  ads.ads_record_count,
  
  -- Comparison flags
  CASE WHEN st.child_asin IS NULL THEN 'Ads Only' 
       WHEN ads.asin IS NULL THEN 'Sales Only'
       ELSE 'Both' END AS data_source,
  
  -- Calculate ratios/differences
  CASE WHEN st.SALES_ORDERS > 0 
       THEN ROUND(ads.ads_orders * 100.0 / NULLIF(st.SALES_ORDERS, 0), 2)
       ELSE NULL END AS ads_orders_pct_of_total,
  
  CASE WHEN st.SALES_AMOUNT > 0 
       THEN ROUND(ads.ads_sales * 100.0 / NULLIF(st.SALES_AMOUNT, 0), 2)
       ELSE NULL END AS ads_sales_pct_of_total,
  
  CASE WHEN ads.ads_clicks > 0 
       THEN ROUND(st.traffic_clicks * 100.0 / NULLIF(ads.ads_clicks, 0), 2)
       ELSE NULL END AS traffic_clicks_pct_of_ads_clicks

FROM sales_traffic st
FULL OUTER JOIN stg_amazon_ads_by_asin ads
  ON st.child_asin = ads.asin
  AND st.date = ads.date

ORDER BY date DESC, asin;

-- =============================================
-- SUMMARY STATISTICS
-- =============================================

WITH 
stg_amazon_ads_by_asin AS (
  SELECT 
    date,
    TRIM(asin) AS asin,
    SUM(clicks) AS ads_clicks,
    SUM(impressions) AS ads_impressions,
    SUM(cost) AS ads_cost,
    SUM(orders) AS ads_orders,
    SUM(units) AS ads_units,
    SUM(sales) AS ads_sales
  FROM `onyga-482313.OI.STG_AMAZON_ADS`,
  UNNEST(SPLIT(COALESCE(advertised_asins, ''), ',')) AS asin
  WHERE advertised_asins IS NOT NULL
    AND advertised_asins != ''
    AND TRIM(asin) != ''
  GROUP BY date, TRIM(asin)
),
sales_traffic AS (
  SELECT 
    child_asin,
    date,
    SALES_QUANTITY,
    SALES_AMOUNT,
    SALES_ORDERS,
    CLICKS_DAILY_UNIQUE,
    CLICKS AS traffic_clicks
  FROM `onyga-482313.OI.V_SRC_sales_and_traffic_business_sku_report_daily`
  WHERE child_asin IS NOT NULL
),
comparison AS (
  SELECT 
    COALESCE(st.child_asin, ads.asin) AS asin,
    COALESCE(st.date, ads.date) AS date,
    st.SALES_QUANTITY,
    st.SALES_AMOUNT,
    st.SALES_ORDERS,
    st.traffic_clicks,
    ads.ads_clicks,
    ads.ads_impressions,
    ads.ads_cost,
    ads.ads_orders,
    ads.ads_sales,
    CASE WHEN st.child_asin IS NULL THEN 'Ads Only' 
         WHEN ads.asin IS NULL THEN 'Sales Only'
         ELSE 'Both' END AS data_source
  FROM sales_traffic st
  FULL OUTER JOIN stg_amazon_ads_by_asin ads
    ON st.child_asin = ads.asin
    AND st.date = ads.date
)
SELECT 
  data_source,
  COUNT(DISTINCT asin) AS unique_asins,
  COUNT(DISTINCT date) AS unique_dates,
  COUNT(*) AS total_records,
  
  -- Sales & Traffic totals
  SUM(SALES_QUANTITY) AS total_sales_quantity,
  SUM(SALES_AMOUNT) AS total_sales_amount,
  SUM(SALES_ORDERS) AS total_sales_orders,
  SUM(traffic_clicks) AS total_traffic_clicks,
  
  -- Amazon Ads totals
  SUM(ads_clicks) AS total_ads_clicks,
  SUM(ads_impressions) AS total_ads_impressions,
  SUM(ads_cost) AS total_ads_cost,
  SUM(ads_orders) AS total_ads_orders,
  SUM(ads_sales) AS total_ads_sales,
  
  -- Averages
  ROUND(AVG(SALES_QUANTITY), 2) AS avg_sales_quantity,
  ROUND(AVG(SALES_AMOUNT), 2) AS avg_sales_amount,
  ROUND(AVG(ads_clicks), 2) AS avg_ads_clicks,
  ROUND(AVG(ads_impressions), 2) AS avg_ads_impressions

FROM comparison
GROUP BY data_source
ORDER BY data_source;

-- =============================================
-- TOP ASINS BY ATTRIBUTION (Both data sources)
-- =============================================

WITH 
stg_amazon_ads_by_asin AS (
  SELECT 
    date,
    TRIM(asin) AS asin,
    SUM(clicks) AS ads_clicks,
    SUM(orders) AS ads_orders,
    SUM(sales) AS ads_sales
  FROM `onyga-482313.OI.STG_AMAZON_ADS`,
  UNNEST(SPLIT(COALESCE(advertised_asins, ''), ',')) AS asin
  WHERE advertised_asins IS NOT NULL
    AND advertised_asins != ''
    AND TRIM(asin) != ''
  GROUP BY date, TRIM(asin)
),
sales_traffic AS (
  SELECT 
    child_asin,
    date,
    SALES_QUANTITY,
    SALES_AMOUNT,
    SALES_ORDERS
  FROM `onyga-482313.OI.V_SRC_sales_and_traffic_business_sku_report_daily`
  WHERE child_asin IS NOT NULL
)
SELECT 
  st.child_asin AS asin,
  st.date,
  st.SALES_QUANTITY,
  st.SALES_AMOUNT,
  st.SALES_ORDERS AS sales_orders,
  ads.ads_orders,
  ads.ads_sales,
  ROUND(ads.ads_orders * 100.0 / NULLIF(st.SALES_ORDERS, 0), 2) AS ads_orders_pct,
  ROUND(ads.ads_sales * 100.0 / NULLIF(st.SALES_AMOUNT, 0), 2) AS ads_sales_pct
FROM sales_traffic st
INNER JOIN stg_amazon_ads_by_asin ads
  ON st.child_asin = ads.asin
  AND st.date = ads.date
WHERE st.SALES_ORDERS > 0 OR ads.ads_orders > 0
ORDER BY st.date DESC, ads.ads_orders DESC;
