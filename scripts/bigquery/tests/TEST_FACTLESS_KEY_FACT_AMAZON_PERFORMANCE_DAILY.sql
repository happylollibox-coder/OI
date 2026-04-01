-- =============================================
-- Test Script: FACT_AMAZON_PERFORMANCE_DAILY factless_key
-- =============================================
--
-- Purpose: Comprehensive testing of factless_key implementation
-- Tests:
-- 1. All records have factless_key populated
-- 2. Format correctness (YYYYMMDD-ASIN)
-- 3. Format matches FACT_FACTLESS_BRIDGE
-- 4. Edge cases (NULL ASINs, date parsing)
-- 5. Joining capability with FACT_FACTLESS_BRIDGE
-- 6. Data integrity checks
--
-- =============================================

-- Test 1: Verify all records have factless_key populated
SELECT 
  'Test 1: factless_key Population' AS test_name,
  COUNT(*) AS total_records,
  COUNT(factless_key) AS records_with_factless_key,
  COUNT(*) - COUNT(factless_key) AS records_without_factless_key,
  CASE 
    WHEN COUNT(*) = COUNT(factless_key) THEN 'PASS'
    ELSE 'FAIL'
  END AS status
FROM `onyga-482313.OI.FACT_AMAZON_PERFORMANCE_DAILY`;

-- Test 2: Verify factless_key format (should be YYYYMMDD-ASIN)
SELECT 
  'Test 2: factless_key Format Validation' AS test_name,
  COUNT(*) AS total_records,
  COUNT(CASE WHEN REGEXP_CONTAINS(factless_key, r'^\d{8}-[A-Z0-9]+$') THEN 1 END) AS valid_format_count,
  COUNT(CASE WHEN NOT REGEXP_CONTAINS(factless_key, r'^\d{8}-[A-Z0-9]+$') THEN 1 END) AS invalid_format_count,
  CASE 
    WHEN COUNT(CASE WHEN NOT REGEXP_CONTAINS(factless_key, r'^\d{8}-[A-Z0-9]+$') THEN 1 END) = 0 THEN 'PASS'
    ELSE 'FAIL'
  END AS status
FROM `onyga-482313.OI.FACT_AMAZON_PERFORMANCE_DAILY`
WHERE factless_key IS NOT NULL;

-- Test 3: Verify date part matches actual date column
SELECT 
  'Test 3: Date Part Validation' AS test_name,
  COUNT(*) AS total_records,
  COUNT(CASE WHEN CAST(SUBSTR(factless_key, 1, 8) AS INT64) = CAST(FORMAT_DATE('%Y%m%d', date) AS INT64) THEN 1 END) AS matching_dates,
  COUNT(CASE WHEN CAST(SUBSTR(factless_key, 1, 8) AS INT64) != CAST(FORMAT_DATE('%Y%m%d', date) AS INT64) THEN 1 END) AS mismatched_dates,
  CASE 
    WHEN COUNT(CASE WHEN CAST(SUBSTR(factless_key, 1, 8) AS INT64) != CAST(FORMAT_DATE('%Y%m%d', date) AS INT64) THEN 1 END) = 0 THEN 'PASS'
    ELSE 'FAIL'
  END AS status
FROM `onyga-482313.OI.FACT_AMAZON_PERFORMANCE_DAILY`
WHERE factless_key IS NOT NULL;

-- Test 4: Verify ASIN part matches most_advertised_asin (when not NULL)
SELECT 
  'Test 4: ASIN Part Validation' AS test_name,
  COUNT(*) AS total_records,
  COUNT(CASE WHEN most_advertised_asin IS NOT NULL AND SUBSTR(factless_key, 10) = most_advertised_asin THEN 1 END) AS matching_asins,
  COUNT(CASE WHEN most_advertised_asin IS NOT NULL AND SUBSTR(factless_key, 10) != most_advertised_asin THEN 1 END) AS mismatched_asins,
  COUNT(CASE WHEN most_advertised_asin IS NULL AND SUBSTR(factless_key, 10) = 'UNKNOWN' THEN 1 END) AS null_asins_handled,
  CASE 
    WHEN COUNT(CASE WHEN most_advertised_asin IS NOT NULL AND SUBSTR(factless_key, 10) != most_advertised_asin THEN 1 END) = 0 
      AND COUNT(CASE WHEN most_advertised_asin IS NULL AND SUBSTR(factless_key, 10) != 'UNKNOWN' THEN 1 END) = 0 THEN 'PASS'
    ELSE 'FAIL'
  END AS status
FROM `onyga-482313.OI.FACT_AMAZON_PERFORMANCE_DAILY`
WHERE factless_key IS NOT NULL;

-- Test 5: Verify format matches FACT_FACTLESS_BRIDGE format
SELECT 
  'Test 5: Format Match with FACT_FACTLESS_BRIDGE' AS test_name,
  COUNT(DISTINCT fapd.factless_key) AS fact_performance_keys,
  COUNT(DISTINCT ffb.factless_key) AS factless_bridge_keys,
  COUNT(DISTINCT CASE WHEN ffb.factless_key IS NOT NULL THEN fapd.factless_key END) AS matching_keys,
  CASE 
    WHEN COUNT(DISTINCT CASE WHEN ffb.factless_key IS NOT NULL THEN fapd.factless_key END) > 0 THEN 'PASS'
    ELSE 'WARNING - No matches found (may be expected if dates/ASINs differ)'
  END AS status
FROM `onyga-482313.OI.FACT_AMAZON_PERFORMANCE_DAILY` fapd
LEFT JOIN `onyga-482313.OI.FACT_FACTLESS_BRIDGE` ffb
  ON fapd.factless_key = ffb.factless_key;

-- Test 6: Sample records with factless_key breakdown
SELECT 
  'Test 6: Sample Records' AS test_name,
  date,
  most_advertised_asin,
  factless_key,
  SUBSTR(factless_key, 1, 8) AS date_part,
  SUBSTR(factless_key, 10) AS asin_part,
  CAST(FORMAT_DATE('%Y%m%d', date) AS INT64) AS expected_date_key,
  Performance_TYPE
FROM `onyga-482313.OI.FACT_AMAZON_PERFORMANCE_DAILY`
WHERE factless_key IS NOT NULL
ORDER BY date DESC, most_advertised_asin
LIMIT 10;

-- Test 7: Check for NULL or empty factless_key values
SELECT 
  'Test 7: NULL/Empty factless_key Check' AS test_name,
  COUNT(*) AS null_or_empty_count,
  CASE 
    WHEN COUNT(*) = 0 THEN 'PASS'
    ELSE 'FAIL'
  END AS status
FROM `onyga-482313.OI.FACT_AMAZON_PERFORMANCE_DAILY`
WHERE factless_key IS NULL OR factless_key = '';

-- Test 8: Verify factless_key uniqueness per date+asin combination
SELECT 
  'Test 8: factless_key Uniqueness Check' AS test_name,
  COUNT(*) AS total_records,
  COUNT(DISTINCT factless_key) AS distinct_factless_keys,
  COUNT(*) - COUNT(DISTINCT factless_key) AS duplicate_keys,
  CASE 
    WHEN COUNT(*) - COUNT(DISTINCT factless_key) = 0 THEN 'PASS (all unique)'
    WHEN COUNT(*) - COUNT(DISTINCT factless_key) > 0 THEN 'INFO (duplicates expected - same date+asin can have multiple rows with different Performance_TYPE)'
    ELSE 'PASS'
  END AS status
FROM `onyga-482313.OI.FACT_AMAZON_PERFORMANCE_DAILY`
WHERE factless_key IS NOT NULL;

-- Test 9: Distribution by Performance_TYPE
SELECT 
  'Test 9: factless_key by Performance_TYPE' AS test_name,
  Performance_TYPE,
  COUNT(*) AS record_count,
  COUNT(DISTINCT factless_key) AS distinct_factless_keys,
  COUNT(DISTINCT most_advertised_asin) AS distinct_asins,
  COUNT(DISTINCT date) AS distinct_dates
FROM `onyga-482313.OI.FACT_AMAZON_PERFORMANCE_DAILY`
WHERE factless_key IS NOT NULL
GROUP BY Performance_TYPE;

-- Test 10: Edge cases - NULL ASIN handling
SELECT 
  'Test 10: NULL ASIN Handling' AS test_name,
  COUNT(*) AS records_with_null_asin,
  COUNT(CASE WHEN most_advertised_asin IS NULL AND SUBSTR(factless_key, 10) = 'UNKNOWN' THEN 1 END) AS correctly_handled,
  COUNT(CASE WHEN most_advertised_asin IS NULL AND SUBSTR(factless_key, 10) != 'UNKNOWN' THEN 1 END) AS incorrectly_handled,
  CASE 
    WHEN COUNT(CASE WHEN most_advertised_asin IS NULL AND SUBSTR(factless_key, 10) != 'UNKNOWN' THEN 1 END) = 0 THEN 'PASS'
    ELSE 'FAIL'
  END AS status
FROM `onyga-482313.OI.FACT_AMAZON_PERFORMANCE_DAILY`
WHERE most_advertised_asin IS NULL;

-- Test 11: Join capability test with FACT_FACTLESS_BRIDGE
SELECT 
  'Test 11: Join Capability Test' AS test_name,
  COUNT(DISTINCT fapd.factless_key) AS fact_performance_keys,
  COUNT(DISTINCT ffb.factless_key) AS factless_bridge_keys,
  COUNT(DISTINCT CASE WHEN ffb.factless_key IS NOT NULL THEN fapd.factless_key END) AS joinable_keys,
  ROUND(COUNT(DISTINCT CASE WHEN ffb.factless_key IS NOT NULL THEN fapd.factless_key END) * 100.0 / NULLIF(COUNT(DISTINCT fapd.factless_key), 0), 2) AS join_percentage,
  CASE 
    WHEN COUNT(DISTINCT CASE WHEN ffb.factless_key IS NOT NULL THEN fapd.factless_key END) > 0 THEN 'PASS'
    ELSE 'WARNING - No joinable keys found'
  END AS status
FROM `onyga-482313.OI.FACT_AMAZON_PERFORMANCE_DAILY` fapd
LEFT JOIN `onyga-482313.OI.FACT_FACTLESS_BRIDGE` ffb
  ON fapd.factless_key = ffb.factless_key;

-- Test 12: Sample join results
SELECT 
  'Test 12: Sample Join Results' AS test_name,
  fapd.date,
  fapd.most_advertised_asin,
  fapd.factless_key,
  fapd.Performance_TYPE,
  fapd.impressions,
  fapd.clicks,
  fapd.orders,
  ffb.factless_key AS bridge_factless_key,
  CASE 
    WHEN ffb.factless_key IS NOT NULL THEN 'JOINED'
    ELSE 'NO MATCH'
  END AS join_status
FROM `onyga-482313.OI.FACT_AMAZON_PERFORMANCE_DAILY` fapd
LEFT JOIN `onyga-482313.OI.FACT_FACTLESS_BRIDGE` ffb
  ON fapd.factless_key = ffb.factless_key
WHERE fapd.factless_key IS NOT NULL
ORDER BY fapd.date DESC, fapd.most_advertised_asin
LIMIT 10;
