-- =============================================
-- Test: FACT_AMAZON_SEARCH_PERFORMANCE_WEEKLY - Source to Target Data Integrity
-- =============================================
-- Purpose: Verify all data from STG is correctly loaded into FACT with no missing or duplicates
-- Test Cases:
--   1.1: Row count match
--   1.2: No missing rows
--   1.3: No duplicate rows
--   1.4: Data value accuracy
--   1.5: Key calculation accuracy
-- =============================================

-- ==========================================
-- Test 1.1: Row Count Match
-- ==========================================
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

-- ==========================================
-- Test 1.2: No Missing Rows
-- ==========================================
SELECT 
  'Test 1.2: No Missing Rows' as test_name,
  COUNT(*) as missing_row_count,
  CASE 
    WHEN COUNT(*) = 0 THEN 'PASS: No missing rows'
    ELSE CONCAT('FAIL: Found ', CAST(COUNT(*) AS STRING), ' missing rows')
  END as assertion_result,
  -- Sample of missing rows for debugging
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

-- ==========================================
-- Test 1.3: No Duplicate Rows
-- ==========================================
SELECT 
  'Test 1.3: No Duplicate Rows' as test_name,
  COUNT(*) as duplicate_count,
  SUM(duplicate_count - 1) as total_duplicate_rows,
  CASE 
    WHEN COUNT(*) = 0 THEN 'PASS: No duplicate rows'
    ELSE CONCAT('FAIL: Found ', CAST(COUNT(*) AS STRING), ' duplicate primary keys')
  END as assertion_result,
  -- Sample of duplicate rows for debugging
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

-- ==========================================
-- Test 1.4: Data Value Accuracy (Sample Check)
-- ==========================================
-- Check if key columns match between STG and FACT
SELECT 
  'Test 1.4: Data Value Accuracy' as test_name,
  COUNT(*) as mismatched_value_count,
  CASE 
    WHEN COUNT(*) = 0 THEN 'PASS: All sampled values match'
    ELSE CONCAT('FAIL: Found ', CAST(COUNT(*) AS STRING), ' rows with mismatched values')
  END as assertion_result,
  -- Sample of mismatched rows for debugging
  ARRAY_AGG(STRUCT(
    stg.Reporting_Date,
    stg.ASIN,
    stg.Search_Query,
    stg.Impressions as stg_impressions,
    fact.Impressions as fact_impressions,
    stg.Clicks as stg_clicks,
    fact.Clicks as fact_clicks
  ) LIMIT 10) as sample_mismatches
FROM `onyga-482313.OI.STG_AMAZON_SEARCH_PERFORMANCE_WEEKLY` stg
INNER JOIN `onyga-482313.OI.FACT_AMAZON_SEARCH_PERFORMANCE_WEEKLY` fact
  ON stg.Reporting_Date = fact.Reporting_Date
  AND stg.ASIN = fact.ASIN
  AND COALESCE(stg.Search_Query, '') = COALESCE(fact.Search_Query, '')
WHERE 
  -- Check for mismatches in key columns
  COALESCE(stg.Impressions, 0) != COALESCE(fact.Impressions, 0)
  OR COALESCE(stg.Clicks, 0) != COALESCE(fact.Clicks, 0)
  OR COALESCE(stg.Cart_Adds, 0) != COALESCE(fact.Cart_Adds, 0)
  OR COALESCE(stg.ORDERS, 0) != COALESCE(fact.ORDERS, 0)
  OR COALESCE(stg.DATA_SOURCE, '') != COALESCE(fact.DATA_SOURCE, '');

-- ==========================================
-- Test 1.5: Key Calculation Accuracy
-- ==========================================
-- Verify ad_key and factless_key are calculated correctly
SELECT 
  'Test 1.5: Key Calculation Accuracy' as test_name,
  COUNT(*) as incorrect_key_count,
  CASE 
    WHEN COUNT(*) = 0 THEN 'PASS: All keys calculated correctly'
    ELSE CONCAT('FAIL: Found ', CAST(COUNT(*) AS STRING), ' rows with incorrect keys')
  END as assertion_result,
  -- Sample of incorrect keys for debugging
  ARRAY_AGG(STRUCT(
    Reporting_Date,
    ASIN,
    Search_Query,
    ad_key as actual_ad_key,
    CONCAT(
      FORMAT_DATE('%Y%m%d', Reporting_Date),
      '-',
      COALESCE(ASIN, 'NULL'),
      '-',
      COALESCE(Search_Query, 'NULL')
    ) as expected_ad_key,
    factless_key as actual_factless_key,
    CONCAT(
      FORMAT_DATE('%Y%m%d', Reporting_Date),
      '-',
      COALESCE(ASIN, 'NULL')
    ) as expected_factless_key
  ) LIMIT 10) as sample_incorrect_keys
FROM `onyga-482313.OI.FACT_AMAZON_SEARCH_PERFORMANCE_WEEKLY`
WHERE 
  -- Check if ad_key matches expected format
  ad_key != CONCAT(
    FORMAT_DATE('%Y%m%d', Reporting_Date),
    '-',
    COALESCE(ASIN, 'NULL'),
    '-',
    COALESCE(Search_Query, 'NULL')
  )
  OR
  -- Check if factless_key matches expected format
  factless_key != CONCAT(
    FORMAT_DATE('%Y%m%d', Reporting_Date),
    '-',
    COALESCE(ASIN, 'NULL')
  );

-- ==========================================
-- Summary Report
-- ==========================================
SELECT 
  'SUMMARY: Source to Target Data Integrity' as summary_type,
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
    THEN 'PASS: All tests passed'
    ELSE 'FAIL: One or more tests failed - see individual test results above'
  END as overall_result;
