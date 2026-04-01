-- =============================================
-- OI Database Project - SP_POPULATE_FACTLESS_BRIDGE
-- =============================================
--
-- Purpose: Populate the factless fact bridge table via UNION of all fact table keys
--          Each fact contributes its own (date_key, asin) rows
--          Uses -1 for missing date_key, 'UNKNOWN' for missing asin
-- Project: onyga-482313
-- Dataset: OI
--
-- =============================================

CREATE OR REPLACE PROCEDURE `onyga-482313.OI.SP_POPULATE_FACTLESS_BRIDGE`()
BEGIN
  -- Truncate the table to remove all existing data
  TRUNCATE TABLE `onyga-482313.OI.FACT_FACTLESS_BRIDGE`;
  
  -- Insert UNION of all fact table keys with DISTINCT applied to final result
  INSERT INTO `onyga-482313.OI.FACT_FACTLESS_BRIDGE` (
    date_key,
    asin,
    factless_key
  )
  SELECT DISTINCT
    date_key,
    asin,
    factless_key
  FROM (
    -- FACT_INVENTORY_SNAPSHOT keys
    SELECT
      COALESCE(CAST(FORMAT_DATE('%Y%m%d', Date) AS INT64), -1) AS date_key,
      COALESCE(ASIN, 'UNKNOWN') AS asin,
      CONCAT(CAST(COALESCE(CAST(FORMAT_DATE('%Y%m%d', Date) AS INT64), -1) AS STRING), '-', COALESCE(ASIN, 'UNKNOWN')) AS factless_key
    FROM `onyga-482313.OI.FACT_INVENTORY_SNAPSHOT`
    
    UNION ALL
    
    -- FACT_FINANCIAL_TRANSACTIONS keys
    SELECT
      COALESCE(CAST(FORMAT_DATE('%Y%m%d', transaction_date) AS INT64), -1) AS date_key,
      COALESCE(JSON_EXTRACT_SCALAR(source_metadata, '$.asin'), 'UNKNOWN') AS asin,
      CONCAT(CAST(COALESCE(CAST(FORMAT_DATE('%Y%m%d', transaction_date) AS INT64), -1) AS STRING), '-', COALESCE(JSON_EXTRACT_SCALAR(source_metadata, '$.asin'), 'UNKNOWN')) AS factless_key
    FROM `onyga-482313.OI.FACT_FINANCIAL_TRANSACTIONS`
    
    UNION ALL
    
    -- FACT_PURCHASE_ORDER keys
    SELECT
      COALESCE(CAST(FORMAT_DATE('%Y%m%d', snapshot_date) AS INT64), -1) AS date_key,
      COALESCE(product_asin, 'UNKNOWN') AS asin,
      CONCAT(CAST(COALESCE(CAST(FORMAT_DATE('%Y%m%d', snapshot_date) AS INT64), -1) AS STRING), '-', COALESCE(product_asin, 'UNKNOWN')) AS factless_key
    FROM `onyga-482313.OI.FACT_PURCHASE_ORDER`
    
    UNION ALL
    
    -- FACT_AMAZON_PERFORMANCE_DAILY keys
    SELECT
      COALESCE(CAST(FORMAT_DATE('%Y%m%d', DATE) AS INT64), -1) AS date_key,
      COALESCE(PURCHASED_ASIN, 'UNKNOWN') AS asin,
      COALESCE(factless_key, CONCAT(CAST(CAST(FORMAT_DATE('%Y%m%d', DATE) AS INT64) AS STRING), '-', COALESCE(PURCHASED_ASIN, 'UNKNOWN'))) AS factless_key
    FROM `onyga-482313.OI.FACT_AMAZON_PERFORMANCE_DAILY`
    WHERE factless_key IS NOT NULL
    
    UNION ALL
    
    -- FACT_AMAZON_SEARCH_PERFORMANCE_WEEKLY keys
    SELECT
      COALESCE(CAST(FORMAT_DATE('%Y%m%d', Reporting_Date) AS INT64), -1) AS date_key,
      COALESCE(ASIN, 'UNKNOWN') AS asin,
      COALESCE(factless_key, CONCAT(CAST(COALESCE(CAST(FORMAT_DATE('%Y%m%d', Reporting_Date) AS INT64), -1) AS STRING), '-', COALESCE(ASIN, 'UNKNOWN'))) AS factless_key
    FROM `onyga-482313.OI.FACT_AMAZON_SEARCH_PERFORMANCE_WEEKLY`
    WHERE factless_key IS NOT NULL

    UNION ALL

    -- FACT_EXPERIMENT_DAILY keys
    SELECT
      COALESCE(CAST(FORMAT_DATE('%Y%m%d', snapshot_date) AS INT64), -1) AS date_key,
      COALESCE(asin, 'UNKNOWN') AS asin,
      COALESCE(factless_key, CONCAT(CAST(CAST(FORMAT_DATE('%Y%m%d', snapshot_date) AS INT64) AS STRING), '-', COALESCE(asin, 'UNKNOWN'))) AS factless_key
    FROM `onyga-482313.OI.FACT_EXPERIMENT_DAILY`
    WHERE factless_key IS NOT NULL
  );
  
END;

-- =============================================
-- USAGE EXAMPLES
-- =============================================
--
-- Populate the table (loads all data from all fact tables):
-- CALL `onyga-482313.OI.SP_POPULATE_FACTLESS_BRIDGE`();
--
-- =============================================
-- EXTENDING FOR NEW FACTS
-- =============================================
--
-- To add a new fact table, add another UNION ALL clause:
--
-- UNION ALL
--
-- -- FACT_NEW_FACT keys
-- SELECT
--   COALESCE(CAST(FORMAT_DATE('%Y%m%d', fact_date) AS INT64), -1) AS date_key,
--   COALESCE(product_asin, 'UNKNOWN') AS asin
-- FROM `onyga-482313.OI.FACT_NEW_FACT`
--
-- =============================================
