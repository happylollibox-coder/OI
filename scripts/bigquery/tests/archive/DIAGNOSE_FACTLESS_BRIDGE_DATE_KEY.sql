-- =============================================
-- Diagnostic Query: Check for Missing date_key in FACT_FACTLESS_BRIDGE
-- =============================================
-- Purpose: Identify date_key issues in the factless bridge table
-- =============================================

-- 1. Check for NULL date_key values (should not exist)
SELECT 
  'NULL date_key check' AS check_type,
  COUNT(*) AS null_count,
  COUNT(*) * 100.0 / (SELECT COUNT(*) FROM `onyga-482313.OI.FACT_FACTLESS_BRIDGE`) AS null_percentage
FROM `onyga-482313.OI.FACT_FACTLESS_BRIDGE`
WHERE date_key IS NULL;

-- 2. Check for -1 date_key values (placeholder for missing dates)
SELECT 
  'Missing date_key (-1) check' AS check_type,
  COUNT(*) AS missing_count,
  COUNT(*) * 100.0 / (SELECT COUNT(*) FROM `onyga-482313.OI.FACT_FACTLESS_BRIDGE`) AS missing_percentage
FROM `onyga-482313.OI.FACT_FACTLESS_BRIDGE`
WHERE date_key = -1;

-- 3. Check date_key values that don't exist in DIM_TIME
SELECT 
  'date_key not in DIM_TIME' AS check_type,
  COUNT(DISTINCT b.date_key) AS unmatched_date_keys,
  COUNT(*) AS unmatched_rows
FROM `onyga-482313.OI.FACT_FACTLESS_BRIDGE` b
LEFT JOIN `onyga-482313.OI.DIM_TIME` t ON b.date_key = t.date_key
WHERE t.date_key IS NULL
  AND b.date_key != -1;  -- Exclude -1 placeholder

-- 4. Sample of date_key values that don't match DIM_TIME
SELECT 
  'Sample unmatched date_keys' AS check_type,
  b.date_key,
  COUNT(*) AS row_count
FROM `onyga-482313.OI.FACT_FACTLESS_BRIDGE` b
LEFT JOIN `onyga-482313.OI.DIM_TIME` t ON b.date_key = t.date_key
WHERE t.date_key IS NULL
  AND b.date_key != -1
GROUP BY b.date_key
ORDER BY row_count DESC
LIMIT 10;

-- 5. Check date_key distribution by source fact table
-- (This helps identify which fact table is contributing missing dates)
WITH fact_sources AS (
  -- FACT_INVENTORY_SNAPSHOT
  SELECT 
    'FACT_INVENTORY_SNAPSHOT' AS source_table,
    COALESCE(CAST(FORMAT_DATE('%Y%m%d', Date) AS INT64), -1) AS date_key,
    COUNT(*) AS row_count
  FROM `onyga-482313.OI.FACT_INVENTORY_SNAPSHOT`
  GROUP BY date_key
  
  UNION ALL
  
  -- FACT_FINANCIAL_TRANSACTIONS
  SELECT 
    'FACT_FINANCIAL_TRANSACTIONS' AS source_table,
    COALESCE(CAST(FORMAT_DATE('%Y%m%d', transaction_date) AS INT64), -1) AS date_key,
    COUNT(*) AS row_count
  FROM `onyga-482313.OI.FACT_FINANCIAL_TRANSACTIONS`
  GROUP BY date_key
  
  UNION ALL
  
  -- FACT_PURCHASE_ORDER
  SELECT 
    'FACT_PURCHASE_ORDER' AS source_table,
    COALESCE(CAST(FORMAT_DATE('%Y%m%d', snapshot_date) AS INT64), -1) AS date_key,
    COUNT(*) AS row_count
  FROM `onyga-482313.OI.FACT_PURCHASE_ORDER`
  GROUP BY date_key
  
  UNION ALL
  
  -- FACT_AMAZON_PERFORMANCE_DAILY
  SELECT 
    'FACT_AMAZON_PERFORMANCE_DAILY' AS source_table,
    COALESCE(CAST(FORMAT_DATE('%Y%m%d', date) AS INT64), -1) AS date_key,
    COUNT(*) AS row_count
  FROM `onyga-482313.OI.FACT_AMAZON_PERFORMANCE_DAILY`
  GROUP BY date_key
)
SELECT 
  source_table,
  date_key,
  row_count,
  CASE 
    WHEN date_key = -1 THEN 'Missing Date'
    WHEN date_key NOT IN (SELECT date_key FROM `onyga-482313.OI.DIM_TIME`) THEN 'Not in DIM_TIME'
    ELSE 'Valid'
  END AS status
FROM fact_sources
WHERE date_key = -1 OR date_key NOT IN (SELECT date_key FROM `onyga-482313.OI.DIM_TIME`)
ORDER BY source_table, date_key;

-- 6. Check for NULL dates in source fact tables
SELECT 
  'FACT_INVENTORY_SNAPSHOT NULL dates' AS check_type,
  COUNT(*) AS null_date_count
FROM `onyga-482313.OI.FACT_INVENTORY_SNAPSHOT`
WHERE Date IS NULL

UNION ALL

SELECT 
  'FACT_FINANCIAL_TRANSACTIONS NULL dates' AS check_type,
  COUNT(*) AS null_date_count
FROM `onyga-482313.OI.FACT_FINANCIAL_TRANSACTIONS`
WHERE transaction_date IS NULL

UNION ALL

SELECT 
  'FACT_PURCHASE_ORDER NULL dates' AS check_type,
  COUNT(*) AS null_date_count
FROM `onyga-482313.OI.FACT_PURCHASE_ORDER`
WHERE snapshot_date IS NULL

UNION ALL

SELECT 
  'FACT_AMAZON_PERFORMANCE_DAILY NULL dates' AS check_type,
  COUNT(*) AS null_date_count
FROM `onyga-482313.OI.FACT_AMAZON_PERFORMANCE_DAILY`
WHERE date IS NULL;

-- 7. Summary: Overall date_key health check
SELECT 
  'Summary' AS check_type,
  COUNT(*) AS total_rows,
  COUNT(DISTINCT date_key) AS distinct_date_keys,
  COUNT(CASE WHEN date_key = -1 THEN 1 END) AS missing_date_keys,
  COUNT(CASE WHEN date_key != -1 AND date_key NOT IN (SELECT date_key FROM `onyga-482313.OI.DIM_TIME`) THEN 1 END) AS unmatched_date_keys,
  COUNT(CASE WHEN date_key != -1 AND date_key IN (SELECT date_key FROM `onyga-482313.OI.DIM_TIME`) THEN 1 END) AS valid_date_keys
FROM `onyga-482313.OI.FACT_FACTLESS_BRIDGE`;
