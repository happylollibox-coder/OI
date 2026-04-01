-- Simple Diagnostic: Find the exact issue
-- Run each query separately to see where the problem is

-- Query 1: What's the actual total in FACT table right now?
SELECT 
  'Current FACT Total' AS check_type,
  SUM(sales) AS total_sales,
  SUM(CASE WHEN Performance_TYPE = 'Ads' THEN sales ELSE 0 END) AS ads_sales,
  SUM(CASE WHEN Performance_TYPE = 'Organic' THEN sales ELSE 0 END) AS organic_sales
FROM `onyga-482313.OI.FACT_AMAZON_PERFORMANCE_DAILY`
WHERE date = '2026-01-29';

-- Query 2: What should the Ads sales be? (Direct from STG_AMAZON_ADS)
SELECT 
  'Expected Ads Sales (from STG_AMAZON_ADS)' AS check_type,
  SUM(sales) AS total_ads_sales
FROM `onyga-482313.OI.STG_AMAZON_ADS`
WHERE date = '2026-01-29'
  AND most_advertised_asin_purchased IS NOT NULL;

-- Query 3: What's the source total? (STG_AMAZON_PERFORMANCE)
SELECT 
  'Source Total (STG_AMAZON_PERFORMANCE)' AS check_type,
  SUM(SALES_AMOUNT) AS total_sales
FROM `onyga-482313.OI.STG_AMAZON_PERFORMANCE`
WHERE date = '2026-01-29' AND IS_LOADED = TRUE;

-- Query 4: Check if there are duplicate rows in STG_AMAZON_ADS with same key but different sales
SELECT 
  'Duplicate Rows in STG_AMAZON_ADS' AS check_type,
  date,
  campaign_id,
  ad_group_id,
  keyword_id,
  search_term,
  most_advertised_asin_purchased,
  COUNT(*) AS duplicate_count,
  SUM(sales) AS total_sales,
  MAX(sales) AS max_sales,
  SUM(sales) - MAX(sales) AS lost_if_using_max
FROM `onyga-482313.OI.STG_AMAZON_ADS`
WHERE date = '2026-01-29'
  AND most_advertised_asin_purchased IS NOT NULL
GROUP BY 
  date, campaign_id, ad_group_id, keyword_id, search_term, most_advertised_asin_purchased
HAVING COUNT(*) > 1
ORDER BY lost_if_using_max DESC
LIMIT 20;

-- Query 5: Simulate what happens in the SP - UNPIVOT then GROUP BY with SUM
WITH unpivoted AS (
  SELECT 
    date,
    campaign_id,
    campaign_name,
    campaign_type,
    inferred_sales_module,
    ad_group_id,
    keyword_id,
    ad_keyword_status,
    targeting,
    search_term,
    placement_type,
    advertised_asins,
    advertised_asins_count,
    _fivetran_synced,
    source_table,
    asin,
    CASE WHEN measure_type = 'impressions' THEN impressions ELSE NULL END AS impressions,
    CASE WHEN measure_type = 'clicks' THEN clicks ELSE NULL END AS clicks,
    CASE WHEN measure_type = 'purchased' THEN orders ELSE NULL END AS orders,
    CASE WHEN measure_type = 'purchased' THEN units ELSE NULL END AS units,
    CASE WHEN measure_type = 'purchased' THEN cost ELSE NULL END AS cost,
    CASE WHEN measure_type = 'purchased' THEN sales ELSE NULL END AS sales
  FROM `onyga-482313.OI.STG_AMAZON_ADS`
  UNPIVOT (asin FOR measure_type IN (
    most_advertised_asin_impressions AS 'impressions',
    most_advertised_asin_clicks AS 'clicks',
    most_advertised_asin_purchased AS 'purchased'
  ))
  WHERE date = '2026-01-29'
    AND asin IS NOT NULL
)
SELECT 
  'Simulated SP Result (with SUM)' AS check_type,
  SUM(COALESCE(sales, 0)) AS total_sales
FROM (
  SELECT 
    date,
    campaign_id,
    campaign_name,
    campaign_type,
    inferred_sales_module,
    ad_group_id,
    keyword_id,
    ad_keyword_status,
    targeting,
    search_term,
    placement_type,
    advertised_asins,
    advertised_asins_count,
    asin,
    _fivetran_synced,
    source_table,
    MAX(impressions) AS impressions,
    MAX(clicks) AS clicks,
    MAX(orders) AS orders,
    MAX(units) AS units,
    MAX(cost) AS cost,
    SUM(COALESCE(sales, 0)) AS sales
  FROM unpivoted
  GROUP BY 
    date, campaign_id, campaign_name, campaign_type, inferred_sales_module,
    ad_group_id, keyword_id, ad_keyword_status, targeting, search_term,
    placement_type, advertised_asins, advertised_asins_count, asin,
    _fivetran_synced, source_table
);

-- Query 6: Compare actual FACT Ads sales vs expected
SELECT 
  'Ads Sales Comparison' AS check_type,
  (SELECT SUM(sales) FROM `onyga-482313.OI.FACT_AMAZON_PERFORMANCE_DAILY` 
   WHERE date = '2026-01-29' AND Performance_TYPE = 'Ads') AS fact_ads_sales,
  (SELECT SUM(sales) FROM `onyga-482313.OI.STG_AMAZON_ADS` 
   WHERE date = '2026-01-29' AND most_advertised_asin_purchased IS NOT NULL) AS stg_ads_sales,
  (SELECT SUM(sales) FROM `onyga-482313.OI.FACT_AMAZON_PERFORMANCE_DAILY` 
   WHERE date = '2026-01-29' AND Performance_TYPE = 'Ads') - 
  (SELECT SUM(sales) FROM `onyga-482313.OI.STG_AMAZON_ADS` 
   WHERE date = '2026-01-29' AND most_advertised_asin_purchased IS NOT NULL) AS difference;
