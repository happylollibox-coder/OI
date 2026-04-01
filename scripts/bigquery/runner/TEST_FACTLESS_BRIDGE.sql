-- =============================================
-- Test Query for FACT_FACTLESS_BRIDGE
-- =============================================
-- Run this to verify fact tables exist and have data
-- =============================================

-- Test 1: Check if FACT_INVENTORY_SNAPSHOT exists and has data
SELECT 
  'FACT_INVENTORY_SNAPSHOT' AS table_name,
  COUNT(*) AS row_count,
  COUNT(DISTINCT Date) AS distinct_dates,
  COUNT(DISTINCT ASIN) AS distinct_asins
FROM `onyga-482313.OI.FACT_INVENTORY_SNAPSHOT`;

-- Test 2: Check if FACT_PURCHASE_ORDER exists and has data
SELECT 
  'FACT_PURCHASE_ORDER' AS table_name,
  COUNT(*) AS row_count,
  COUNT(DISTINCT snapshot_date) AS distinct_dates,
  COUNT(DISTINCT product_asin) AS distinct_asins
FROM `onyga-482313.OI.FACT_PURCHASE_ORDER`;

-- Test 3: Check if FACT_FINANCIAL_TRANSACTIONS exists and has ASIN data
SELECT 
  'FACT_FINANCIAL_TRANSACTIONS' AS table_name,
  COUNT(*) AS total_rows,
  COUNT(DISTINCT transaction_date) AS distinct_dates,
  COUNT(DISTINCT JSON_EXTRACT_SCALAR(source_metadata, '$.asin')) AS distinct_asins,
  COUNT(CASE WHEN JSON_EXTRACT_SCALAR(source_metadata, '$.asin') IS NOT NULL THEN 1 END) AS rows_with_asin
FROM `onyga-482313.OI.FACT_FINANCIAL_TRANSACTIONS`;

-- Test 4: Sample the UNION query (without INSERT)
SELECT DISTINCT
  date_key,
  asin
FROM (
  SELECT
    COALESCE(CAST(FORMAT_DATE('%Y%m%d', Date) AS INT64), -1) AS date_key,
    COALESCE(ASIN, 'UNKNOWN') AS asin
  FROM `onyga-482313.OI.FACT_INVENTORY_SNAPSHOT`
  WHERE Date IS NOT NULL AND ASIN IS NOT NULL
  LIMIT 10
  
  UNION ALL
  
  SELECT
    COALESCE(CAST(FORMAT_DATE('%Y%m%d', transaction_date) AS INT64), -1) AS date_key,
    COALESCE(JSON_EXTRACT_SCALAR(source_metadata, '$.asin'), 'UNKNOWN') AS asin
  FROM `onyga-482313.OI.FACT_FINANCIAL_TRANSACTIONS`
  WHERE transaction_date IS NOT NULL
    AND JSON_EXTRACT_SCALAR(source_metadata, '$.asin') IS NOT NULL
  LIMIT 10
  
  UNION ALL
  
  SELECT
    COALESCE(CAST(FORMAT_DATE('%Y%m%d', snapshot_date) AS INT64), -1) AS date_key,
    COALESCE(product_asin, 'UNKNOWN') AS asin
  FROM `onyga-482313.OI.FACT_PURCHASE_ORDER`
  WHERE snapshot_date IS NOT NULL AND product_asin IS NOT NULL
  LIMIT 10
)
WHERE date_key != -1 AND asin != 'UNKNOWN'
LIMIT 20;
