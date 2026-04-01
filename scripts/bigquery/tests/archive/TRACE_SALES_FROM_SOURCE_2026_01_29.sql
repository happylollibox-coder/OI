-- =============================================
-- End-to-End Sales Trace: Jan 29, 2026
-- =============================================
-- Expected: $3,069 USD
-- Actual in FACT_AMAZON_PERFORMANCE_DAILY: $3,614.6
-- Difference: $545.6
-- =============================================
-- This query traces sales from source to fact table
-- =============================================

-- 1. SOURCE: fivetran-hl.amazon_selling_partner.sales_and_traffic_business_sku_report_daily
SELECT 
  '1. SOURCE - Fivetran Table' AS step,
  DATE('2026-01-29') AS date,
  SUM(sales_by_asin_ordered_product_sales_amount) AS total_sales_amount,
  COUNT(*) AS record_count,
  COUNT(DISTINCT child_asin) AS distinct_asins,
  STRING_AGG(DISTINCT sales_by_asin_ordered_product_sales_currency_code, ', ') AS currencies
FROM `fivetran-hl.amazon_selling_partner.sales_and_traffic_business_sku_report_daily`
WHERE end_date = '2026-01-29';

-- 2. SOURCE VIEW: V_SRC_sales_and_traffic_business_sku_report_daily
SELECT 
  '2. SOURCE VIEW - V_SRC_sales_and_traffic' AS step,
  DATE('2026-01-29') AS date,
  SUM(SALES_AMOUNT) AS total_sales_amount,
  COUNT(*) AS record_count,
  COUNT(DISTINCT child_asin) AS distinct_asins,
  STRING_AGG(DISTINCT SALES_CURRENCY, ', ') AS currencies
FROM `onyga-482313.OI.V_SRC_sales_and_traffic_business_sku_report_daily`
WHERE date = '2026-01-29';

-- 3. STAGING: STG_AMAZON_PERFORMANCE
SELECT 
  '3. STAGING - STG_AMAZON_PERFORMANCE' AS step,
  DATE('2026-01-29') AS date,
  SUM(SALES_AMOUNT) AS total_sales_amount,
  COUNT(*) AS record_count,
  COUNT(DISTINCT child_asin) AS distinct_asins,
  SUM(CASE WHEN IS_LOADED = TRUE THEN 1 ELSE 0 END) AS loaded_records,
  SUM(CASE WHEN IS_LOADED = FALSE THEN 1 ELSE 0 END) AS not_loaded_records,
  STRING_AGG(DISTINCT SALES_CURRENCY, ', ') AS currencies
FROM `onyga-482313.OI.STG_AMAZON_PERFORMANCE`
WHERE date = '2026-01-29';

-- 4. STAGING (LOADED ONLY): STG_AMAZON_PERFORMANCE with IS_LOADED = TRUE
SELECT 
  '4. STAGING (LOADED) - STG_AMAZON_PERFORMANCE' AS step,
  DATE('2026-01-29') AS date,
  SUM(SALES_AMOUNT) AS total_sales_amount,
  COUNT(*) AS record_count,
  COUNT(DISTINCT child_asin) AS distinct_asins
FROM `onyga-482313.OI.STG_AMAZON_PERFORMANCE`
WHERE date = '2026-01-29'
  AND IS_LOADED = TRUE;

-- 5. ADS STAGING: STG_AMAZON_ADS (what gets subtracted for organic delta)
SELECT 
  '5. ADS STAGING - STG_AMAZON_ADS' AS step,
  DATE('2026-01-29') AS date,
  SUM(sales) AS total_ads_sales,
  COUNT(*) AS record_count,
  COUNT(DISTINCT most_advertised_asin_purchased) AS distinct_asins_purchased
FROM `onyga-482313.OI.STG_AMAZON_ADS`
WHERE date = '2026-01-29'
  AND most_advertised_asin_purchased IS NOT NULL;

-- 6. ADS AGGREGATION: How ads sales are aggregated by ASIN (used in organic delta calc)
SELECT 
  '6. ADS AGGREGATION - By ASIN' AS step,
  DATE('2026-01-29') AS date,
  most_advertised_asin_purchased AS asin,
  SUM(sales) AS ads_sales,
  SUM(orders) AS ads_orders,
  SUM(units) AS ads_units,
  COUNT(*) AS source_rows
FROM `onyga-482313.OI.STG_AMAZON_ADS`
WHERE date = '2026-01-29'
  AND most_advertised_asin_purchased IS NOT NULL
GROUP BY most_advertised_asin_purchased
ORDER BY ads_sales DESC;

-- 7. ORGANIC DELTA CALCULATION: Performance - Ads (what should be in FACT as Organic)
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
  '7. ORGANIC DELTA - Performance - Ads' AS step,
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

-- 8. ORGANIC DELTA SUMMARY: Total organic sales that should be in FACT
WITH ads_sales_agg AS (
  SELECT 
    most_advertised_asin_purchased AS asin,
    date,
    SUM(sales) AS ads_sales
  FROM `onyga-482313.OI.STG_AMAZON_ADS`
  WHERE date = '2026-01-29'
    AND most_advertised_asin_purchased IS NOT NULL
  GROUP BY most_advertised_asin_purchased, date
)
SELECT 
  '8. ORGANIC DELTA SUMMARY' AS step,
  DATE('2026-01-29') AS date,
  SUM(perf.SALES_AMOUNT) AS total_performance_sales,
  SUM(COALESCE(ads.ads_sales, 0)) AS total_ads_sales,
  SUM(GREATEST(0, perf.SALES_AMOUNT - COALESCE(ads.ads_sales, 0))) AS total_organic_delta_sales,
  COUNT(*) AS asin_count
FROM `onyga-482313.OI.STG_AMAZON_PERFORMANCE` perf
LEFT JOIN ads_sales_agg ads
  ON perf.child_asin = ads.asin
  AND perf.date = ads.date
WHERE perf.date = '2026-01-29'
  AND (perf.SALES_QUANTITY > 0 OR perf.SALES_AMOUNT > 0 OR perf.SALES_ORDERS > 0)
  AND perf.IS_LOADED = TRUE;

-- 9. FACT TABLE: FACT_AMAZON_PERFORMANCE_DAILY (Actual)
SELECT 
  '9. FACT TABLE - FACT_AMAZON_PERFORMANCE_DAILY' AS step,
  DATE('2026-01-29') AS date,
  SUM(sales) AS total_sales,
  SUM(CASE WHEN Performance_TYPE = 'Ads' THEN sales ELSE 0 END) AS ads_sales,
  SUM(CASE WHEN Performance_TYPE = 'Organic' THEN sales ELSE 0 END) AS organic_sales,
  COUNT(*) AS record_count,
  COUNT(DISTINCT most_advertised_asin) AS distinct_asins,
  COUNT(DISTINCT CASE WHEN Performance_TYPE = 'Ads' THEN most_advertised_asin END) AS ads_asins,
  COUNT(DISTINCT CASE WHEN Performance_TYPE = 'Organic' THEN most_advertised_asin END) AS organic_asins
FROM `onyga-482313.OI.FACT_AMAZON_PERFORMANCE_DAILY`
WHERE date = '2026-01-29';

-- 10. FACT TABLE BY ASIN: Detailed breakdown
SELECT 
  '10. FACT TABLE BY ASIN' AS step,
  most_advertised_asin AS asin,
  Performance_TYPE,
  SUM(sales) AS sales,
  COUNT(*) AS record_count
FROM `onyga-482313.OI.FACT_AMAZON_PERFORMANCE_DAILY`
WHERE date = '2026-01-29'
GROUP BY most_advertised_asin, Performance_TYPE
ORDER BY most_advertised_asin, Performance_TYPE;

-- 11. COMPARISON: Expected vs Actual
WITH source_total AS (
  SELECT SUM(SALES_AMOUNT) AS total
  FROM `onyga-482313.OI.STG_AMAZON_PERFORMANCE`
  WHERE date = '2026-01-29' AND IS_LOADED = TRUE
),
ads_total AS (
  SELECT SUM(sales) AS total
  FROM `onyga-482313.OI.STG_AMAZON_ADS`
  WHERE date = '2026-01-29' AND most_advertised_asin_purchased IS NOT NULL
),
fact_total AS (
  SELECT SUM(sales) AS total
  FROM `onyga-482313.OI.FACT_AMAZON_PERFORMANCE_DAILY`
  WHERE date = '2026-01-29'
)
SELECT 
  '11. COMPARISON SUMMARY' AS step,
  3069.0 AS expected_sales,
  (SELECT total FROM source_total) AS source_total_sales,
  (SELECT total FROM ads_total) AS ads_total_sales,
  (SELECT total FROM fact_total) AS fact_total_sales,
  (SELECT total FROM fact_total) - 3069.0 AS difference,
  ROUND(((SELECT total FROM fact_total) - 3069.0) / 3069.0 * 100, 2) AS difference_pct;

-- 12. CHECK FOR DUPLICATES IN FACT TABLE
SELECT 
  '12. DUPLICATE CHECK - FACT TABLE' AS step,
  date,
  most_advertised_asin,
  campaign_id,
  ad_group_id,
  keyword_id,
  search_term,
  Performance_TYPE,
  COUNT(*) AS duplicate_count,
  SUM(sales) AS total_sales_for_group,
  STRING_AGG(DISTINCT data_SOURCE, ', ') AS data_sources
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

-- 13. CHECK UNPIVOT LOGIC: Simulate what happens in SP for Ads records
SELECT 
  '13. UNPIVOT SIMULATION - Ads Records' AS step,
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
HAVING SUM(sales) > 0 OR measure_type != 'purchased'
ORDER BY asin, measure_type;

-- 14. EXPECTED ADS SALES AFTER GROUPING: What should be in FACT for Ads
SELECT 
  '14. EXPECTED ADS SALES - After Grouping' AS step,
  date,
  asin AS most_advertised_asin,
  SUM(CASE WHEN measure_type = 'purchased' THEN sales ELSE 0 END) AS expected_ads_sales,
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
ORDER BY expected_ads_sales DESC;

-- 15. FINAL COMPARISON: Expected vs Actual by ASIN
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
expected_organic AS (
  WITH ads_sales_agg AS (
    SELECT 
      most_advertised_asin_purchased AS asin,
      date,
      SUM(sales) AS ads_sales
    FROM `onyga-482313.OI.STG_AMAZON_ADS`
    WHERE date = '2026-01-29'
      AND most_advertised_asin_purchased IS NOT NULL
    GROUP BY most_advertised_asin_purchased, date
  )
  SELECT 
    perf.child_asin AS most_advertised_asin,
    GREATEST(0, perf.SALES_AMOUNT - COALESCE(ads.ads_sales, 0)) AS expected_organic_sales
  FROM `onyga-482313.OI.STG_AMAZON_PERFORMANCE` perf
  LEFT JOIN ads_sales_agg ads
    ON perf.child_asin = ads.asin
    AND perf.date = ads.date
  WHERE perf.date = '2026-01-29'
    AND (perf.SALES_QUANTITY > 0 OR perf.SALES_AMOUNT > 0 OR perf.SALES_ORDERS > 0)
    AND perf.IS_LOADED = TRUE
    AND GREATEST(0, perf.SALES_AMOUNT - COALESCE(ads.ads_sales, 0)) > 0
),
actual_fact AS (
  SELECT 
    most_advertised_asin,
    SUM(CASE WHEN Performance_TYPE = 'Ads' THEN sales ELSE 0 END) AS actual_ads_sales,
    SUM(CASE WHEN Performance_TYPE = 'Organic' THEN sales ELSE 0 END) AS actual_organic_sales,
    SUM(sales) AS actual_total_sales
  FROM `onyga-482313.OI.FACT_AMAZON_PERFORMANCE_DAILY`
  WHERE date = '2026-01-29'
  GROUP BY most_advertised_asin
)
SELECT 
  '15. FINAL COMPARISON BY ASIN' AS step,
  COALESCE(ea.most_advertised_asin, eo.most_advertised_asin, af.most_advertised_asin) AS asin,
  COALESCE(ea.expected_ads_sales, 0) AS expected_ads_sales,
  COALESCE(eo.expected_organic_sales, 0) AS expected_organic_sales,
  COALESCE(ea.expected_ads_sales, 0) + COALESCE(eo.expected_organic_sales, 0) AS expected_total,
  COALESCE(af.actual_ads_sales, 0) AS actual_ads_sales,
  COALESCE(af.actual_organic_sales, 0) AS actual_organic_sales,
  COALESCE(af.actual_total_sales, 0) AS actual_total_sales,
  COALESCE(af.actual_total_sales, 0) - (COALESCE(ea.expected_ads_sales, 0) + COALESCE(eo.expected_organic_sales, 0)) AS difference
FROM expected_ads ea
FULL OUTER JOIN expected_organic eo
  ON ea.most_advertised_asin = eo.most_advertised_asin
FULL OUTER JOIN actual_fact af
  ON COALESCE(ea.most_advertised_asin, eo.most_advertised_asin) = af.most_advertised_asin
WHERE COALESCE(ea.expected_ads_sales, 0) + COALESCE(eo.expected_organic_sales, 0) != COALESCE(af.actual_total_sales, 0)
   OR COALESCE(af.actual_total_sales, 0) > 0
ORDER BY ABS(COALESCE(af.actual_total_sales, 0) - (COALESCE(ea.expected_ads_sales, 0) + COALESCE(eo.expected_organic_sales, 0))) DESC;
