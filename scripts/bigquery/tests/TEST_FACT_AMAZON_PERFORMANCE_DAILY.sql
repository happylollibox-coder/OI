-- =============================================
-- Test Script for SP_LOAD_FACT_AMAZON_PERFORMANCE_DAILY
-- =============================================
--
-- Purpose: Comprehensive tests for the fact table loading procedure
-- Tests:
-- 1. Procedure execution
-- 2. Record counts by Performance_TYPE
-- 3. Data quality checks
-- 4. Delta calculations
-- 5. Negative delta handling
-- 6. Missing organic data handling
--
-- =============================================

-- Test 1: Run the procedure
SELECT 'Test 1: Running SP_LOAD_FACT_AMAZON_PERFORMANCE_DAILY' AS test_name;
CALL `onyga-482313.OI.SP_LOAD_FACT_AMAZON_PERFORMANCE_DAILY`();

-- Test 2: Check record counts by Performance_TYPE
SELECT 
  'Test 2: Record counts by Performance_TYPE' AS test_name,
  Performance_TYPE,
  COUNT(*) AS record_count,
  COUNT(DISTINCT date) AS unique_dates,
  MIN(date) AS min_date,
  MAX(date) AS max_date
FROM `onyga-482313.OI.FACT_AMAZON_PERFORMANCE_DAILY`
GROUP BY Performance_TYPE
ORDER BY Performance_TYPE;

-- Test 3: Check DATA_QUALITY_STATUS distribution
SELECT 
  'Test 3: DATA_QUALITY_STATUS distribution' AS test_name,
  DATA_QUALITY_STATUS,
  COUNT(*) AS record_count
FROM `onyga-482313.OI.FACT_AMAZON_PERFORMANCE_DAILY`
GROUP BY DATA_QUALITY_STATUS
ORDER BY record_count DESC;

-- Test 4: Verify Ads records have correct fields
SELECT 
  'Test 4: Ads records validation' AS test_name,
  COUNT(*) AS total_ads_records,
  COUNT(CASE WHEN Performance_TYPE = 'Ads' THEN 1 END) AS ads_type_count,
  COUNT(CASE WHEN data_SOURCE = 'STG_AMAZON_ADS' THEN 1 END) AS ads_source_count,
  COUNT(CASE WHEN campaign_id IS NOT NULL THEN 1 END) AS has_campaign_id,
  COUNT(CASE WHEN ad_group_id IS NOT NULL THEN 1 END) AS has_ad_group_id,
  COUNT(CASE WHEN keyword_id IS NOT NULL THEN 1 END) AS has_keyword_id,
  COUNT(CASE WHEN cost IS NOT NULL AND cost > 0 THEN 1 END) AS has_cost,
  COUNT(CASE WHEN CLICKS_DAILY_UNIQUE IS NULL THEN 1 END) AS clicks_daily_unique_null
FROM `onyga-482313.OI.FACT_AMAZON_PERFORMANCE_DAILY`
WHERE Performance_TYPE = 'Ads';

-- Test 5: Verify Organic records have correct fields
SELECT 
  'Test 5: Organic records validation' AS test_name,
  COUNT(*) AS total_organic_records,
  COUNT(CASE WHEN Performance_TYPE = 'Organic' THEN 1 END) AS organic_type_count,
  COUNT(CASE WHEN data_SOURCE = 'STG_AMAZON_PERFORMANCE' THEN 1 END) AS perf_source_count,
  COUNT(CASE WHEN campaign_id IS NULL THEN 1 END) AS campaign_id_null,
  COUNT(CASE WHEN ad_group_id IS NULL THEN 1 END) AS ad_group_id_null,
  COUNT(CASE WHEN keyword_id IS NULL THEN 1 END) AS keyword_id_null,
  COUNT(CASE WHEN cost = 0 THEN 1 END) AS cost_zero,
  COUNT(CASE WHEN most_advertised_asin_purchased IS NOT NULL OR most_advertised_asin_clicks IS NOT NULL THEN 1 END) AS has_asin
FROM `onyga-482313.OI.FACT_AMAZON_PERFORMANCE_DAILY`
WHERE Performance_TYPE = 'Organic';

-- Test 6: Check for negative deltas (should be 0)
SELECT 
  'Test 6: Negative delta check' AS test_name,
  COUNT(*) AS records_with_negative_deltas,
  COUNT(CASE WHEN orders < 0 THEN 1 END) AS negative_orders,
  COUNT(CASE WHEN units < 0 THEN 1 END) AS negative_units,
  COUNT(CASE WHEN sales < 0 THEN 1 END) AS negative_sales,
  COUNT(CASE WHEN clicks < 0 THEN 1 END) AS negative_clicks,
  COUNT(CASE WHEN CLICKS_DAILY_UNIQUE < 0 THEN 1 END) AS negative_clicks_daily_unique
FROM `onyga-482313.OI.FACT_AMAZON_PERFORMANCE_DAILY`
WHERE Performance_TYPE = 'Organic';

-- Test 7: Sample sales delta records
SELECT 
  'Test 7: Sample sales delta records' AS test_name,
  date,
  most_advertised_asin_purchased AS asin,
  orders,
  units,
  sales,
  cost,
  DATA_QUALITY_STATUS,
  Performance_TYPE
FROM `onyga-482313.OI.FACT_AMAZON_PERFORMANCE_DAILY`
WHERE Performance_TYPE = 'Organic'
  AND (orders > 0 OR units > 0 OR sales > 0)
ORDER BY date DESC, sales DESC
LIMIT 10;

-- Test 8: Sample clicks delta records
SELECT 
  'Test 8: Sample clicks delta records' AS test_name,
  date,
  most_advertised_asin_clicks AS asin,
  clicks,
  CLICKS_DAILY_UNIQUE,
  cost,
  DATA_QUALITY_STATUS,
  Performance_TYPE
FROM `onyga-482313.OI.FACT_AMAZON_PERFORMANCE_DAILY`
WHERE Performance_TYPE = 'Organic'
  AND (clicks > 0 OR CLICKS_DAILY_UNIQUE > 0)
ORDER BY date DESC, clicks DESC
LIMIT 10;

-- Test 9: Check dates with missing organic data
SELECT 
  'Test 9: Dates with missing organic data' AS test_name,
  date,
  COUNT(*) AS total_records,
  COUNT(CASE WHEN DATA_QUALITY_STATUS LIKE '%Missing Organic data%' THEN 1 END) AS missing_data_records,
  COUNT(CASE WHEN Performance_TYPE = 'Ads' THEN 1 END) AS ads_records,
  COUNT(CASE WHEN Performance_TYPE = 'Organic' THEN 1 END) AS organic_records
FROM `onyga-482313.OI.FACT_AMAZON_PERFORMANCE_DAILY`
WHERE DATA_QUALITY_STATUS LIKE '%Missing Organic data%'
GROUP BY date
ORDER BY date DESC
LIMIT 10;

-- Test 10: Check dates with ads greater than total warnings
SELECT 
  'Test 10: Dates with ads > total warnings' AS test_name,
  date,
  COUNT(*) AS total_records,
  COUNT(CASE WHEN DATA_QUALITY_STATUS LIKE '%in ads greater than total%' THEN 1 END) AS warning_records
FROM `onyga-482313.OI.FACT_AMAZON_PERFORMANCE_DAILY`
WHERE DATA_QUALITY_STATUS LIKE '%in ads greater than total%'
GROUP BY date
ORDER BY date DESC
LIMIT 10;

-- Test 11: Verify delta calculations for a specific ASIN and date
SELECT 
  'Test 11: Delta calculation verification (sample)' AS test_name,
  fact.date,
  fact.most_advertised_asin_purchased AS asin,
  fact.orders AS organic_units,
  fact.units AS organic_units,
  fact.sales AS organic_sales,
  COALESCE(ads_agg.ads_orders, 0) AS ads_orders,
  COALESCE(ads_agg.ads_units, 0) AS ads_units,
  COALESCE(ads_agg.ads_sales, 0) AS ads_sales,
  COALESCE(perf.SALES_ORDERS, 0) AS perf_orders,
  COALESCE(perf.SALES_QUANTITY, 0) AS perf_quantity,
  COALESCE(perf.SALES_AMOUNT, 0) AS perf_amount,
  fact.DATA_QUALITY_STATUS
FROM `onyga-482313.OI.FACT_AMAZON_PERFORMANCE_DAILY` fact
LEFT JOIN (
  SELECT 
    most_advertised_asin_purchased AS asin,
    date,
    SUM(orders) AS ads_orders,
    SUM(units) AS ads_units,
    SUM(sales) AS ads_sales
  FROM `onyga-482313.OI.STG_AMAZON_ADS`
  WHERE most_advertised_asin_purchased IS NOT NULL
  GROUP BY most_advertised_asin_purchased, date
) ads_agg
  ON fact.most_advertised_asin_purchased = ads_agg.asin
  AND fact.date = ads_agg.date
LEFT JOIN `onyga-482313.OI.STG_AMAZON_PERFORMANCE` perf
  ON fact.most_advertised_asin_purchased = perf.child_asin
  AND fact.date = perf.date
WHERE fact.Performance_TYPE = 'Organic'
  AND fact.most_advertised_asin_purchased IS NOT NULL
ORDER BY fact.date DESC, fact.sales DESC
LIMIT 5;

-- Test 12: Summary statistics
SELECT 
  'Test 12: Summary statistics' AS test_name,
  COUNT(*) AS total_records,
  COUNT(DISTINCT date) AS unique_dates,
  COUNT(DISTINCT CASE WHEN Performance_TYPE = 'Ads' THEN campaign_id END) AS unique_campaigns,
  COUNT(DISTINCT CASE WHEN Performance_TYPE = 'Organic' THEN most_advertised_asin_purchased END) AS unique_organic_asins_purchased,
  COUNT(DISTINCT CASE WHEN Performance_TYPE = 'Organic' THEN most_advertised_asin_clicks END) AS unique_organic_asins_clicks,
  SUM(CASE WHEN Performance_TYPE = 'Ads' THEN cost ELSE 0 END) AS total_ads_cost,
  SUM(CASE WHEN Performance_TYPE = 'Organic' THEN orders ELSE 0 END) AS total_organic_units,
  SUM(CASE WHEN Performance_TYPE = 'Organic' THEN units ELSE 0 END) AS total_organic_units,
  SUM(CASE WHEN Performance_TYPE = 'Organic' THEN sales ELSE 0 END) AS total_organic_sales,
  SUM(CASE WHEN Performance_TYPE = 'Organic' THEN clicks ELSE 0 END) AS total_organic_clicks
FROM `onyga-482313.OI.FACT_AMAZON_PERFORMANCE_DAILY`;
