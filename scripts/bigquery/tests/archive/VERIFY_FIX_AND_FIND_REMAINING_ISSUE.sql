-- =============================================
-- Verify Fix and Find Remaining Issue
-- =============================================
-- Run this after deploying the SUM fix to see what's still wrong
-- =============================================

-- 1. Current state of FACT table
SELECT 
  '1. FACT Table Current State' AS step,
  SUM(sales) AS total_sales,
  SUM(CASE WHEN Performance_TYPE = 'Ads' THEN sales ELSE 0 END) AS ads_sales,
  SUM(CASE WHEN Performance_TYPE = 'Organic' THEN sales ELSE 0 END) AS organic_sales,
  3069.0 AS expected_sales,
  SUM(sales) - 3069.0 AS difference
FROM `onyga-482313.OI.FACT_AMAZON_PERFORMANCE_DAILY`
WHERE date = '2026-01-29';

-- 2. What should Ads sales be? (Direct aggregation from STG_AMAZON_ADS)
SELECT 
  '2. Expected Ads Sales (STG_AMAZON_ADS direct sum)' AS step,
  SUM(sales) AS expected_ads_sales
FROM `onyga-482313.OI.STG_AMAZON_ADS`
WHERE date = '2026-01-29'
  AND most_advertised_asin_purchased IS NOT NULL;

-- 3. What's the source total?
SELECT 
  '3. Source Total (STG_AMAZON_PERFORMANCE)' AS step,
  SUM(SALES_AMOUNT) AS source_total
FROM `onyga-482313.OI.STG_AMAZON_PERFORMANCE`
WHERE date = '2026-01-29' AND IS_LOADED = TRUE;

-- 4. Check if SUM fix is working - simulate the SP logic
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
),
grouped AS (
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
    SUM(COALESCE(sales, 0)) AS sales  -- Using SUM as per the fix
  FROM unpivoted
  GROUP BY 
    date, campaign_id, campaign_name, campaign_type, inferred_sales_module,
    ad_group_id, keyword_id, ad_keyword_status, targeting, search_term,
    placement_type, advertised_asins, advertised_asins_count, asin,
    _fivetran_synced, source_table
)
SELECT 
  '4. Simulated SP Result (with SUM fix)' AS step,
  SUM(sales) AS simulated_ads_sales
FROM grouped;

-- 5. Compare: What's actually in FACT vs what should be
SELECT 
  '5. Comparison' AS step,
  (SELECT SUM(sales) FROM `onyga-482313.OI.FACT_AMAZON_PERFORMANCE_DAILY` 
   WHERE date = '2026-01-29' AND Performance_TYPE = 'Ads') AS fact_ads_sales,
  (SELECT SUM(sales) FROM `onyga-482313.OI.STG_AMAZON_ADS` 
   WHERE date = '2026-01-29' AND most_advertised_asin_purchased IS NOT NULL) AS stg_ads_sales,
  (SELECT SUM(sales) FROM `onyga-482313.OI.FACT_AMAZON_PERFORMANCE_DAILY` 
   WHERE date = '2026-01-29' AND Performance_TYPE = 'Ads') - 
  (SELECT SUM(sales) FROM `onyga-482313.OI.STG_AMAZON_ADS` 
   WHERE date = '2026-01-29' AND most_advertised_asin_purchased IS NOT NULL) AS ads_difference;

-- 6. Check organic delta calculation
WITH ads_agg AS (
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
  '6. Organic Delta Check' AS step,
  SUM(perf.SALES_AMOUNT) AS total_performance,
  SUM(COALESCE(ads.ads_sales, 0)) AS total_ads,
  SUM(GREATEST(0, perf.SALES_AMOUNT - COALESCE(ads.ads_sales, 0))) AS expected_organic,
  (SELECT SUM(sales) FROM `onyga-482313.OI.FACT_AMAZON_PERFORMANCE_DAILY` 
   WHERE date = '2026-01-29' AND Performance_TYPE = 'Organic') AS actual_organic
FROM `onyga-482313.OI.STG_AMAZON_PERFORMANCE` perf
LEFT JOIN ads_agg ads
  ON perf.child_asin = ads.asin
  AND perf.date = ads.date
WHERE perf.date = '2026-01-29'
  AND (perf.SALES_QUANTITY > 0 OR perf.SALES_AMOUNT > 0 OR perf.SALES_ORDERS > 0)
  AND perf.IS_LOADED = TRUE;

-- 7. Summary: All totals side by side
SELECT 
  '7. SUMMARY' AS step,
  3069.0 AS expected_total,
  (SELECT SUM(SALES_AMOUNT) FROM `onyga-482313.OI.STG_AMAZON_PERFORMANCE` 
   WHERE date = '2026-01-29' AND IS_LOADED = TRUE) AS source_total,
  (SELECT SUM(sales) FROM `onyga-482313.OI.FACT_AMAZON_PERFORMANCE_DAILY` 
   WHERE date = '2026-01-29') AS fact_total,
  (SELECT SUM(sales) FROM `onyga-482313.OI.FACT_AMAZON_PERFORMANCE_DAILY` 
   WHERE date = '2026-01-29') - 3069.0 AS difference;
