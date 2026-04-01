-- =============================================
-- COMPREHENSIVE TEST SUITE
-- FACT_AMAZON_SEARCH_PERFORMANCE_WEEKLY & V_AMAZON_ADS_TOP_SEARCH_QUERY_TERMS_WEEKLY
-- =============================================
-- Run this file to execute all tests
-- Each test section can be run independently
-- =============================================

-- =============================================
-- TEST 1: SOURCE TO TARGET DATA INTEGRITY
-- =============================================

-- Test 1.1: Row Count Match
SELECT 
  'Test 1.1: Row Count Match' as test_name,
  (SELECT COUNT(*) FROM `onyga-482313.OI.STG_AMAZON_SEARCH_PERFORMANCE_WEEKLY`) as stg_row_count,
  (SELECT COUNT(*) FROM `onyga-482313.OI.FACT_AMAZON_SEARCH_PERFORMANCE_WEEKLY`) as fact_row_count,
  (SELECT COUNT(*) FROM `onyga-482313.OI.STG_AMAZON_SEARCH_PERFORMANCE_WEEKLY`) - 
  (SELECT COUNT(*) FROM `onyga-482313.OI.FACT_AMAZON_SEARCH_PERFORMANCE_WEEKLY`) as row_count_diff,
  CASE 
    WHEN (SELECT COUNT(*) FROM `onyga-482313.OI.STG_AMAZON_SEARCH_PERFORMANCE_WEEKLY`) = 
         (SELECT COUNT(*) FROM `onyga-482313.OI.FACT_AMAZON_SEARCH_PERFORMANCE_WEEKLY`)
    THEN 'PASS: Row counts match'
    ELSE CONCAT('FAIL: Row counts do not match. Difference: ', 
                CAST((SELECT COUNT(*) FROM `onyga-482313.OI.STG_AMAZON_SEARCH_PERFORMANCE_WEEKLY`) - 
                     (SELECT COUNT(*) FROM `onyga-482313.OI.FACT_AMAZON_SEARCH_PERFORMANCE_WEEKLY`) AS STRING))
  END as assertion_result;

-- Test 1.2: No Missing Rows
SELECT 
  'Test 1.2: No Missing Rows' as test_name,
  COUNT(*) as missing_row_count,
  CASE 
    WHEN COUNT(*) = 0 THEN 'PASS: No missing rows'
    ELSE CONCAT('FAIL: Found ', CAST(COUNT(*) AS STRING), ' missing rows')
  END as assertion_result,
  ARRAY_AGG(STRUCT(
    stg.Reporting_Date,
    stg.ASIN,
    stg.Search_Query
  ) LIMIT 10) as sample_missing_rows
FROM `onyga-482313.OI.STG_AMAZON_SEARCH_PERFORMANCE_WEEKLY` stg
LEFT JOIN `onyga-482313.OI.FACT_AMAZON_SEARCH_PERFORMANCE_WEEKLY` fact
  ON stg.Reporting_Date = fact.Reporting_Date
  AND stg.ASIN = fact.ASIN
  AND COALESCE(stg.Search_Query, '') = COALESCE(fact.Search_Query, '')
WHERE fact.Reporting_Date IS NULL;

-- Test 1.3: No Duplicate Rows
SELECT 
  'Test 1.3: No Duplicate Rows' as test_name,
  COUNT(*) as duplicate_count,
  SUM(duplicate_count - 1) as total_duplicate_rows,
  CASE 
    WHEN COUNT(*) = 0 THEN 'PASS: No duplicate rows'
    ELSE CONCAT('FAIL: Found ', CAST(COUNT(*) AS STRING), ' duplicate primary keys')
  END as assertion_result,
  ARRAY_AGG(STRUCT(
    Reporting_Date,
    ASIN,
    Search_Query,
    duplicate_count
  ) ORDER BY duplicate_count DESC LIMIT 10) as sample_duplicates
FROM (
  SELECT 
    Reporting_Date,
    ASIN,
    Search_Query,
    COUNT(*) as duplicate_count
  FROM `onyga-482313.OI.FACT_AMAZON_SEARCH_PERFORMANCE_WEEKLY`
  GROUP BY Reporting_Date, ASIN, Search_Query
  HAVING COUNT(*) > 1
);

-- =============================================
-- TEST 2: ad_key REFERENTIAL INTEGRITY
-- =============================================

-- Test 2.1: All ad_keys Exist
SELECT 
  'Test 2.1: All ad_keys Exist' as test_name,
  COUNT(*) as missing_ad_key_count,
  CASE 
    WHEN COUNT(*) = 0 THEN 'PASS: All ad_keys from view exist in fact table'
    ELSE CONCAT('FAIL: Found ', CAST(COUNT(*) AS STRING), ' ad_keys in view that do not exist in fact table')
  END as assertion_result,
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

-- =============================================
-- TEST 3: factless_key REFERENTIAL INTEGRITY
-- =============================================

-- Test 3.1: All factless_keys Exist
SELECT 
  'Test 3.1: All factless_keys Exist' as test_name,
  COUNT(*) as missing_factless_key_count,
  CASE 
    WHEN COUNT(*) = 0 THEN 'PASS: All factless_keys from fact table exist in bridge table'
    ELSE CONCAT('FAIL: Found ', CAST(COUNT(*) AS STRING), ' factless_keys in fact table that do not exist in bridge table')
  END as assertion_result,
  ARRAY_AGG(STRUCT(
    fact.Reporting_Date,
    fact.ASIN,
    fact.factless_key
  ) ORDER BY fact.Reporting_Date DESC LIMIT 20) as sample_missing_factless_keys
FROM `onyga-482313.OI.FACT_AMAZON_SEARCH_PERFORMANCE_WEEKLY` fact
LEFT JOIN `onyga-482313.OI.FACT_FACTLESS_BRIDGE` bridge
  ON fact.factless_key = bridge.factless_key
WHERE bridge.factless_key IS NULL;

-- =============================================
-- SUMMARY REPORT
-- =============================================
SELECT 
  '=== TEST SUMMARY ===' as summary_type,
  (SELECT COUNT(*) FROM `onyga-482313.OI.STG_AMAZON_SEARCH_PERFORMANCE_WEEKLY`) as stg_total_rows,
  (SELECT COUNT(*) FROM `onyga-482313.OI.FACT_AMAZON_SEARCH_PERFORMANCE_WEEKLY`) as fact_total_rows,
  (SELECT COUNT(*) FROM `onyga-482313.OI.STG_AMAZON_SEARCH_PERFORMANCE_WEEKLY` stg
   LEFT JOIN `onyga-482313.OI.FACT_AMAZON_SEARCH_PERFORMANCE_WEEKLY` fact
     ON stg.Reporting_Date = fact.Reporting_Date
     AND stg.ASIN = fact.ASIN
     AND COALESCE(stg.Search_Query, '') = COALESCE(fact.Search_Query, '')
   WHERE fact.Reporting_Date IS NULL) as missing_rows,
  (SELECT COUNT(*) FROM (
    SELECT Reporting_Date, ASIN, Search_Query, COUNT(*) as cnt
    FROM `onyga-482313.OI.FACT_AMAZON_SEARCH_PERFORMANCE_WEEKLY`
    GROUP BY Reporting_Date, ASIN, Search_Query
    HAVING COUNT(*) > 1
  )) as duplicate_keys,
  (SELECT COUNT(*) FROM `onyga-482313.OI.V_AMAZON_ADS_TOP_SEARCH_QUERY_TERMS_WEEKLY` view
   LEFT JOIN `onyga-482313.OI.FACT_AMAZON_SEARCH_PERFORMANCE_WEEKLY` fact
     ON view.ad_key = fact.ad_key
   WHERE fact.ad_key IS NULL) as missing_ad_keys,
  (SELECT COUNT(*) FROM `onyga-482313.OI.FACT_AMAZON_SEARCH_PERFORMANCE_WEEKLY` fact
   LEFT JOIN `onyga-482313.OI.FACT_FACTLESS_BRIDGE` bridge
     ON fact.factless_key = bridge.factless_key
   WHERE bridge.factless_key IS NULL) as missing_factless_keys,
  CASE 
    WHEN (SELECT COUNT(*) FROM `onyga-482313.OI.STG_AMAZON_SEARCH_PERFORMANCE_WEEKLY`) = 
         (SELECT COUNT(*) FROM `onyga-482313.OI.FACT_AMAZON_SEARCH_PERFORMANCE_WEEKLY`)
      AND (SELECT COUNT(*) FROM `onyga-482313.OI.STG_AMAZON_SEARCH_PERFORMANCE_WEEKLY` stg
           LEFT JOIN `onyga-482313.OI.FACT_AMAZON_SEARCH_PERFORMANCE_WEEKLY` fact
             ON stg.Reporting_Date = fact.Reporting_Date
             AND stg.ASIN = fact.ASIN
             AND COALESCE(stg.Search_Query, '') = COALESCE(fact.Search_Query, '')
           WHERE fact.Reporting_Date IS NULL) = 0
      AND (SELECT COUNT(*) FROM (
        SELECT Reporting_Date, ASIN, Search_Query, COUNT(*) as cnt
        FROM `onyga-482313.OI.FACT_AMAZON_SEARCH_PERFORMANCE_WEEKLY`
        GROUP BY Reporting_Date, ASIN, Search_Query
        HAVING COUNT(*) > 1
      )) = 0
      AND (SELECT COUNT(*) FROM `onyga-482313.OI.V_AMAZON_ADS_TOP_SEARCH_QUERY_TERMS_WEEKLY` view
           LEFT JOIN `onyga-482313.OI.FACT_AMAZON_SEARCH_PERFORMANCE_WEEKLY` fact
             ON view.ad_key = fact.ad_key
           WHERE fact.ad_key IS NULL) = 0
      AND (SELECT COUNT(*) FROM `onyga-482313.OI.FACT_AMAZON_SEARCH_PERFORMANCE_WEEKLY` fact
           LEFT JOIN `onyga-482313.OI.FACT_FACTLESS_BRIDGE` bridge
             ON fact.factless_key = bridge.factless_key
           WHERE bridge.factless_key IS NULL) = 0
    THEN '✅ ALL TESTS PASSED'
    ELSE '❌ ONE OR MORE TESTS FAILED - Review individual test results above'
  END as overall_result;
