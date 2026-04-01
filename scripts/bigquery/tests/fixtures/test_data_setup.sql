-- =============================================
-- Test Data Setup: Pre-populate TEST_STG_SQP_WEEKLY for Update Tests
-- =============================================
-- Purpose: Create initial state in staging table for tests that check UPDATE behavior
-- Run this BEFORE running the stored procedure tests
-- =============================================

-- Setup Test Case 2: Existing record with CHANGED data
-- Pre-populate staging table with OLD values (will be updated by merge)
INSERT INTO `onyga-482313.OI_TEST.TEST_STG_SQP_WEEKLY` (
  query_text, ASIN, Year, Week, ob_date, week_start_date, week_end_date,
  impressions, clicks, click_through_rate, conversions, conversion_rate,
  sales_amount, sales_currency_code, query_rank, avg_position,
  ob_file_name, ob_marketplace_id, ob_seller_id, ob_transaction_id,
  ob_modified_date, ob_processed_at
)
VALUES (
  'test query two',              -- query_text (will match source)
  'B002TEST02',                  -- ASIN (will match source)
  2024,                          -- Year (Week 2 of 2024)
  2,                             -- Week
  DATE('2024-01-08'),            -- ob_date
  DATE('2024-01-08'),            -- week_start_date (Monday)
  DATE('2024-01-14'),            -- week_end_date (Sunday)
  100,                           -- impressions (OLD - will be updated to 150)
  10,                            -- clicks (OLD - will be updated to 15)
  10.0,                          -- click_through_rate (same - won't change)
  2,                             -- conversions (OLD - will be updated to 3)
  20.0,                          -- conversion_rate (same - won't change)
  50.00,                         -- sales_amount (OLD - will be updated to 75)
  'USD',                         -- sales_currency_code (same - won't change)
  1,                             -- query_rank (same - won't change)
  2.5,                           -- avg_position (same - won't change)
  'test_file_002.csv',           -- ob_file_name (same - won't change)
  'US',                          -- ob_marketplace_id (same - won't change)
  'TEST_SELLER_002',             -- ob_seller_id (same - won't change)
  'TXN002',                      -- ob_transaction_id (same - won't change)
  DATETIME('2024-01-15 10:00:00'), -- ob_modified_date (OLD - will be updated)
  '2024-01-15 10:05:00'          -- ob_processed_at (OLD - will be updated)
);

-- Setup Test Case 3: Existing record with UNCHANGED data
-- Pre-populate staging table with EXACT SAME values (should NOT be updated)
INSERT INTO `onyga-482313.OI_TEST.TEST_STG_SQP_WEEKLY` (
  query_text, ASIN, Year, Week, ob_date, week_start_date, week_end_date,
  impressions, clicks, click_through_rate, conversions, conversion_rate,
  sales_amount, sales_currency_code, query_rank, avg_position,
  ob_file_name, ob_marketplace_id, ob_seller_id, ob_transaction_id,
  ob_modified_date, ob_processed_at
)
VALUES (
  'test query three',            -- query_text (will match source)
  'B003TEST03',                  -- ASIN (will match source)
  2024,                          -- Year (Week 4 of 2024)
  4,                             -- Week
  DATE('2024-01-22'),            -- ob_date
  DATE('2024-01-22'),            -- week_start_date (Monday)
  DATE('2024-01-28'),            -- week_end_date (Sunday)
  200,                           -- impressions (SAME - should NOT update)
  20,                            -- clicks (SAME - should NOT update)
  10.0,                          -- click_through_rate (SAME)
  4,                             -- conversions (SAME - should NOT update)
  20.0,                          -- conversion_rate (SAME)
  100.00,                        -- sales_amount (SAME - should NOT update)
  'USD',                         -- sales_currency_code (SAME)
  1,                             -- query_rank (SAME)
  2.5,                           -- avg_position (SAME)
  'test_file_003.csv',           -- ob_file_name (SAME)
  'US',                          -- ob_marketplace_id (SAME)
  'TEST_SELLER_003',             -- ob_seller_id (SAME)
  'TXN003',                      -- ob_transaction_id (SAME)
  DATETIME('2024-01-22 10:00:00'), -- ob_modified_date (SAME - should NOT update)
  '2024-01-22 10:05:00'          -- ob_processed_at (SAME - should NOT update)
);

-- =============================================
-- Expected Results After Merge:
-- =============================================
-- Test Case 2: Row should have NEW values (impressions=150, clicks=15, etc.)
-- Test Case 3: Row should have SAME values (impressions=200, clicks=20, etc.) - NO UPDATE
-- Test Cases 1, 4, 5: Should INSERT new rows
-- =============================================
