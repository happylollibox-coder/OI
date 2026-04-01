-- =============================================
-- Test: FACT_AMAZON_SEARCH_PERFORMANCE_WEEKLY - ad_key Referential Integrity
-- =============================================
-- Purpose: Verify that every ad_key in V_AMAZON_ADS_TOP_SEARCH_QUERY_TERMS_WEEKLY 
--          exists in FACT_AMAZON_SEARCH_PERFORMANCE_WEEKLY
-- Test Cases:
--   2.1: All ad_keys exist
--   2.2: Date alignment check
--   2.3: NULL handling check
-- =============================================

-- ==========================================
-- Test 2.1: All ad_keys Exist
-- ==========================================
SELECT 
  'Test 2.1: All ad_keys Exist' as test_name,
  COUNT(*) as missing_ad_key_count,
  CASE 
    WHEN COUNT(*) = 0 THEN 'PASS: All ad_keys from view exist in fact table'
    ELSE CONCAT('FAIL: Found ', CAST(COUNT(*) AS STRING), ' ad_keys in view that do not exist in fact table')
  END as assertion_result,
  -- Sample of missing ad_keys for debugging
  ARRAY_AGG(STRUCT(
    view.week_end_date,
    view.asin,
    view.search_term,
    view.ad_key
  ) ORDER BY view.week_end_date DESC LIMIT 20) as sample_missing_ad_keys
FROM `onyga-482313.OI.V_AMAZON_ADS_TOP_SEARCH_QUERY_TERMS_WEEKLY` view
LEFT JOIN `onyga-482313.OI.FACT_AMAZON_SEARCH_PERFORMANCE_WEEKLY` fact
  ON view.ad_key = fact.ad_key
WHERE fact.ad_key IS NULL;

-- ==========================================
-- Test 2.2: Date Alignment Check
-- ==========================================
-- Check if week_end_date from view aligns with Reporting_Date in fact
-- This helps identify if date mismatch is causing key mismatches
SELECT 
  'Test 2.2: Date Alignment Check' as test_name,
  COUNT(*) as date_mismatch_count,
  CASE 
    WHEN COUNT(*) = 0 THEN 'PASS: All dates align correctly'
    ELSE CONCAT('WARNING: Found ', CAST(COUNT(*) AS STRING), ' rows where week_end_date != Reporting_Date')
  END as assertion_result,
  -- Sample of date mismatches for debugging
  ARRAY_AGG(STRUCT(
    view.week_end_date,
    view.asin,
    view.search_term,
    view.ad_key as view_ad_key,
    fact.Reporting_Date,
    fact.ad_key as fact_ad_key
  ) ORDER BY view.week_end_date DESC LIMIT 20) as sample_date_mismatches
FROM `onyga-482313.OI.V_AMAZON_ADS_TOP_SEARCH_QUERY_TERMS_WEEKLY` view
LEFT JOIN `onyga-482313.OI.FACT_AMAZON_SEARCH_PERFORMANCE_WEEKLY` fact
  ON view.ad_key = fact.ad_key
WHERE fact.ad_key IS NOT NULL
  AND view.week_end_date != fact.Reporting_Date;

-- ==========================================
-- Test 2.3: NULL Search Query Handling
-- ==========================================
-- Check if NULL search_term in view creates different keys than NULL Search_Query in fact
-- View uses: search_term directly (no COALESCE)
-- Fact uses: COALESCE(Search_Query, 'NULL')
SELECT 
  'Test 2.3: NULL Search Query Handling' as test_name,
  COUNT(*) as null_handling_mismatch_count,
  CASE 
    WHEN COUNT(*) = 0 THEN 'PASS: NULL handling is consistent'
    ELSE CONCAT('WARNING: Found ', CAST(COUNT(*) AS STRING), ' rows with NULL search_term that may have key format issues')
  END as assertion_result,
  -- Sample of NULL handling issues
  ARRAY_AGG(STRUCT(
    view.week_end_date,
    view.asin,
    view.search_term,
    view.ad_key as view_ad_key,
    -- Expected fact ad_key if Search_Query is NULL
    CONCAT(
      FORMAT_DATE('%Y%m%d', view.week_end_date),
      '-',
      view.asin,
      '-',
      'NULL'
    ) as expected_fact_ad_key_if_null
  ) LIMIT 20) as sample_null_handling_issues
FROM `onyga-482313.OI.V_AMAZON_ADS_TOP_SEARCH_QUERY_TERMS_WEEKLY` view
LEFT JOIN `onyga-482313.OI.FACT_AMAZON_SEARCH_PERFORMANCE_WEEKLY` fact
  ON view.ad_key = fact.ad_key
WHERE view.search_term IS NULL
  AND fact.ad_key IS NULL;

-- ==========================================
-- Test 2.4: Key Format Analysis
-- ==========================================
-- Analyze key formats to identify potential mismatches
SELECT 
  'Test 2.4: Key Format Analysis' as test_name,
  'View ad_key format' as analysis_type,
  COUNT(DISTINCT view.ad_key) as unique_view_keys,
  COUNT(DISTINCT fact.ad_key) as unique_fact_keys,
  COUNT(DISTINCT view.ad_key) - COUNT(DISTINCT fact.ad_key) as key_difference,
  -- Sample keys from view
  ARRAY_AGG(DISTINCT view.ad_key LIMIT 10) as sample_view_keys,
  -- Sample keys from fact (ignore NULLs to avoid array null element errors)
  ARRAY_AGG(DISTINCT fact.ad_key IGNORE NULLS LIMIT 10) as sample_fact_keys
FROM `onyga-482313.OI.V_AMAZON_ADS_TOP_SEARCH_QUERY_TERMS_WEEKLY` view
FULL OUTER JOIN `onyga-482313.OI.FACT_AMAZON_SEARCH_PERFORMANCE_WEEKLY` fact
  ON view.ad_key = fact.ad_key;

-- ==========================================
-- Test 2.5: Detailed Missing Key Analysis
-- ==========================================
-- For missing keys, try to find matches using different key formats
-- This helps identify if the issue is key format or truly missing data
SELECT 
  'Test 2.5: Detailed Missing Key Analysis' as test_name,
  view.week_end_date,
  view.asin,
  view.search_term,
  view.ad_key as view_ad_key,
  -- Try matching with Reporting_Date instead of week_end_date
  fact_by_date.ad_key as fact_ad_key_by_date,
  -- Try matching with different NULL handling
  CONCAT(
    FORMAT_DATE('%Y%m%d', view.week_end_date),
    '-',
    view.asin,
    '-',
    COALESCE(view.search_term, 'NULL')
  ) as alternative_key_format
FROM `onyga-482313.OI.V_AMAZON_ADS_TOP_SEARCH_QUERY_TERMS_WEEKLY` view
LEFT JOIN `onyga-482313.OI.FACT_AMAZON_SEARCH_PERFORMANCE_WEEKLY` fact
  ON view.ad_key = fact.ad_key
LEFT JOIN `onyga-482313.OI.FACT_AMAZON_SEARCH_PERFORMANCE_WEEKLY` fact_by_date
  ON view.week_end_date = fact_by_date.Reporting_Date
  AND view.asin = fact_by_date.ASIN
  AND COALESCE(view.search_term, '') = COALESCE(fact_by_date.Search_Query, '')
WHERE fact.ad_key IS NULL
LIMIT 50;

-- ==========================================
-- Summary Report
-- ==========================================
SELECT 
  'SUMMARY: ad_key Referential Integrity' as summary_type,
  (SELECT COUNT(DISTINCT ad_key) FROM `onyga-482313.OI.V_AMAZON_ADS_TOP_SEARCH_QUERY_TERMS_WEEKLY`) as total_view_ad_keys,
  (SELECT COUNT(DISTINCT ad_key) FROM `onyga-482313.OI.FACT_AMAZON_SEARCH_PERFORMANCE_WEEKLY`) as total_fact_ad_keys,
  (SELECT COUNT(*) FROM `onyga-482313.OI.V_AMAZON_ADS_TOP_SEARCH_QUERY_TERMS_WEEKLY` view
   LEFT JOIN `onyga-482313.OI.FACT_AMAZON_SEARCH_PERFORMANCE_WEEKLY` fact
     ON view.ad_key = fact.ad_key
   WHERE fact.ad_key IS NULL) as missing_ad_keys,
  (SELECT COUNT(*) FROM `onyga-482313.OI.V_AMAZON_ADS_TOP_SEARCH_QUERY_TERMS_WEEKLY` view
   LEFT JOIN `onyga-482313.OI.FACT_AMAZON_SEARCH_PERFORMANCE_WEEKLY` fact
     ON view.ad_key = fact.ad_key
   WHERE fact.ad_key IS NOT NULL
     AND view.week_end_date != fact.Reporting_Date) as date_mismatches,
  CASE 
    WHEN (SELECT COUNT(*) FROM `onyga-482313.OI.V_AMAZON_ADS_TOP_SEARCH_QUERY_TERMS_WEEKLY` view
          LEFT JOIN `onyga-482313.OI.FACT_AMAZON_SEARCH_PERFORMANCE_WEEKLY` fact
            ON view.ad_key = fact.ad_key
          WHERE fact.ad_key IS NULL) = 0
    THEN 'PASS: All ad_keys from view exist in fact table'
    ELSE 'FAIL: Some ad_keys from view do not exist in fact table - see detailed results above'
  END as overall_result;
