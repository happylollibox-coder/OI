-- =============================================
-- Diagnostic Query: Sales Discrepancy for Jan 29, 2026
-- =============================================
-- Expected: $3,069 USD
-- Actual in FACT_AMAZON_PERFORMANCE_DAILY: $3,614.6
-- Difference: $545.6
-- =============================================

-- 1. Check total sales in FACT_AMAZON_PERFORMANCE_DAILY for Jan 29, 2026
SELECT 
  'FACT_AMAZON_PERFORMANCE_DAILY Total' AS source,
  DATE('2026-01-29') AS date,
  SUM(sales) AS total_sales,
  COUNT(*) AS record_count,
  COUNT(DISTINCT most_advertised_asin) AS distinct_asins,
  COUNT(DISTINCT campaign_id) AS distinct_campaigns
FROM `onyga-482313.OI.FACT_AMAZON_PERFORMANCE_DAILY`
WHERE date = '2026-01-29';

-- 2. Break down by Performance_TYPE (Ads vs Organic)
SELECT 
  'FACT_AMAZON_PERFORMANCE_DAILY by Type' AS source,
  Performance_TYPE,
  SUM(sales) AS total_sales,
  COUNT(*) AS record_count,
  COUNT(DISTINCT most_advertised_asin) AS distinct_asins
FROM `onyga-482313.OI.FACT_AMAZON_PERFORMANCE_DAILY`
WHERE date = '2026-01-29'
GROUP BY Performance_TYPE
ORDER BY Performance_TYPE;

-- 3. Check for duplicate records (same date, ASIN, campaign, etc.)
SELECT 
  'Duplicate Check' AS check_type,
  date,
  most_advertised_asin,
  campaign_id,
  ad_group_id,
  keyword_id,
  search_term,
  Performance_TYPE,
  COUNT(*) AS duplicate_count,
  SUM(sales) AS total_sales_for_group
FROM `onyga-482313.OI.FACT_AMAZON_PERFORMANCE_DAILY`
WHERE date = '2026-01-29'
GROUP BY 
  date,
  most_advertised_asin,
  campaign_id,
  ad_group_id,
  keyword_id,
  search_term,
  Performance_TYPE
HAVING COUNT(*) > 1
ORDER BY duplicate_count DESC, total_sales_for_group DESC;

-- 4. Check source data: STG_AMAZON_ADS for Jan 29, 2026
SELECT 
  'STG_AMAZON_ADS Total' AS source,
  DATE('2026-01-29') AS date,
  SUM(sales) AS total_sales,
  COUNT(*) AS record_count,
  COUNT(DISTINCT most_advertised_asin_purchased) AS distinct_asins_purchased,
  COUNT(DISTINCT campaign_id) AS distinct_campaigns
FROM `onyga-482313.OI.STG_AMAZON_ADS`
WHERE date = '2026-01-29';

-- 5. Check STG_AMAZON_PERFORMANCE for Jan 29, 2026
SELECT 
  'STG_AMAZON_PERFORMANCE Total' AS source,
  DATE('2026-01-29') AS date,
  SUM(SALES_AMOUNT) AS total_sales_amount,
  SUM(SALES_QUANTITY) AS total_quantity,
  SUM(SALES_ORDERS) AS total_orders,
  COUNT(*) AS record_count,
  COUNT(DISTINCT child_asin) AS distinct_asins,
  SUM(CASE WHEN IS_LOADED = TRUE THEN 1 ELSE 0 END) AS loaded_records,
  SUM(CASE WHEN IS_LOADED = FALSE THEN 1 ELSE 0 END) AS not_loaded_records
FROM `onyga-482313.OI.STG_AMAZON_PERFORMANCE`
WHERE date = '2026-01-29';

-- 6. Check Ads sales aggregation (how it's calculated in the SP)
SELECT 
  'Ads Sales Aggregation' AS source,
  DATE('2026-01-29') AS date,
  most_advertised_asin_purchased AS asin,
  SUM(sales) AS ads_sales,
  SUM(orders) AS ads_orders,
  SUM(units) AS ads_units,
  COUNT(*) AS record_count
FROM `onyga-482313.OI.STG_AMAZON_ADS`
WHERE date = '2026-01-29'
  AND most_advertised_asin_purchased IS NOT NULL
GROUP BY most_advertised_asin_purchased
ORDER BY ads_sales DESC;

-- 7. Check Organic delta calculation (Performance - Ads)
WITH ads_sales_agg AS (
  SELECT 
    most_advertised_asin_purchased AS asin,
    date,
    SUM(orders) AS ads_orders,
    SUM(units) AS ads_units,
    SUM(sales) AS ads_sales
  FROM `onyga-482313.OI.STG_AMAZON_ADS`
  WHERE date = '2026-01-29'
    AND most_advertised_asin_purchased IS NOT NULL
  GROUP BY most_advertised_asin_purchased, date
)
SELECT 
  'Organic Delta Calculation' AS source,
  perf.child_asin AS asin,
  perf.date,
  perf.SALES_AMOUNT AS total_sales,
  COALESCE(ads.ads_sales, 0) AS ads_sales,
  GREATEST(0, perf.SALES_AMOUNT - COALESCE(ads.ads_sales, 0)) AS organic_delta_sales,
  perf.SALES_AMOUNT - COALESCE(ads.ads_sales, 0) AS raw_delta,
  CASE 
    WHEN perf.SALES_AMOUNT - COALESCE(ads.ads_sales, 0) < 0 THEN 'Negative Delta'
    WHEN COALESCE(ads.ads_sales, 0) > perf.SALES_AMOUNT THEN 'Ads > Total'
    ELSE 'OK'
  END AS delta_status
FROM `onyga-482313.OI.STG_AMAZON_PERFORMANCE` perf
LEFT JOIN ads_sales_agg ads
  ON perf.child_asin = ads.asin
  AND perf.date = ads.date
WHERE perf.date = '2026-01-29'
  AND (perf.SALES_QUANTITY > 0 OR perf.SALES_AMOUNT > 0 OR perf.SALES_ORDERS > 0)
  AND perf.IS_LOADED = TRUE
ORDER BY organic_delta_sales DESC;

-- 8. Check if UNPIVOT is creating duplicates in Ads records
-- This simulates the UNPIVOT logic from the SP
SELECT 
  'UNPIVOT Simulation' AS source,
  date,
  asin,
  measure_type,
  SUM(sales) AS sales,
  COUNT(*) AS record_count
FROM (
  SELECT 
    date,
    most_advertised_asin_impressions AS asin,
    'impressions' AS measure_type,
    NULL AS sales
  FROM `onyga-482313.OI.STG_AMAZON_ADS`
  WHERE date = '2026-01-29'
    AND most_advertised_asin_impressions IS NOT NULL
  
  UNION ALL
  
  SELECT 
    date,
    most_advertised_asin_clicks AS asin,
    'clicks' AS measure_type,
    NULL AS sales
  FROM `onyga-482313.OI.STG_AMAZON_ADS`
  WHERE date = '2026-01-29'
    AND most_advertised_asin_clicks IS NOT NULL
  
  UNION ALL
  
  SELECT 
    date,
    most_advertised_asin_purchased AS asin,
    'purchased' AS measure_type,
    sales
  FROM `onyga-482313.OI.STG_AMAZON_ADS`
  WHERE date = '2026-01-29'
    AND most_advertised_asin_purchased IS NOT NULL
)
GROUP BY date, asin, measure_type
ORDER BY asin, measure_type;

-- 9. Check the final grouped result after UNPIVOT (what should be in FACT table)
SELECT 
  'Expected Ads Sales After Grouping' AS source,
  date,
  asin AS most_advertised_asin,
  SUM(CASE WHEN measure_type = 'purchased' THEN sales ELSE 0 END) AS total_sales,
  COUNT(*) AS unpivot_rows,
  COUNT(DISTINCT measure_type) AS measure_types
FROM (
  SELECT 
    date,
    most_advertised_asin_impressions AS asin,
    'impressions' AS measure_type,
    NULL AS sales
  FROM `onyga-482313.OI.STG_AMAZON_ADS`
  WHERE date = '2026-01-29'
    AND most_advertised_asin_impressions IS NOT NULL
  
  UNION ALL
  
  SELECT 
    date,
    most_advertised_asin_clicks AS asin,
    'clicks' AS measure_type,
    NULL AS sales
  FROM `onyga-482313.OI.STG_AMAZON_ADS`
  WHERE date = '2026-01-29'
    AND most_advertised_asin_clicks IS NOT NULL
  
  UNION ALL
  
  SELECT 
    date,
    most_advertised_asin_purchased AS asin,
    'purchased' AS measure_type,
    sales
  FROM `onyga-482313.OI.STG_AMAZON_ADS`
  WHERE date = '2026-01-29'
    AND most_advertised_asin_purchased IS NOT NULL
)
GROUP BY date, asin
HAVING SUM(CASE WHEN measure_type = 'purchased' THEN sales ELSE 0 END) > 0
ORDER BY total_sales DESC;

-- 10. Compare actual FACT table vs expected
WITH expected_ads AS (
  SELECT 
    date,
    asin AS most_advertised_asin,
    SUM(CASE WHEN measure_type = 'purchased' THEN sales ELSE 0 END) AS expected_ads_sales
  FROM (
    SELECT 
      date,
      most_advertised_asin_impressions AS asin,
      'impressions' AS measure_type,
      NULL AS sales
    FROM `onyga-482313.OI.STG_AMAZON_ADS`
    WHERE date = '2026-01-29'
      AND most_advertised_asin_impressions IS NOT NULL
    
    UNION ALL
    
    SELECT 
      date,
      most_advertised_asin_clicks AS asin,
      'clicks' AS measure_type,
      NULL AS sales
    FROM `onyga-482313.OI.STG_AMAZON_ADS`
    WHERE date = '2026-01-29'
      AND most_advertised_asin_clicks IS NOT NULL
    
    UNION ALL
    
    SELECT 
      date,
      most_advertised_asin_purchased AS asin,
      'purchased' AS measure_type,
      sales
    FROM `onyga-482313.OI.STG_AMAZON_ADS`
    WHERE date = '2026-01-29'
      AND most_advertised_asin_purchased IS NOT NULL
  )
  GROUP BY date, asin
),
actual_fact AS (
  SELECT 
    date,
    most_advertised_asin,
    SUM(CASE WHEN Performance_TYPE = 'Ads' THEN sales ELSE 0 END) AS actual_ads_sales,
    SUM(CASE WHEN Performance_TYPE = 'Organic' THEN sales ELSE 0 END) AS actual_organic_sales,
    SUM(sales) AS actual_total_sales
  FROM `onyga-482313.OI.FACT_AMAZON_PERFORMANCE_DAILY`
  WHERE date = '2026-01-29'
  GROUP BY date, most_advertised_asin
)
SELECT 
  'Comparison' AS source,
  COALESCE(e.most_advertised_asin, a.most_advertised_asin) AS asin,
  COALESCE(e.expected_ads_sales, 0) AS expected_ads_sales,
  COALESCE(a.actual_ads_sales, 0) AS actual_ads_sales,
  COALESCE(a.actual_organic_sales, 0) AS actual_organic_sales,
  COALESCE(a.actual_total_sales, 0) AS actual_total_sales,
  COALESCE(a.actual_ads_sales, 0) - COALESCE(e.expected_ads_sales, 0) AS ads_difference
FROM expected_ads e
FULL OUTER JOIN actual_fact a
  ON e.date = a.date
  AND e.most_advertised_asin = a.most_advertised_asin
WHERE COALESCE(e.expected_ads_sales, 0) != COALESCE(a.actual_ads_sales, 0)
   OR COALESCE(a.actual_total_sales, 0) > 0
ORDER BY ABS(COALESCE(a.actual_ads_sales, 0) - COALESCE(e.expected_ads_sales, 0)) DESC;

-- 11. Summary: All sources side by side
SELECT 
  'SUMMARY' AS check_type,
  'Expected Total' AS source,
  3069.0 AS expected_sales,
  NULL AS actual_sales,
  3069.0 - NULL AS difference
UNION ALL
SELECT 
  'SUMMARY',
  'FACT_AMAZON_PERFORMANCE_DAILY',
  NULL,
  (SELECT SUM(sales) FROM `onyga-482313.OI.FACT_AMAZON_PERFORMANCE_DAILY` WHERE date = '2026-01-29'),
  (SELECT SUM(sales) FROM `onyga-482313.OI.FACT_AMAZON_PERFORMANCE_DAILY` WHERE date = '2026-01-29') - 3069.0
UNION ALL
SELECT 
  'SUMMARY',
  'STG_AMAZON_ADS',
  NULL,
  (SELECT SUM(sales) FROM `onyga-482313.OI.STG_AMAZON_ADS` WHERE date = '2026-01-29'),
  NULL
UNION ALL
SELECT 
  'SUMMARY',
  'STG_AMAZON_PERFORMANCE',
  NULL,
  (SELECT SUM(SALES_AMOUNT) FROM `onyga-482313.OI.STG_AMAZON_PERFORMANCE` WHERE date = '2026-01-29' AND IS_LOADED = TRUE),
  NULL;
