-- =============================================
-- Test Assertions: Pass/Fail Check Functions
-- =============================================
-- Purpose: Common assertion functions for tests
-- Usage: Use these queries to validate test results
-- =============================================

-- Assertion 1: Row Count Changed By N
-- Returns: 'PASS' if row_count_after - row_count_before = expected_change, else 'FAIL'
-- Example: Use to check if INSERT added 1 row

-- Assertion 2: Row Exists
-- Returns: 'PASS' if row found, else 'FAIL'
-- Example: Check if new record was inserted

-- Assertion 3: Row Values Match Expected
-- Returns: 'PASS' if all values match expected, else 'FAIL' with actual values
-- Example: Compare actual vs expected for specific test case

-- Assertion 4: Row Not Updated (values unchanged)
-- Returns: 'PASS' if values same as before, else 'FAIL'
-- Example: Verify Test Case 3 didn't update unchanged data

-- Assertion 5: Row Updated (values changed)
-- Returns: 'PASS' if values changed to new values, else 'FAIL'
-- Example: Verify Test Case 2 updated with new values

-- =============================================
-- Example Assertion Queries:
-- =============================================

-- Assert: Row count increased by 1 (Test Case 1)
-- Expected: row_count_after = row_count_before + 1
WITH counts AS (
  SELECT 
    (SELECT COUNT(*) FROM `onyga-482313.OI_TEST.TEST_STG_SQP_WEEKLY` WHERE query_text = 'test query one') as actual_count,
    1 as expected_change
)
SELECT 
  CASE 
    WHEN actual_count = expected_change THEN 'PASS'
    ELSE CONCAT('FAIL: Expected ', expected_change, ' row(s), got ', actual_count)
  END as assertion_result
FROM counts;

-- Assert: Specific row exists with expected values (Test Case 1)
-- Expected: impressions = 100, clicks = 10, etc.
SELECT 
  CASE 
    WHEN COUNT(*) = 1 THEN 'PASS: Row found'
    ELSE 'FAIL: Row not found or multiple rows'
  END as assertion_result
FROM `onyga-482313.OI_TEST.TEST_STG_SQP_WEEKLY`
WHERE query_text = 'test query one' 
  AND ASIN = 'B001TEST01'
  AND impressions = 100
  AND clicks = 10
  AND Year = 2024
  AND Week = 3;

-- Assert: Row updated with new values (Test Case 2)
-- Expected: impressions = 150 (was 100), clicks = 15 (was 10)
SELECT 
  CASE 
    WHEN impressions = 150 AND clicks = 15 AND conversions = 3 THEN 'PASS: Values updated'
    ELSE CONCAT('FAIL: Expected impressions=150, clicks=15, got impressions=', impressions, ', clicks=', clicks)
  END as assertion_result
FROM `onyga-482313.OI_TEST.TEST_STG_SQP_WEEKLY`
WHERE query_text = 'test query two' AND ASIN = 'B002TEST02';

-- Assert: Row NOT updated (values unchanged) (Test Case 3)
-- Expected: impressions = 200 (unchanged), clicks = 20 (unchanged)
SELECT 
  CASE 
    WHEN impressions = 200 AND clicks = 20 THEN 'PASS: Values unchanged (no update)'
    ELSE CONCAT('FAIL: Values changed when they should not. Expected impressions=200, got ', impressions)
  END as assertion_result
FROM `onyga-482313.OI_TEST.TEST_STG_SQP_WEEKLY`
WHERE query_text = 'test query three' AND ASIN = 'B003TEST03';
