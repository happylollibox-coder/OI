-- =============================================
-- Test: Connection between FACT_AMAZON_PERFORMANCE_DAILY and FACT_AMAZON_ADS using Ads_key
-- =============================================

-- Test 1: Count matching records by Ads_key
SELECT 
  'Test 1: Matching records count' AS test_name,
  COUNT(DISTINCT perf.Ads_key) AS unique_ads_keys_in_performance,
  COUNT(DISTINCT ads.Ads_key) AS unique_ads_keys_in_ads,
  COUNT(DISTINCT CASE WHEN ads.Ads_key IS NOT NULL THEN perf.Ads_key END) AS matching_ads_keys,
  COUNT(*) AS total_matching_rows
FROM `onyga-482313.OI.FACT_AMAZON_PERFORMANCE_DAILY` perf
LEFT JOIN `onyga-482313.OI.FACT_AMAZON_ADS` ads
  ON perf.Ads_key = ads.Ads_key
WHERE perf.Ads_key IS NOT NULL;

-- Test 2: Sample matching records with details
SELECT 
  'Test 2: Sample matching records' AS test_name,
  perf.DATE,
  perf.PURCHASED_ASIN,
  perf.advertised_asin,
  perf.Ads_key,
  perf.PURCHASED_ORDERS AS perf_orders,
  perf.PURCHASED_UNITS AS perf_units,
  perf.PURCHASED_AMOUNT_USD AS perf_sales,
  perf.Performance_TYPE,
  ads.impressions AS ads_impressions,
  ads.clicks AS ads_clicks,
  ads.orders AS ads_orders,
  ads.units AS ads_units,
  ads.sales AS ads_sales,
  ads.campaign_name,
  ads.campaign_type,
  ads.search_term
FROM `onyga-482313.OI.FACT_AMAZON_PERFORMANCE_DAILY` perf
INNER JOIN `onyga-482313.OI.FACT_AMAZON_ADS` ads
  ON perf.Ads_key = ads.Ads_key
WHERE perf.Ads_key IS NOT NULL
ORDER BY perf.DATE DESC, perf.PURCHASED_ASIN
LIMIT 20;

-- Test 3: Aggregated comparison by Ads_key
SELECT 
  'Test 3: Aggregated comparison by Ads_key' AS test_name,
  perf.Ads_key,
  COUNT(DISTINCT perf.DATE) AS perf_dates,
  COUNT(DISTINCT perf.PURCHASED_ASIN) AS perf_asins,
  SUM(perf.PURCHASED_ORDERS) AS total_perf_orders,
  SUM(perf.PURCHASED_UNITS) AS total_perf_units,
  SUM(perf.PURCHASED_AMOUNT_USD) AS total_perf_sales,
  COUNT(DISTINCT ads.date) AS ads_dates,
  COUNT(DISTINCT ads.search_term) AS ads_search_terms,
  SUM(ads.orders) AS total_ads_orders,
  SUM(ads.units) AS total_ads_units,
  SUM(ads.sales) AS total_ads_sales,
  SUM(ads.impressions) AS total_ads_impressions,
  SUM(ads.clicks) AS total_ads_clicks
FROM `onyga-482313.OI.FACT_AMAZON_PERFORMANCE_DAILY` perf
INNER JOIN `onyga-482313.OI.FACT_AMAZON_ADS` ads
  ON perf.Ads_key = ads.Ads_key
WHERE perf.Ads_key IS NOT NULL
GROUP BY perf.Ads_key
ORDER BY total_perf_orders DESC
LIMIT 20;

-- Test 4: Ads_keys in PERFORMANCE but not in ADS
SELECT 
  'Test 4: Ads_keys in PERFORMANCE but not in ADS' AS test_name,
  perf.Ads_key,
  COUNT(*) AS perf_row_count,
  COUNT(DISTINCT perf.DATE) AS perf_dates,
  COUNT(DISTINCT perf.PURCHASED_ASIN) AS perf_asins,
  SUM(perf.PURCHASED_ORDERS) AS total_perf_orders,
  SUM(perf.PURCHASED_UNITS) AS total_perf_units,
  perf.Performance_TYPE
FROM `onyga-482313.OI.FACT_AMAZON_PERFORMANCE_DAILY` perf
LEFT JOIN `onyga-482313.OI.FACT_AMAZON_ADS` ads
  ON perf.Ads_key = ads.Ads_key
WHERE perf.Ads_key IS NOT NULL
  AND ads.Ads_key IS NULL
GROUP BY perf.Ads_key, perf.Performance_TYPE
ORDER BY total_perf_orders DESC
LIMIT 20;

-- Test 5: Ads_keys in ADS but not in PERFORMANCE
SELECT 
  'Test 5: Ads_keys in ADS but not in PERFORMANCE' AS test_name,
  ads.Ads_key,
  COUNT(*) AS ads_row_count,
  COUNT(DISTINCT ads.date) AS ads_dates,
  COUNT(DISTINCT ads.search_term) AS ads_search_terms,
  SUM(ads.orders) AS total_ads_orders,
  SUM(ads.units) AS total_ads_units,
  SUM(ads.sales) AS total_ads_sales,
  ads.campaign_type
FROM `onyga-482313.OI.FACT_AMAZON_ADS` ads
LEFT JOIN `onyga-482313.OI.FACT_AMAZON_PERFORMANCE_DAILY` perf
  ON ads.Ads_key = perf.Ads_key
WHERE perf.Ads_key IS NULL
GROUP BY ads.Ads_key, ads.campaign_type
ORDER BY total_ads_orders DESC
LIMIT 20;

-- Test 6: Date-level matching summary
SELECT 
  'Test 6: Date-level matching summary' AS test_name,
  perf.DATE,
  COUNT(DISTINCT perf.Ads_key) AS perf_unique_ads_keys,
  COUNT(DISTINCT ads.Ads_key) AS ads_unique_ads_keys,
  COUNT(DISTINCT CASE WHEN ads.Ads_key IS NOT NULL THEN perf.Ads_key END) AS matching_ads_keys,
  COUNT(*) AS perf_rows_with_ads_key,
  SUM(perf.PURCHASED_ORDERS) AS perf_total_orders,
  SUM(ads.orders) AS ads_total_orders
FROM `onyga-482313.OI.FACT_AMAZON_PERFORMANCE_DAILY` perf
LEFT JOIN `onyga-482313.OI.FACT_AMAZON_ADS` ads
  ON perf.Ads_key = ads.Ads_key
WHERE perf.Ads_key IS NOT NULL
GROUP BY perf.DATE
ORDER BY perf.DATE DESC
LIMIT 30;
