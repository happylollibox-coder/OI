-- =============================================
-- OI Data Integrity Validation Suite
-- =============================================
--
-- Purpose: Verify all DB connections are solid - no missing or duplicate rows
-- Run after: SP_POPULATE_FACTLESS_BRIDGE, SP_LOAD_FACT_*, SP_FACT_AMAZON_ADS
--
-- Connections validated:
--   1. FACT_FACTLESS_BRIDGE ↔ each fact (factless_key)
--   2. Ads_key: FACT_AMAZON_PERFORMANCE_DAILY ↔ FACT_AMAZON_ADS
--   3. Duplicate checks per fact (primary key grain)
--   4. Bridge: no duplicate factless_keys
--
-- =============================================

-- =============================================
-- SECTION 1: BRIDGE DUPLICATE CHECK
-- =============================================
SELECT 
  '1.1 Bridge: No duplicate factless_keys' as test_name,
  COUNT(*) as total_bridge_rows,
  COUNT(DISTINCT factless_key) as unique_factless_keys,
  COUNT(*) - COUNT(DISTINCT factless_key) as duplicate_count,
  CASE 
    WHEN COUNT(*) = COUNT(DISTINCT factless_key) THEN 'PASS'
    ELSE 'FAIL: Bridge has duplicate factless_keys'
  END as result
FROM `onyga-482313.OI.FACT_FACTLESS_BRIDGE`;

-- =============================================
-- SECTION 2: FACT → BRIDGE (Missing factless_keys in bridge)
-- =============================================

-- 2.1 FACT_AMAZON_PERFORMANCE_DAILY
SELECT 
  '2.1 Performance: factless_keys in bridge' as test_name,
  (SELECT COUNT(DISTINCT factless_key) FROM `onyga-482313.OI.FACT_AMAZON_PERFORMANCE_DAILY` WHERE factless_key IS NOT NULL) as fact_unique_keys,
  (SELECT COUNT(*) FROM (
    SELECT f.factless_key FROM `onyga-482313.OI.FACT_AMAZON_PERFORMANCE_DAILY` f
    WHERE f.factless_key IS NOT NULL
    AND EXISTS (SELECT 1 FROM `onyga-482313.OI.FACT_FACTLESS_BRIDGE` b WHERE b.factless_key = f.factless_key)
  )) as keys_in_bridge,
  (SELECT COUNT(*) FROM `onyga-482313.OI.FACT_AMAZON_PERFORMANCE_DAILY` f
   LEFT JOIN `onyga-482313.OI.FACT_FACTLESS_BRIDGE` b ON f.factless_key = b.factless_key
   WHERE f.factless_key IS NOT NULL AND b.factless_key IS NULL) as missing_in_bridge,
  CASE 
    WHEN (SELECT COUNT(*) FROM `onyga-482313.OI.FACT_AMAZON_PERFORMANCE_DAILY` f
          LEFT JOIN `onyga-482313.OI.FACT_FACTLESS_BRIDGE` b ON f.factless_key = b.factless_key
          WHERE f.factless_key IS NOT NULL AND b.factless_key IS NULL) = 0 
    THEN 'PASS' ELSE 'FAIL' 
  END as result;

-- 2.2 FACT_AMAZON_SEARCH_PERFORMANCE_WEEKLY
SELECT 
  '2.2 SearchWeekly: factless_keys in bridge' as test_name,
  (SELECT COUNT(DISTINCT factless_key) FROM `onyga-482313.OI.FACT_AMAZON_SEARCH_PERFORMANCE_WEEKLY` WHERE factless_key IS NOT NULL) as fact_unique_keys,
  (SELECT COUNT(*) FROM `onyga-482313.OI.FACT_AMAZON_SEARCH_PERFORMANCE_WEEKLY` f
   LEFT JOIN `onyga-482313.OI.FACT_FACTLESS_BRIDGE` b ON f.factless_key = b.factless_key
   WHERE f.factless_key IS NOT NULL AND b.factless_key IS NULL) as missing_in_bridge,
  CASE 
    WHEN (SELECT COUNT(*) FROM `onyga-482313.OI.FACT_AMAZON_SEARCH_PERFORMANCE_WEEKLY` f
          LEFT JOIN `onyga-482313.OI.FACT_FACTLESS_BRIDGE` b ON f.factless_key = b.factless_key
          WHERE f.factless_key IS NOT NULL AND b.factless_key IS NULL) = 0 
    THEN 'PASS' ELSE 'FAIL' 
  END as result;

-- 2.3 FACT_EXPERIMENT_DAILY
SELECT 
  '2.3 ExperimentDaily: factless_keys in bridge' as test_name,
  (SELECT COUNT(DISTINCT factless_key) FROM `onyga-482313.OI.FACT_EXPERIMENT_DAILY` WHERE factless_key IS NOT NULL) as fact_unique_keys,
  (SELECT COUNT(*) FROM `onyga-482313.OI.FACT_EXPERIMENT_DAILY` f
   LEFT JOIN `onyga-482313.OI.FACT_FACTLESS_BRIDGE` b ON f.factless_key = b.factless_key
   WHERE f.factless_key IS NOT NULL AND b.factless_key IS NULL) as missing_in_bridge,
  CASE 
    WHEN (SELECT COUNT(*) FROM `onyga-482313.OI.FACT_EXPERIMENT_DAILY` f
          LEFT JOIN `onyga-482313.OI.FACT_FACTLESS_BRIDGE` b ON f.factless_key = b.factless_key
          WHERE f.factless_key IS NOT NULL AND b.factless_key IS NULL) = 0 
    THEN 'PASS' ELSE 'FAIL' 
  END as result;

-- 2.4 FACT_INVENTORY_SNAPSHOT (uses computed key)
SELECT 
  '2.4 Inventory: keys in bridge' as test_name,
  (SELECT COUNT(*) FROM `onyga-482313.OI.FACT_INVENTORY_SNAPSHOT`) as fact_rows,
  (SELECT COUNT(*) FROM `onyga-482313.OI.FACT_INVENTORY_SNAPSHOT` f
   LEFT JOIN `onyga-482313.OI.FACT_FACTLESS_BRIDGE` b 
     ON CONCAT(CAST(FORMAT_DATE('%Y%m%d', f.Date) AS STRING), '-', COALESCE(f.ASIN, 'UNKNOWN')) = b.factless_key
   WHERE b.factless_key IS NULL) as missing_in_bridge,
  CASE 
    WHEN (SELECT COUNT(*) FROM `onyga-482313.OI.FACT_INVENTORY_SNAPSHOT` f
          LEFT JOIN `onyga-482313.OI.FACT_FACTLESS_BRIDGE` b 
            ON CONCAT(CAST(FORMAT_DATE('%Y%m%d', f.Date) AS STRING), '-', COALESCE(f.ASIN, 'UNKNOWN')) = b.factless_key
          WHERE b.factless_key IS NULL) = 0 
    THEN 'PASS' ELSE 'FAIL' 
  END as result;

-- 2.5 FACT_PURCHASE_ORDER (uses computed key)
SELECT 
  '2.5 PurchaseOrder: keys in bridge' as test_name,
  (SELECT COUNT(*) FROM `onyga-482313.OI.FACT_PURCHASE_ORDER`) as fact_rows,
  (SELECT COUNT(*) FROM `onyga-482313.OI.FACT_PURCHASE_ORDER` f
   LEFT JOIN `onyga-482313.OI.FACT_FACTLESS_BRIDGE` b 
     ON CONCAT(CAST(FORMAT_DATE('%Y%m%d', f.snapshot_date) AS STRING), '-', COALESCE(f.product_asin, 'UNKNOWN')) = b.factless_key
   WHERE b.factless_key IS NULL) as missing_in_bridge,
  CASE 
    WHEN (SELECT COUNT(*) FROM `onyga-482313.OI.FACT_PURCHASE_ORDER` f
          LEFT JOIN `onyga-482313.OI.FACT_FACTLESS_BRIDGE` b 
            ON CONCAT(CAST(FORMAT_DATE('%Y%m%d', f.snapshot_date) AS STRING), '-', COALESCE(f.product_asin, 'UNKNOWN')) = b.factless_key
          WHERE b.factless_key IS NULL) = 0 
    THEN 'PASS' ELSE 'FAIL' 
  END as result;

-- =============================================
-- SECTION 3: Ads_key CONNECTION (Performance ↔ Ads)
-- =============================================

-- 3.1 Performance Ads_keys that exist in Ads (expected: most should match)
SELECT 
  '3.1 Ads_key: Performance rows with Ads_key' as test_name,
  (SELECT COUNT(*) FROM `onyga-482313.OI.FACT_AMAZON_PERFORMANCE_DAILY` WHERE Ads_key IS NOT NULL) as perf_rows_with_ads_key,
  (SELECT COUNT(DISTINCT perf.Ads_key) FROM `onyga-482313.OI.FACT_AMAZON_PERFORMANCE_DAILY` perf
   INNER JOIN `onyga-482313.OI.FACT_AMAZON_ADS` ads ON perf.Ads_key = ads.Ads_key) as matching_ads_keys,
  (SELECT COUNT(DISTINCT perf.Ads_key) FROM `onyga-482313.OI.FACT_AMAZON_PERFORMANCE_DAILY` perf
   LEFT JOIN `onyga-482313.OI.FACT_AMAZON_ADS` ads ON perf.Ads_key = ads.Ads_key
   WHERE perf.Ads_key IS NOT NULL AND ads.Ads_key IS NULL) as perf_ads_keys_not_in_ads,
  'INFO: Ads/Performance may not fully align (Amazon data)' as note;

-- 3.2 Ads_keys in Ads not in Performance (expected: some - Ads has more granularity)
SELECT 
  '3.2 Ads_key: Ads rows with Ads_key' as test_name,
  (SELECT COUNT(DISTINCT Ads_key) FROM `onyga-482313.OI.FACT_AMAZON_ADS` WHERE Ads_key IS NOT NULL) as ads_unique_ads_keys,
  (SELECT COUNT(DISTINCT ads.Ads_key) FROM `onyga-482313.OI.FACT_AMAZON_ADS` ads
   INNER JOIN `onyga-482313.OI.FACT_AMAZON_PERFORMANCE_DAILY` perf ON ads.Ads_key = perf.Ads_key) as matching_in_perf,
  (SELECT COUNT(DISTINCT ads.Ads_key) FROM `onyga-482313.OI.FACT_AMAZON_ADS` ads
   LEFT JOIN `onyga-482313.OI.FACT_AMAZON_PERFORMANCE_DAILY` perf ON ads.Ads_key = perf.Ads_key
   WHERE perf.Ads_key IS NULL) as ads_keys_not_in_perf,
  'INFO: Expected - Ads has search-term grain' as note;

-- =============================================
-- SECTION 4: DUPLICATE ROW CHECKS (per fact primary key)
-- =============================================

-- 4.1 FACT_AMAZON_PERFORMANCE_DAILY (PK: DATE, PURCHASED_ASIN, advertised_asin, campaign_id, ad_group_id, keyword_id, DATA_SOURCE)
SELECT 
  '4.1 Performance: No duplicate PK' as test_name,
  (SELECT COUNT(*) FROM `onyga-482313.OI.FACT_AMAZON_PERFORMANCE_DAILY`) as total_rows,
  (SELECT COUNT(*) FROM (
    SELECT DATE, PURCHASED_ASIN, advertised_asin, campaign_id, ad_group_id, keyword_id, DATA_SOURCE, COUNT(*) as cnt
    FROM `onyga-482313.OI.FACT_AMAZON_PERFORMANCE_DAILY`
    GROUP BY 1, 2, 3, 4, 5, 6, 7
    HAVING COUNT(*) > 1
  )) as duplicate_groups,
  CASE WHEN (SELECT COUNT(*) FROM (
    SELECT DATE, PURCHASED_ASIN, advertised_asin, campaign_id, ad_group_id, keyword_id, DATA_SOURCE, COUNT(*) as cnt
    FROM `onyga-482313.OI.FACT_AMAZON_PERFORMANCE_DAILY`
    GROUP BY 1, 2, 3, 4, 5, 6, 7
    HAVING COUNT(*) > 1
  )) = 0 THEN 'PASS' ELSE 'FAIL' END as result;

-- 4.2 FACT_AMAZON_SEARCH_PERFORMANCE_WEEKLY
SELECT 
  '4.2 SearchWeekly: No duplicate PK' as test_name,
  (SELECT COUNT(*) FROM `onyga-482313.OI.FACT_AMAZON_SEARCH_PERFORMANCE_WEEKLY`) as total_rows,
  (SELECT COUNT(*) FROM (
    SELECT Reporting_Date, ASIN, Search_Query, COUNT(*) as cnt
    FROM `onyga-482313.OI.FACT_AMAZON_SEARCH_PERFORMANCE_WEEKLY`
    GROUP BY 1, 2, 3
    HAVING COUNT(*) > 1
  )) as duplicate_groups,
  CASE WHEN (SELECT COUNT(*) FROM (
    SELECT Reporting_Date, ASIN, Search_Query, COUNT(*) as cnt
    FROM `onyga-482313.OI.FACT_AMAZON_SEARCH_PERFORMANCE_WEEKLY`
    GROUP BY 1, 2, 3
    HAVING COUNT(*) > 1
  )) = 0 THEN 'PASS' ELSE 'FAIL' END as result;

-- 4.3 FACT_EXPERIMENT_DAILY
SELECT 
  '4.3 ExperimentDaily: No duplicate PK' as test_name,
  (SELECT COUNT(*) FROM `onyga-482313.OI.FACT_EXPERIMENT_DAILY`) as total_rows,
  (SELECT COUNT(*) FROM (
    SELECT snapshot_date, experiment_id, asin, COUNT(*) as cnt
    FROM `onyga-482313.OI.FACT_EXPERIMENT_DAILY`
    GROUP BY 1, 2, 3
    HAVING COUNT(*) > 1
  )) as duplicate_groups,
  CASE WHEN (SELECT COUNT(*) FROM (
    SELECT snapshot_date, experiment_id, asin, COUNT(*) as cnt
    FROM `onyga-482313.OI.FACT_EXPERIMENT_DAILY`
    GROUP BY 1, 2, 3
    HAVING COUNT(*) > 1
  )) = 0 THEN 'PASS' ELSE 'FAIL' END as result;

-- 4.4 FACT_AMAZON_ADS
SELECT 
  '4.4 Ads: No duplicate PK' as test_name,
  (SELECT COUNT(*) FROM `onyga-482313.OI.FACT_AMAZON_ADS`) as total_rows,
  (SELECT COUNT(*) FROM (
    SELECT campaign_id, ad_group_id, keyword_id, date, search_term, COUNT(*) as cnt
    FROM `onyga-482313.OI.FACT_AMAZON_ADS`
    GROUP BY 1, 2, 3, 4, 5
    HAVING COUNT(*) > 1
  )) as duplicate_groups,
  CASE WHEN (SELECT COUNT(*) FROM (
    SELECT campaign_id, ad_group_id, keyword_id, date, search_term, COUNT(*) as cnt
    FROM `onyga-482313.OI.FACT_AMAZON_ADS`
    GROUP BY 1, 2, 3, 4, 5
    HAVING COUNT(*) > 1
  )) = 0 THEN 'PASS' ELSE 'FAIL' END as result;

-- =============================================
-- SECTION 5: SUMMARY
-- =============================================
WITH integrity_checks AS (
  SELECT
    (SELECT COUNT(*) - COUNT(DISTINCT factless_key) FROM `onyga-482313.OI.FACT_FACTLESS_BRIDGE`) as bridge_duplicates,
    (SELECT COUNT(*) FROM `onyga-482313.OI.FACT_AMAZON_PERFORMANCE_DAILY` f
     LEFT JOIN `onyga-482313.OI.FACT_FACTLESS_BRIDGE` b ON f.factless_key = b.factless_key
     WHERE f.factless_key IS NOT NULL AND b.factless_key IS NULL) as perf_missing,
    (SELECT COUNT(*) FROM `onyga-482313.OI.FACT_AMAZON_SEARCH_PERFORMANCE_WEEKLY` f
     LEFT JOIN `onyga-482313.OI.FACT_FACTLESS_BRIDGE` b ON f.factless_key = b.factless_key
     WHERE f.factless_key IS NOT NULL AND b.factless_key IS NULL) as search_missing,
    (SELECT COUNT(*) FROM `onyga-482313.OI.FACT_EXPERIMENT_DAILY` f
     LEFT JOIN `onyga-482313.OI.FACT_FACTLESS_BRIDGE` b ON f.factless_key = b.factless_key
     WHERE f.factless_key IS NOT NULL AND b.factless_key IS NULL) as experiment_missing
)
SELECT 
  '=== INTEGRITY SUMMARY ===' as summary_type,
  (SELECT COUNT(*) FROM `onyga-482313.OI.FACT_FACTLESS_BRIDGE`) as bridge_total_rows,
  (SELECT COUNT(DISTINCT factless_key) FROM `onyga-482313.OI.FACT_FACTLESS_BRIDGE`) as bridge_unique_keys,
  c.perf_missing as perf_missing_in_bridge,
  c.search_missing as search_missing_in_bridge,
  c.experiment_missing as experiment_missing_in_bridge,
  CASE 
    WHEN c.bridge_duplicates = 0 AND c.perf_missing = 0 AND c.search_missing = 0 AND c.experiment_missing = 0
    THEN '✅ CORE INTEGRITY PASS'
    ELSE '❌ REVIEW FAILURES ABOVE'
  END as overall_result
FROM integrity_checks c;
