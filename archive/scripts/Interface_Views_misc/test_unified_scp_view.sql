-- =============================================
-- Test Queries for V_UNIFIED_SCP_DATA View
-- =============================================
-- Run these queries to verify the view works correctly
-- =============================================

-- Test 1: Verify view exists and has data
SELECT 
  'View Test' as test_name,
  COUNT(*) as total_rows,
  COUNT(DISTINCT source_system) as source_count,
  COUNT(DISTINCT ASIN) as unique_asins,
  MIN(reporting_date) as earliest_date,
  MAX(reporting_date) as latest_date
FROM `onyga-482313.OI.V_UNIFIED_SCP_DATA`;

-- Test 2: Check data distribution by source
SELECT 
  source_system,
  COUNT(*) as row_count,
  COUNT(DISTINCT ASIN) as unique_asins,
  COUNT(DISTINCT Year) as unique_years,
  COUNT(DISTINCT Week) as unique_weeks,
  MIN(Year) as min_year,
  MAX(Year) as max_year,
  MIN(reporting_date) as earliest_date,
  MAX(reporting_date) as latest_date
FROM `onyga-482313.OI.V_UNIFIED_SCP_DATA`
GROUP BY source_system
ORDER BY source_system;

-- Test 3: Verify Year/Week extraction for OpenBridge
SELECT 
  source_system,
  Year,
  Week,
  start_date,
  end_date,
  reporting_date,
  COUNT(*) as record_count
FROM `onyga-482313.OI.V_UNIFIED_SCP_DATA`
WHERE source_system = 'OpenBridge'
GROUP BY source_system, Year, Week, start_date, end_date, reporting_date
ORDER BY Year DESC, Week DESC
LIMIT 10;

-- Test 4: Check for NULL values in key fields
SELECT 
  source_system,
  COUNT(*) as total_rows,
  COUNTIF(ASIN IS NULL) as null_asins,
  COUNTIF(Year IS NULL) as null_years,
  COUNTIF(Week IS NULL) as null_weeks,
  COUNTIF(start_date IS NULL) as null_start_dates,
  COUNTIF(end_date IS NULL) as null_end_dates
FROM `onyga-482313.OI.V_UNIFIED_SCP_DATA`
GROUP BY source_system;

-- Test 5: Sample data from both sources
SELECT 
  source_system,
  Year,
  Week,
  ASIN,
  start_date,
  end_date,
  Impressions_Impressions,
  Clicks_Clicks,
  Purchases_Purchases,
  Purchases_Search_Traffic_Sales
FROM `onyga-482313.OI.V_UNIFIED_SCP_DATA`
WHERE ASIN IS NOT NULL
ORDER BY source_system, Year DESC, Week DESC, ASIN
LIMIT 20;

-- Test 6: Check for overlapping ASINs between sources
WITH source_asins AS (
  SELECT 
    ASIN,
    Year,
    Week,
    source_system,
    COUNT(*) as record_count
  FROM `onyga-482313.OI.V_UNIFIED_SCP_DATA`
  WHERE ASIN IS NOT NULL
  GROUP BY ASIN, Year, Week, source_system
)
SELECT 
  'Overlap Analysis' as analysis_type,
  COUNT(DISTINCT CASE WHEN source_system = 'SCP' THEN ASIN END) as scp_unique_asins,
  COUNT(DISTINCT CASE WHEN source_system = 'OpenBridge' THEN ASIN END) as ob_unique_asins,
  COUNT(DISTINCT CASE 
    WHEN ASIN IN (SELECT ASIN FROM source_asins WHERE source_system = 'SCP')
    AND ASIN IN (SELECT ASIN FROM source_asins WHERE source_system = 'OpenBridge')
    THEN ASIN 
  END) as overlapping_asins
FROM source_asins;

-- Test 7: Verify metric mappings (check non-zero values)
SELECT 
  source_system,
  SUM(Impressions_Impressions) as total_impressions,
  SUM(Clicks_Clicks) as total_clicks,
  SUM(Cart_Adds_Cart_Adds) as total_cart_adds,
  SUM(Purchases_Purchases) as total_purchases,
  SUM(Purchases_Search_Traffic_Sales) as total_sales
FROM `onyga-482313.OI.V_UNIFIED_SCP_DATA`
WHERE ASIN IS NOT NULL
GROUP BY source_system;

-- Test 8: Check date range coverage
SELECT 
  source_system,
  Year,
  COUNT(DISTINCT Week) as weeks_in_year,
  MIN(Week) as min_week,
  MAX(Week) as max_week,
  MIN(start_date) as earliest_start,
  MAX(end_date) as latest_end
FROM `onyga-482313.OI.V_UNIFIED_SCP_DATA`
GROUP BY source_system, Year
ORDER BY source_system, Year DESC;
