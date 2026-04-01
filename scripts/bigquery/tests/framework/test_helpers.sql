-- =============================================
-- Test Helpers: Common Test Utilities
-- =============================================
-- Purpose: Reusable functions and queries for tests
-- =============================================

-- Helper 1: Create Test Dataset (run once)
-- CREATE SCHEMA IF NOT EXISTS `onyga-482313.OI_TEST`;

-- Helper 2: Create Test Source Table (run once)
-- This mimics openbridge-482712.DB.sp_ba_search_query_by_week_v1
CREATE OR REPLACE TABLE `onyga-482313.OI_TEST.TEST_SOURCE` (
  query_text STRING,
  ASIN STRING,
  ob_date DATE,
  impressions INT64,
  clicks INT64,
  click_through_rate FLOAT64,
  conversions INT64,
  conversion_rate FLOAT64,
  sales_amount FLOAT64,
  sales_currency_code STRING,
  query_rank INT64,
  avg_position FLOAT64,
  ob_file_name STRING,
  ob_marketplace_id STRING,
  ob_seller_id STRING,
  ob_transaction_id STRING,
  ob_modified_date DATETIME,
  ob_processed_at STRING
);

-- Helper 3: Create Test Staging Table (run once)
-- This mirrors OI.STG_SQP_WEEKLY structure
CREATE OR REPLACE TABLE `onyga-482313.OI_TEST.TEST_STG_SQP_WEEKLY` (
  query_text STRING,
  ASIN STRING,
  Year INT64 NOT NULL,
  Week INT64 NOT NULL,
  ob_date DATE,
  week_start_date DATE NOT NULL,
  week_end_date DATE NOT NULL,
  impressions INT64,
  clicks INT64,
  click_through_rate FLOAT64,
  conversions INT64,
  conversion_rate FLOAT64,
  sales_amount FLOAT64,
  sales_currency_code STRING,
  query_rank INT64,
  avg_position FLOAT64,
  ob_file_name STRING,
  ob_marketplace_id STRING,
  ob_seller_id STRING,
  ob_transaction_id STRING,
  ob_modified_date DATETIME,
  ob_processed_at STRING
);

-- Helper 4: Clear Test Tables (run before each test)
-- DELETE FROM `onyga-482313.OI_TEST.TEST_SOURCE`;
-- DELETE FROM `onyga-482313.OI_TEST.TEST_STG_SQP_WEEKLY`;

-- Helper 5: Get Row Count Before Merge
-- SELECT COUNT(*) as row_count_before FROM `onyga-482313.OI_TEST.TEST_STG_SQP_WEEKLY`;

-- Helper 6: Get Row Count After Merge
-- SELECT COUNT(*) as row_count_after FROM `onyga-482313.OI_TEST.TEST_STG_SQP_WEEKLY`;

-- Helper 7: Get Actual Values for Test Case 1
-- SELECT * FROM `onyga-482313.OI_TEST.TEST_STG_SQP_WEEKLY`
-- WHERE query_text = 'test query one' AND ASIN = 'B001TEST01';

-- Helper 8: Get Actual Values for Test Case 2
-- SELECT * FROM `onyga-482313.OI_TEST.TEST_STG_SQP_WEEKLY`
-- WHERE query_text = 'test query two' AND ASIN = 'B002TEST02';

-- Helper 9: Get Actual Values for Test Case 3
-- SELECT * FROM `onyga-482313.OI_TEST.TEST_STG_SQP_WEEKLY`
-- WHERE query_text = 'test query three' AND ASIN = 'B003TEST03';
