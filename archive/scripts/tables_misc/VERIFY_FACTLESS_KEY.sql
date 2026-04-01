-- =============================================
-- Verify factless_key has been populated
-- =============================================

-- Check FACT_FACTLESS_BRIDGE
SELECT 
  'FACT_FACTLESS_BRIDGE' AS table_name,
  COUNT(*) AS total_rows,
  COUNT(factless_key) AS rows_with_factless_key,
  COUNT(*) - COUNT(factless_key) AS rows_without_factless_key,
  COUNT(DISTINCT factless_key) AS distinct_factless_keys
FROM `onyga-482313.OI.FACT_FACTLESS_BRIDGE`;

-- Check FACT_INVENTORY_SNAPSHOT
SELECT 
  'FACT_INVENTORY_SNAPSHOT' AS table_name,
  COUNT(*) AS total_rows,
  COUNT(factless_key) AS rows_with_factless_key,
  COUNT(*) - COUNT(factless_key) AS rows_without_factless_key,
  COUNT(DISTINCT factless_key) AS distinct_factless_keys
FROM `onyga-482313.OI.FACT_INVENTORY_SNAPSHOT`;

-- Check FACT_PURCHASE_ORDER
SELECT 
  'FACT_PURCHASE_ORDER' AS table_name,
  COUNT(*) AS total_rows,
  COUNT(factless_key) AS rows_with_factless_key,
  COUNT(*) - COUNT(factless_key) AS rows_without_factless_key,
  COUNT(DISTINCT factless_key) AS distinct_factless_keys
FROM `onyga-482313.OI.FACT_PURCHASE_ORDER`;

-- Check FACT_FINANCIAL_TRANSACTIONS
SELECT 
  'FACT_FINANCIAL_TRANSACTIONS' AS table_name,
  COUNT(*) AS total_rows,
  COUNT(factless_key) AS rows_with_factless_key,
  COUNT(*) - COUNT(factless_key) AS rows_without_factless_key,
  COUNT(DISTINCT factless_key) AS distinct_factless_keys
FROM `onyga-482313.OI.FACT_FINANCIAL_TRANSACTIONS`;

-- Sample rows from each table
SELECT 'FACT_FACTLESS_BRIDGE Sample' AS sample_type, date_key, asin, factless_key
FROM `onyga-482313.OI.FACT_FACTLESS_BRIDGE`
LIMIT 5;

SELECT 'FACT_INVENTORY_SNAPSHOT Sample' AS sample_type, Date, ASIN, factless_key
FROM `onyga-482313.OI.FACT_INVENTORY_SNAPSHOT`
LIMIT 5;

SELECT 'FACT_PURCHASE_ORDER Sample' AS sample_type, snapshot_date, product_asin, factless_key
FROM `onyga-482313.OI.FACT_PURCHASE_ORDER`
LIMIT 5;

SELECT 'FACT_FINANCIAL_TRANSACTIONS Sample' AS sample_type, transaction_date, JSON_EXTRACT_SCALAR(source_metadata, '$.asin') AS asin, factless_key
FROM `onyga-482313.OI.FACT_FINANCIAL_TRANSACTIONS`
WHERE factless_key IS NOT NULL
LIMIT 5;
