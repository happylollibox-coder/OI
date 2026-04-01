-- =============================================
-- OI Database Project - SP_LOAD_STG_AMAZON_PERFORMANCE Stored Procedure
-- =============================================
--
-- Purpose: Load STG_AMAZON_PERFORMANCE with sales and traffic data
-- Pattern: TRUNCATE + INSERT (full refresh)
-- Project: onyga-482313
-- Dataset: OI
--
-- Logic:
-- 1. Aggregate data from V_SRC_sales_and_traffic_business_sku_report_daily
--    at DATE + PURCHASED_ASIN (child_asin) level
-- 2. TRUNCATE STG_AMAZON_PERFORMANCE
-- 3. INSERT aggregated records
--
-- =============================================

CREATE OR REPLACE PROCEDURE `onyga-482313.OI.SP_LOAD_STG_AMAZON_PERFORMANCE`()
OPTIONS (
  description = "Load STG_AMAZON_PERFORMANCE with aggregated sales and traffic data from V_SRC_sales_and_traffic_business_sku_report_daily at DATE + PURCHASED_ASIN level. TRUNCATEs table and inserts aggregated records."
)
BEGIN
  -- Declare variables for logging
  DECLARE record_count INT64 DEFAULT 0;
  DECLARE start_time TIMESTAMP;
  DECLARE end_time TIMESTAMP;

  SET start_time = CURRENT_TIMESTAMP();

  -- Step 1: TRUNCATE the staging table
  TRUNCATE TABLE `onyga-482313.OI.STG_AMAZON_PERFORMANCE`;

  -- Step 2: Load aggregated data
  INSERT INTO `onyga-482313.OI.STG_AMAZON_PERFORMANCE` (
    DATE,
    PURCHASED_ASIN,
    PURCHASED_ORDERS,
    PURCHASED_UNITS,
    PURCHASED_AMOUNT_USD,
    ASIN_SESSIONS,
    ASIN_PAGE_VIEWS,
    IS_LOADED
  )
  SELECT 
    date AS DATE,
    child_asin AS PURCHASED_ASIN,
    SUM(SALES_ORDERS) AS PURCHASED_ORDERS,
    SUM(SALES_QUANTITY) AS PURCHASED_UNITS,
    SUM(SALES_AMOUNT) AS PURCHASED_AMOUNT_USD,
    SUM(asin_sessions) AS ASIN_SESSIONS,
    SUM(page_views) AS ASIN_PAGE_VIEWS,
    -- IS_LOADED: false if ASIN_PAGE_VIEWS (aggregated page_views) is NULL or 0, else true
    CASE 
      WHEN COALESCE(SUM(page_views), 0) = 0
      THEN FALSE
      ELSE TRUE
    END AS IS_LOADED
  FROM `onyga-482313.OI.V_SRC_sales_and_traffic_business_sku_report_daily`
  GROUP BY
    DATE,
    PURCHASED_ASIN;

  SET record_count = @@row_count;
  SET end_time = CURRENT_TIMESTAMP();

  -- Log the operation results
  SELECT FORMAT(
    'SP_LOAD_STG_AMAZON_PERFORMANCE completed:\n' ||
    '  Records inserted: %d\n' ||
    '  Duration: %d seconds\n' ||
    '  Completed at: %s',
    record_count,
    TIMESTAMP_DIFF(end_time, start_time, SECOND),
    CAST(end_time AS STRING)
  ) as operation_summary;
END;
