-- =============================================
-- Deploy and Verify Fix for Sales Discrepancy
-- =============================================
-- This script:
-- 1. Deploys the updated SP_LOAD_FACT_AMAZON_PERFORMANCE_DAILY
-- 2. Runs the procedure
-- 3. Verifies the total for Jan 29, 2026
-- =============================================

-- Step 1: Deploy the updated stored procedure
-- (Run the entire SP_LOAD_FACT_AMAZON_PERFORMANCE_DAILY.sql file)

-- Step 2: Run the stored procedure
CALL `onyga-482313.OI.SP_LOAD_FACT_AMAZON_PERFORMANCE_DAILY`();

-- Step 3: Verify the total for Jan 29, 2026
SELECT 
  'Verification - Jan 29, 2026' AS check_type,
  DATE('2026-01-29') AS date,
  SUM(sales) AS total_sales,
  SUM(CASE WHEN Performance_TYPE = 'Ads' THEN sales ELSE 0 END) AS ads_sales,
  SUM(CASE WHEN Performance_TYPE = 'Organic' THEN sales ELSE 0 END) AS organic_sales,
  3069.0 AS expected_sales,
  SUM(sales) - 3069.0 AS difference,
  ROUND((SUM(sales) - 3069.0) / 3069.0 * 100, 2) AS difference_pct,
  COUNT(*) AS record_count,
  COUNT(DISTINCT most_advertised_asin) AS distinct_asins
FROM `onyga-482313.OI.FACT_AMAZON_PERFORMANCE_DAILY`
WHERE date = '2026-01-29';

-- Step 4: Compare with source data
SELECT 
  'Source Comparison' AS check_type,
  'STG_AMAZON_PERFORMANCE (LOADED)' AS source,
  SUM(SALES_AMOUNT) AS total_sales
FROM `onyga-482313.OI.STG_AMAZON_PERFORMANCE`
WHERE date = '2026-01-29' AND IS_LOADED = TRUE

UNION ALL

SELECT 
  'Source Comparison',
  'FACT_AMAZON_PERFORMANCE_DAILY',
  SUM(sales) AS total_sales
FROM `onyga-482313.OI.FACT_AMAZON_PERFORMANCE_DAILY`
WHERE date = '2026-01-29';

-- Step 5: Check for any remaining issues
SELECT 
  'Data Quality Check' AS check_type,
  COUNT(*) AS total_records,
  COUNT(CASE WHEN DATA_QUALITY_STATUS != 'OK' AND DATA_QUALITY_STATUS IS NOT NULL THEN 1 END) AS records_with_issues,
  COUNT(DISTINCT most_advertised_asin) AS distinct_asins,
  COUNT(DISTINCT CASE WHEN Performance_TYPE = 'Ads' THEN most_advertised_asin END) AS ads_asins,
  COUNT(DISTINCT CASE WHEN Performance_TYPE = 'Organic' THEN most_advertised_asin END) AS organic_asins
FROM `onyga-482313.OI.FACT_AMAZON_PERFORMANCE_DAILY`
WHERE date = '2026-01-29';
