-- Simple test table to verify BigQuery connection
CREATE OR REPLACE TABLE `onyga-482313.OI.TEST_CURRENCY` (
  id INT64,
  test_value STRING
);

-- Insert test data
INSERT INTO `onyga-482313.OI.TEST_CURRENCY` (id, test_value)
VALUES (1, 'Test successful');

-- Query to verify
SELECT * FROM `onyga-482313.OI.TEST_CURRENCY`;