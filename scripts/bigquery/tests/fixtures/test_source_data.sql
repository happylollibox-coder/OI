-- =============================================
-- Test Fixtures: Source Data for SP_MERGE_SQP_WEEKLY
-- =============================================
-- Purpose: Known test input data simulating openbridge-482712.DB.sp_ba_search_query_by_week_v1
-- These are the INPUT values that will be merged into STG_SQP_WEEKLY
-- =============================================

-- Test Case 1: New Record - Basic Query
-- Expected: Should INSERT new row
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

-- Test Case 2: Existing Record with CHANGED Data
-- Expected: Should UPDATE (impressions changed from 100 to 150)
INSERT INTO `onyga-482313.OI_TEST.TEST_SOURCE` (
  query_text, ASIN, ob_date,
  impressions, clicks, click_through_rate, conversions, conversion_rate,
  sales_amount, sales_currency_code, query_rank, avg_position,
  ob_file_name, ob_marketplace_id, ob_seller_id, ob_transaction_id,
  ob_modified_date, ob_processed_at
)
VALUES (
  'test query two',              -- query_text (same as existing in staging)
  'B002TEST02',                  -- ASIN (same as existing)
  DATE('2024-01-08'),            -- ob_date (Week 2 of 2024) - SAME as existing
  150,                           -- impressions (CHANGED from 100 to 150)
  15,                            -- clicks (CHANGED from 10 to 15)
  10.0,                          -- click_through_rate (same)
  3,                             -- conversions (CHANGED from 2 to 3)
  20.0,                          -- conversion_rate (same)
  75.00,                         -- sales_amount (CHANGED from 50 to 75)
  'USD',                         -- sales_currency_code (same)
  1,                             -- query_rank (same)
  2.5,                           -- avg_position (same)
  'test_file_002.csv',           -- ob_file_name (same)
  'US',                          -- ob_marketplace_id (same)
  'TEST_SELLER_002',             -- ob_seller_id (same)
  'TXN002',                      -- ob_transaction_id (same)
  DATETIME('2024-01-16 10:00:00'), -- ob_modified_date (CHANGED - newer)
  '2024-01-16 10:05:00'          -- ob_processed_at (CHANGED)
);

-- Test Case 3: Existing Record with UNCHANGED Data
-- Expected: Should NOT UPDATE (all values identical)
INSERT INTO `onyga-482313.OI_TEST.TEST_SOURCE` (
  query_text, ASIN, ob_date,
  impressions, clicks, click_through_rate, conversions, conversion_rate,
  sales_amount, sales_currency_code, query_rank, avg_position,
  ob_file_name, ob_marketplace_id, ob_seller_id, ob_transaction_id,
  ob_modified_date, ob_processed_at
)
VALUES (
  'test query three',            -- query_text (same as existing)
  'B003TEST03',                  -- ASIN (same as existing)
  DATE('2024-01-22'),            -- ob_date (Week 4 of 2024) - SAME as existing
  200,                           -- impressions (SAME as existing)
  20,                            -- clicks (SAME as existing)
  10.0,                          -- click_through_rate (SAME)
  4,                             -- conversions (SAME)
  20.0,                          -- conversion_rate (SAME)
  100.00,                        -- sales_amount (SAME)
  'USD',                         -- sales_currency_code (SAME)
  1,                             -- query_rank (SAME)
  2.5,                           -- avg_position (SAME)
  'test_file_003.csv',           -- ob_file_name (SAME)
  'US',                          -- ob_marketplace_id (SAME)
  'TEST_SELLER_003',             -- ob_seller_id (SAME)
  'TXN003',                      -- ob_transaction_id (SAME)
  DATETIME('2024-01-22 10:00:00'), -- ob_modified_date (SAME)
  '2024-01-22 10:05:00'          -- ob_processed_at (SAME)
);

-- Test Case 4: Edge Case - NULL values
-- Expected: Should INSERT (handles NULLs correctly)
INSERT INTO `onyga-482313.OI_TEST.TEST_SOURCE` (
  query_text, ASIN, ob_date,
  impressions, clicks, click_through_rate, conversions, conversion_rate,
  sales_amount, sales_currency_code, query_rank, avg_position,
  ob_file_name, ob_marketplace_id, ob_seller_id, ob_transaction_id,
  ob_modified_date, ob_processed_at
)
VALUES (
  'test query nulls',            -- query_text
  'B004TEST04',                  -- ASIN
  DATE('2024-02-05'),            -- ob_date (Week 6 of 2024)
  50,                            -- impressions
  5,                             -- clicks
  NULL,                          -- click_through_rate (NULL)
  NULL,                          -- conversions (NULL)
  NULL,                          -- conversion_rate (NULL)
  NULL,                          -- sales_amount (NULL)
  NULL,                          -- sales_currency_code (NULL)
  NULL,                          -- query_rank (NULL)
  NULL,                          -- avg_position (NULL)
  NULL,                          -- ob_file_name (NULL)
  NULL,                          -- ob_marketplace_id (NULL)
  NULL,                          -- ob_seller_id (NULL)
  NULL,                          -- ob_transaction_id (NULL)
  NULL,                          -- ob_modified_date (NULL)
  NULL                           -- ob_processed_at (NULL)
);

-- Test Case 5: Edge Case - Zero values
-- Expected: Should INSERT (handles zeros correctly)
INSERT INTO `onyga-482313.OI_TEST.TEST_SOURCE` (
  query_text, ASIN, ob_date,
  impressions, clicks, click_through_rate, conversions, conversion_rate,
  sales_amount, sales_currency_code, query_rank, avg_position,
  ob_file_name, ob_marketplace_id, ob_seller_id, ob_transaction_id,
  ob_modified_date, ob_processed_at
)
VALUES (
  'test query zeros',            -- query_text
  'B005TEST05',                  -- ASIN
  DATE('2024-02-12'),            -- ob_date (Week 7 of 2024)
  0,                             -- impressions (ZERO)
  0,                             -- clicks (ZERO)
  0.0,                           -- click_through_rate (ZERO)
  0,                             -- conversions (ZERO)
  0.0,                           -- conversion_rate (ZERO)
  0.00,                          -- sales_amount (ZERO)
  'USD',                         -- sales_currency_code
  999,                           -- query_rank (high number for low rank)
  NULL,                          -- avg_position (NULL)
  'test_file_005.csv',           -- ob_file_name
  'US',                          -- ob_marketplace_id
  'TEST_SELLER_005',             -- ob_seller_id
  'TXN005',                      -- ob_transaction_id
  DATETIME('2024-02-12 10:00:00'), -- ob_modified_date
  '2024-02-12 10:05:00'          -- ob_processed_at
);

-- =============================================
-- Note: Before running tests, populate TEST_STG_SQP_WEEKLY with:
-- - Test Case 2 base data: query_text='test query two', ASIN='B002TEST02', Year=2024, Week=2, impressions=100
-- - Test Case 3 base data: query_text='test query three', ASIN='B003TEST03', Year=2024, Week=4, impressions=200
-- See fixtures/test_data_setup.sql for pre-population queries
-- =============================================
