-- =============================================
-- Test: FACT_AMAZON_SEARCH_PERFORMANCE_WEEKLY - factless_key Referential Integrity
-- =============================================
-- Purpose: Verify that every factless_key in FACT_AMAZON_SEARCH_PERFORMANCE_WEEKLY 
--          exists in FACT_FACTLESS_BRIDGE
-- Test Cases:
--   3.1: All factless_keys exist
--   3.2: Key format compatibility
--   3.3: Bridge table population check
--   3.4: NULL ASIN handling
-- =============================================

-- ==========================================
-- Test 3.1: All factless_keys Exist
-- ==========================================
SELECT 
  'Test 3.1: All factless_keys Exist' as test_name,
  COUNT(*) as missing_factless_key_count,
  CASE 
    WHEN COUNT(*) = 0 THEN 'PASS: All factless_keys from fact table exist in bridge table'
    ELSE CONCAT('FAIL: Found ', CAST(COUNT(*) AS STRING), ' factless_keys in fact table that do not exist in bridge table')
  END as assertion_result,
  -- Sample of missing factless_keys for debugging
  ARRAY_AGG(STRUCT(
    fact.Reporting_Date,
    fact.ASIN,
    fact.factless_key
  ) ORDER BY fact.Reporting_Date DESC LIMIT 20) as sample_missing_factless_keys
FROM `onyga-482313.OI.FACT_AMAZON_SEARCH_PERFORMANCE_WEEKLY` fact
LEFT JOIN `onyga-482313.OI.FACT_FACTLESS_BRIDGE` bridge
  ON fact.factless_key = bridge.factless_key
WHERE bridge.factless_key IS NULL;

-- ==========================================
-- Test 3.2: Key Format Compatibility
-- ==========================================
-- Verify that key formats match exactly between fact and bridge
-- Fact: YYYYMMDD-ASIN (using FORMAT_DATE on Reporting_Date)
-- Bridge: date_key-asin (using CAST on INT64 date_key)
SELECT 
  'Test 3.2: Key Format Compatibility' as test_name,
  COUNT(*) as format_mismatch_count,
  CASE 
    WHEN COUNT(*) = 0 THEN 'PASS: All key formats match'
    ELSE CONCAT('WARNING: Found ', CAST(COUNT(*) AS STRING), ' rows with potential format mismatches')
  END as assertion_result,
  -- Sample of format mismatches
  ARRAY_AGG(STRUCT(
    fact.Reporting_Date,
    fact.ASIN,
    fact.factless_key as fact_factless_key,
    -- Expected bridge format
    CONCAT(
      CAST(CAST(FORMAT_DATE('%Y%m%d', fact.Reporting_Date) AS INT64) AS STRING),
      '-',
      fact.ASIN
    ) as expected_bridge_format,
    bridge.factless_key as bridge_factless_key
  ) LIMIT 20) as sample_format_mismatches
FROM `onyga-482313.OI.FACT_AMAZON_SEARCH_PERFORMANCE_WEEKLY` fact
LEFT JOIN `onyga-482313.OI.FACT_FACTLESS_BRIDGE` bridge
  ON fact.factless_key = bridge.factless_key
WHERE bridge.factless_key IS NULL
  AND fact.ASIN IS NOT NULL;

-- ==========================================
-- Test 3.3: Bridge Table Population Check
-- ==========================================
-- Check if FACT_AMAZON_SEARCH_PERFORMANCE_WEEKLY is included in bridge table
-- by checking if any factless_keys from fact exist in bridge
SELECT 
  'Test 3.3: Bridge Table Population Check' as test_name,
  COUNT(DISTINCT fact.factless_key) as unique_fact_keys,
  COUNT(DISTINCT bridge.factless_key) as matching_bridge_keys,
  COUNT(DISTINCT fact.factless_key) - COUNT(DISTINCT bridge.factless_key) as missing_keys,
  CASE 
    WHEN COUNT(DISTINCT fact.factless_key) = COUNT(DISTINCT bridge.factless_key) 
    THEN 'PASS: All unique factless_keys from fact exist in bridge'
    ELSE CONCAT('FAIL: ', CAST(COUNT(DISTINCT fact.factless_key) - COUNT(DISTINCT bridge.factless_key) AS STRING), 
                ' unique factless_keys missing from bridge')
  END as assertion_result
FROM `onyga-482313.OI.FACT_AMAZON_SEARCH_PERFORMANCE_WEEKLY` fact
LEFT JOIN `onyga-482313.OI.FACT_FACTLESS_BRIDGE` bridge
  ON fact.factless_key = bridge.factless_key;

-- ==========================================
-- Test 3.4: NULL ASIN Handling
-- ==========================================
-- Check if NULL ASIN handling is consistent
-- Fact uses: COALESCE(ASIN, 'NULL')
-- Bridge uses: COALESCE(asin, 'UNKNOWN')
-- This may cause mismatches for NULL ASINs
SELECT 
  'Test 3.4: NULL ASIN Handling' as test_name,
  COUNT(*) as null_asin_mismatch_count,
  CASE 
    WHEN COUNT(*) = 0 THEN 'PASS: NULL ASIN handling is consistent'
    ELSE CONCAT('WARNING: Found ', CAST(COUNT(*) AS STRING), 
                ' rows with NULL ASIN that may have key format issues')
  END as assertion_result,
  -- Sample of NULL ASIN issues
  ARRAY_AGG(STRUCT(
    fact.Reporting_Date,
    fact.ASIN,
    fact.factless_key as fact_factless_key,
    -- Expected bridge format with 'UNKNOWN' instead of 'NULL'
    CONCAT(
      FORMAT_DATE('%Y%m%d', fact.Reporting_Date),
      '-',
      'UNKNOWN'
    ) as expected_bridge_format_with_unknown
  ) LIMIT 20) as sample_null_asin_issues
FROM `onyga-482313.OI.FACT_AMAZON_SEARCH_PERFORMANCE_WEEKLY` fact
LEFT JOIN `onyga-482313.OI.FACT_FACTLESS_BRIDGE` bridge
  ON fact.factless_key = bridge.factless_key
WHERE fact.ASIN IS NULL
  AND bridge.factless_key IS NULL;

-- ==========================================
-- Test 3.5: Date Key Conversion Check
-- ==========================================
-- Verify that Reporting_Date (DATE) converts correctly to date_key (INT64) format
SELECT 
  'Test 3.5: Date Key Conversion Check' as test_name,
  COUNT(*) as date_conversion_mismatch_count,
  CASE 
    WHEN COUNT(*) = 0 THEN 'PASS: All date conversions are correct'
    ELSE CONCAT('WARNING: Found ', CAST(COUNT(*) AS STRING), ' rows with date conversion issues')
  END as assertion_result,
  -- Sample of date conversion issues
  ARRAY_AGG(STRUCT(
    fact.Reporting_Date,
    fact.ASIN,
    fact.factless_key as fact_factless_key,
    -- Expected bridge date_key
    CAST(FORMAT_DATE('%Y%m%d', fact.Reporting_Date) AS INT64) as expected_date_key,
    bridge.date_key as bridge_date_key
  ) LIMIT 20) as sample_date_conversion_issues
FROM `onyga-482313.OI.FACT_AMAZON_SEARCH_PERFORMANCE_WEEKLY` fact
LEFT JOIN `onyga-482313.OI.FACT_FACTLESS_BRIDGE` bridge
  ON fact.factless_key = bridge.factless_key
WHERE bridge.factless_key IS NULL
  AND fact.Reporting_Date IS NOT NULL;

-- ==========================================
-- Test 3.6: Alternative Key Format Matching
-- ==========================================
-- Try matching with alternative key formats to identify the issue
SELECT 
  'Test 3.6: Alternative Key Format Matching' as test_name,
  fact.Reporting_Date,
  fact.ASIN,
  fact.factless_key as fact_factless_key,
  -- Try matching with date_key as INT64
  bridge_by_date.factless_key as bridge_factless_key_by_date,
  -- Try matching with 'UNKNOWN' instead of 'NULL'
  bridge_by_unknown.factless_key as bridge_factless_key_by_unknown,
  -- Expected formats
  CONCAT(
    CAST(CAST(FORMAT_DATE('%Y%m%d', fact.Reporting_Date) AS INT64) AS STRING),
    '-',
    COALESCE(fact.ASIN, 'UNKNOWN')
  ) as alternative_key_format
FROM `onyga-482313.OI.FACT_AMAZON_SEARCH_PERFORMANCE_WEEKLY` fact
LEFT JOIN `onyga-482313.OI.FACT_FACTLESS_BRIDGE` bridge
  ON fact.factless_key = bridge.factless_key
LEFT JOIN `onyga-482313.OI.FACT_FACTLESS_BRIDGE` bridge_by_date
  ON CAST(FORMAT_DATE('%Y%m%d', fact.Reporting_Date) AS INT64) = bridge_by_date.date_key
  AND COALESCE(fact.ASIN, 'NULL') = bridge_by_date.asin
LEFT JOIN `onyga-482313.OI.FACT_FACTLESS_BRIDGE` bridge_by_unknown
  ON CONCAT(
    FORMAT_DATE('%Y%m%d', fact.Reporting_Date),
    '-',
    COALESCE(fact.ASIN, 'UNKNOWN')
  ) = bridge_by_unknown.factless_key
WHERE bridge.factless_key IS NULL
LIMIT 50;

-- ==========================================
-- Summary Report
-- ==========================================
SELECT 
  'SUMMARY: factless_key Referential Integrity' as summary_type,
  (SELECT COUNT(DISTINCT factless_key) FROM `onyga-482313.OI.FACT_AMAZON_SEARCH_PERFORMANCE_WEEKLY`) as total_fact_factless_keys,
  (SELECT COUNT(DISTINCT factless_key) FROM `onyga-482313.OI.FACT_FACTLESS_BRIDGE`) as total_bridge_factless_keys,
  (SELECT COUNT(*) FROM `onyga-482313.OI.FACT_AMAZON_SEARCH_PERFORMANCE_WEEKLY` fact
   LEFT JOIN `onyga-482313.OI.FACT_FACTLESS_BRIDGE` bridge
     ON fact.factless_key = bridge.factless_key
   WHERE bridge.factless_key IS NULL) as missing_factless_keys,
  (SELECT COUNT(*) FROM `onyga-482313.OI.FACT_AMAZON_SEARCH_PERFORMANCE_WEEKLY` fact
   LEFT JOIN `onyga-482313.OI.FACT_FACTLESS_BRIDGE` bridge
     ON fact.factless_key = bridge.factless_key
   WHERE fact.ASIN IS NULL
     AND bridge.factless_key IS NULL) as null_asin_mismatches,
  CASE 
    WHEN (SELECT COUNT(*) FROM `onyga-482313.OI.FACT_AMAZON_SEARCH_PERFORMANCE_WEEKLY` fact
          LEFT JOIN `onyga-482313.OI.FACT_FACTLESS_BRIDGE` bridge
            ON fact.factless_key = bridge.factless_key
          WHERE bridge.factless_key IS NULL) = 0
    THEN 'PASS: All factless_keys from fact table exist in bridge table'
    ELSE 'FAIL: Some factless_keys from fact table do not exist in bridge table - see detailed results above'
  END as overall_result;
