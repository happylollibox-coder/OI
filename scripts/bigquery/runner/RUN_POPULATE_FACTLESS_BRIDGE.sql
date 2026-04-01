-- =============================================
-- Run SP_POPULATE_FACTLESS_BRIDGE
-- =============================================
-- Execute this in BigQuery Console to repopulate the bridge table
-- =============================================

CALL `onyga-482313.OI.SP_POPULATE_FACTLESS_BRIDGE`();

-- =============================================
-- Verification Query (run after the procedure)
-- =============================================

-- Check total rows and date_key distribution
SELECT 
  COUNT(*) AS total_rows,
  COUNT(DISTINCT date_key) AS distinct_date_keys,
  COUNT(CASE WHEN date_key = -1 THEN 1 END) AS missing_date_keys,
  COUNT(CASE WHEN date_key != -1 THEN 1 END) AS valid_date_keys,
  MIN(CASE WHEN date_key != -1 THEN date_key END) AS min_date_key,
  MAX(CASE WHEN date_key != -1 THEN date_key END) AS max_date_key
FROM `onyga-482313.OI.FACT_FACTLESS_BRIDGE`;

-- Check if all fact tables are represented
-- This should show rows from all 4 fact tables
SELECT 
  CASE 
    WHEN asin = 'UNKNOWN' AND date_key IN (
      SELECT DISTINCT COALESCE(CAST(FORMAT_DATE('%Y%m%d', transaction_date) AS INT64), -1)
      FROM `onyga-482313.OI.FACT_FINANCIAL_TRANSACTIONS`
    ) THEN 'FACT_FINANCIAL_TRANSACTIONS'
    WHEN date_key IN (
      SELECT DISTINCT COALESCE(CAST(FORMAT_DATE('%Y%m%d', Date) AS INT64), -1)
      FROM `onyga-482313.OI.FACT_INVENTORY_SNAPSHOT`
    ) THEN 'FACT_INVENTORY_SNAPSHOT'
    WHEN date_key IN (
      SELECT DISTINCT COALESCE(CAST(FORMAT_DATE('%Y%m%d', snapshot_date) AS INT64), -1)
      FROM `onyga-482313.OI.FACT_PURCHASE_ORDER`
    ) THEN 'FACT_PURCHASE_ORDER'
    WHEN date_key IN (
      SELECT DISTINCT COALESCE(CAST(FORMAT_DATE('%Y%m%d', date) AS INT64), -1)
      FROM `onyga-482313.OI.FACT_AMAZON_PERFORMANCE_DAILY`
    ) THEN 'FACT_AMAZON_PERFORMANCE_DAILY'
    ELSE 'Unknown'
  END AS likely_source,
  COUNT(*) AS row_count
FROM `onyga-482313.OI.FACT_FACTLESS_BRIDGE`
GROUP BY likely_source
ORDER BY row_count DESC;
