-- =============================================
-- Test: SP_MERGE_SQP_WEEKLY - Test Case 1: New Record Insert
-- =============================================
-- Purpose: Verify that new records are inserted correctly
-- Expected: New row inserted with exact source values
-- =============================================

-- Step 1: Setup - Clear test tables
DELETE FROM `onyga-482313.OI_TEST.TEST_SOURCE` WHERE TRUE;
DELETE FROM `onyga-482313.OI_TEST.TEST_STG_SQP_WEEKLY` WHERE TRUE;

-- Step 2: Setup - Insert test source data (Test Case 1 only)
INSERT INTO `onyga-482313.OI_TEST.TEST_SOURCE` (
  query_text, ASIN, ob_date,
  impressions, clicks, click_through_rate, conversions, conversion_rate,
  sales_amount, sales_currency_code, query_rank, avg_position,
  ob_file_name, ob_marketplace_id, ob_seller_id, ob_transaction_id,
  ob_modified_date, ob_processed_at
)
VALUES (
  'test query one',              -- query_text
  'B001TEST01',                  -- ASIN
  DATE('2024-01-15'),            -- ob_date (Monday, Week 3 of 2024)
  100,                           -- impressions
  10,                            -- clicks
  10.0,                          -- click_through_rate (%)
  2,                             -- conversions
  20.0,                          -- conversion_rate (%)
  50.00,                         -- sales_amount
  'USD',                         -- sales_currency_code
  1,                             -- query_rank
  2.5,                           -- avg_position
  'test_file_001.csv',           -- ob_file_name
  'US',                          -- ob_marketplace_id
  'TEST_SELLER_001',             -- ob_seller_id
  'TXN001',                      -- ob_transaction_id
  DATETIME('2024-01-15 10:00:00'), -- ob_modified_date
  '2024-01-15 10:05:00'          -- ob_processed_at
);

-- Step 3: Get baseline - Row count before merge
DECLARE row_count_before INT64;
SET row_count_before = (SELECT COUNT(*) FROM `onyga-482313.OI_TEST.TEST_STG_SQP_WEEKLY`);

-- Step 4: Execute - Run test version of merge procedure
-- NOTE: This is a test version that uses TEST_SOURCE and TEST_STG_SQP_WEEKLY
-- In real test, would create TEST_SP_MERGE_SQP_WEEKLY that uses test tables
-- For now, we simulate the MERGE logic:

MERGE `onyga-482313.OI_TEST.TEST_STG_SQP_WEEKLY` AS stg
USING (
  SELECT
    query_text,
    ASIN,
    EXTRACT(YEAR FROM ob_date) AS Year,
    EXTRACT(WEEK FROM ob_date) AS Week,
    ob_date,
    DATE_TRUNC(ob_date, WEEK(MONDAY)) AS week_start_date,
    DATE_ADD(DATE_TRUNC(ob_date, WEEK(MONDAY)), INTERVAL 6 DAY) AS week_end_date,
    impressions,
    clicks,
    click_through_rate,
    conversions,
    conversion_rate,
    sales_amount,
    sales_currency_code,
    query_rank,
    avg_position,
    ob_file_name,
    ob_marketplace_id,
    ob_seller_id,
    ob_transaction_id,
    ob_modified_date,
    ob_processed_at
  FROM `onyga-482313.OI_TEST.TEST_SOURCE`
  WHERE ASIN IS NOT NULL
    AND query_text IS NOT NULL
) AS source
ON (
  COALESCE(stg.query_text, '') = COALESCE(source.query_text, '')
  AND COALESCE(stg.ASIN, '') = COALESCE(source.ASIN, '')
  AND stg.Year = source.Year
  AND stg.Week = source.Week
)
WHEN MATCHED AND (
  COALESCE(stg.impressions, 0) != COALESCE(source.impressions, 0)
  OR COALESCE(stg.clicks, 0) != COALESCE(source.clicks, 0)
  OR COALESCE(stg.click_through_rate, 0) != COALESCE(source.click_through_rate, 0)
  OR COALESCE(stg.conversions, 0) != COALESCE(source.conversions, 0)
  OR COALESCE(stg.conversion_rate, 0) != COALESCE(source.conversion_rate, 0)
  OR COALESCE(stg.sales_amount, 0) != COALESCE(source.sales_amount, 0)
  OR COALESCE(stg.query_rank, 0) != COALESCE(source.query_rank, 0)
  OR COALESCE(stg.avg_position, 0) != COALESCE(source.avg_position, 0)
  OR COALESCE(stg.sales_currency_code, '') != COALESCE(source.sales_currency_code, '')
  OR COALESCE(stg.ob_file_name, '') != COALESCE(source.ob_file_name, '')
  OR COALESCE(stg.ob_marketplace_id, '') != COALESCE(source.ob_marketplace_id, '')
  OR COALESCE(stg.ob_seller_id, '') != COALESCE(source.ob_seller_id, '')
  OR COALESCE(stg.ob_transaction_id, '') != COALESCE(source.ob_transaction_id, '')
  OR stg.ob_modified_date != source.ob_modified_date
  OR COALESCE(stg.ob_processed_at, '') != COALESCE(source.ob_processed_at, '')
) THEN
  UPDATE SET
    ob_date = source.ob_date,
    week_start_date = source.week_start_date,
    week_end_date = source.week_end_date,
    impressions = source.impressions,
    clicks = source.clicks,
    click_through_rate = source.click_through_rate,
    conversions = source.conversions,
    conversion_rate = source.conversion_rate,
    sales_amount = source.sales_amount,
    sales_currency_code = source.sales_currency_code,
    query_rank = source.query_rank,
    avg_position = source.avg_position,
    ob_file_name = source.ob_file_name,
    ob_marketplace_id = source.ob_marketplace_id,
    ob_seller_id = source.ob_seller_id,
    ob_transaction_id = source.ob_transaction_id,
    ob_modified_date = source.ob_modified_date,
    ob_processed_at = source.ob_processed_at
WHEN NOT MATCHED THEN
  INSERT (
    query_text, ASIN, Year, Week, ob_date, week_start_date, week_end_date,
    impressions, clicks, click_through_rate, conversions, conversion_rate,
    sales_amount, sales_currency_code, query_rank, avg_position,
    ob_file_name, ob_marketplace_id, ob_seller_id, ob_transaction_id,
    ob_modified_date, ob_processed_at
  )
  VALUES (
    source.query_text, source.ASIN, source.Year, source.Week, source.ob_date,
    source.week_start_date, source.week_end_date,
    source.impressions, source.clicks, source.click_through_rate,
    source.conversions, source.conversion_rate,
    source.sales_amount, source.sales_currency_code, source.query_rank, source.avg_position,
    source.ob_file_name, source.ob_marketplace_id, source.ob_seller_id, source.ob_transaction_id,
    source.ob_modified_date, source.ob_processed_at
  );

-- Step 5: Get result - Row count after merge
DECLARE row_count_after INT64;
SET row_count_after = (SELECT COUNT(*) FROM `onyga-482313.OI_TEST.TEST_STG_SQP_WEEKLY`);

-- Step 6: Assert - Verify row count increased by 1
SELECT 
  'Test Case 1: New Record Insert' as test_name,
  row_count_before as row_count_before,
  row_count_after as row_count_after,
  (row_count_after - row_count_before) as row_count_change,
  CASE 
    WHEN (row_count_after - row_count_before) = 1 THEN 'PASS'
    ELSE CONCAT('FAIL: Expected row count to increase by 1, but changed by ', (row_count_after - row_count_before))
  END as assertion_result;

-- Step 7: Assert - Verify row exists with expected values
SELECT 
  'Test Case 1: Row Values Verification' as test_name,
  CASE 
    WHEN COUNT(*) = 1 THEN 'PASS: Row found'
    ELSE CONCAT('FAIL: Expected 1 row, found ', COUNT(*))
  END as row_count_check,
  CASE 
    WHEN COUNT(*) = 1 AND 
         impressions = 100 AND 
         clicks = 10 AND 
         Year = 2024 AND 
         Week = 3 THEN 'PASS: All values match expected'
    ELSE CONCAT('FAIL: Values do not match expected. Actual: impressions=', MAX(impressions), ', clicks=', MAX(clicks))
  END as values_check,
  -- Actual values for debugging
  MAX(impressions) as actual_impressions,
  MAX(clicks) as actual_clicks,
  MAX(Year) as actual_year,
  MAX(Week) as actual_week
FROM `onyga-482313.OI_TEST.TEST_STG_SQP_WEEKLY`
WHERE query_text = 'test query one' 
  AND ASIN = 'B001TEST01';

-- Step 8: Display actual row for manual inspection
SELECT 
  'Test Case 1: Actual Row Data' as test_name,
  query_text,
  ASIN,
  Year,
  Week,
  ob_date,
  week_start_date,
  week_end_date,
  impressions,
  clicks,
  click_through_rate,
  conversions,
  conversion_rate,
  sales_amount,
  sales_currency_code
FROM `onyga-482313.OI_TEST.TEST_STG_SQP_WEEKLY`
WHERE query_text = 'test query one' AND ASIN = 'B001TEST01';
