-- =============================================
-- OI Database Project - SP_LOAD_STG_AMAZON_SEARCH_PERFORMANCE_WEEKLY
-- =============================================
--
-- Purpose: Load STG_AMAZON_SEARCH_PERFORMANCE_WEEKLY with data from SQP and SCP sources
-- Method: TRUNCATE + INSERT (full refresh)
-- Project: onyga-482313
-- Dataset: OI
--
-- Logic:
-- 1. TRUNCATE STG_AMAZON_SEARCH_PERFORMANCE_WEEKLY
-- 2. INSERT from SRC_ACC_SQP_WEEKLY (SQP data)
-- 3. INSERT delta calculation (SCP - SQP) for Impressions, Clicks, Cart_Adds
--    - Only includes rows where delta is not negative (>= 0)
--    - Other measures are NULL, Search_Query and Search_Query_Score are NULL
--    - ORDERS comes from SCP.Purchases_Purchases
--
-- =============================================

CREATE OR REPLACE PROCEDURE `onyga-482313.OI.SP_LOAD_STG_AMAZON_SEARCH_PERFORMANCE_WEEKLY`()
OPTIONS (
  description = "Load STG_AMAZON_SEARCH_PERFORMANCE_WEEKLY with data from SQP and delta calculation from SCP minus SQP. TRUNCATEs table and inserts records."
)
BEGIN
  -- Declare variables for logging
  DECLARE sqp_record_count INT64 DEFAULT 0;
  DECLARE delta_record_count INT64 DEFAULT 0;
  DECLARE start_time TIMESTAMP;
  DECLARE end_time TIMESTAMP;

  SET start_time = CURRENT_TIMESTAMP();

  -- Step 1: TRUNCATE the staging table
  TRUNCATE TABLE `onyga-482313.OI.STG_AMAZON_SEARCH_PERFORMANCE_WEEKLY`;

  -- Step 2: INSERT from SRC_ACC_SQP_WEEKLY (SQP data)
  INSERT INTO `onyga-482313.OI.STG_AMAZON_SEARCH_PERFORMANCE_WEEKLY` (
    Reporting_Date,
    ASIN,
    Search_Query,
    Search_Query_Score,
    Impressions,
    Clicks,
    Cart_Adds,
    ORDERS,
    AMAZON_IMPRESSIONS,
    AMAZON_Clicks,
    AMAZON_Cart_Adds,
    AMAZON_ORDERS,
    DATA_SOURCE
  )
  SELECT
    Reporting_Date,
    ASIN,
    Search_Query,
    Search_Query_Score,
    Impressions_ASIN_Count AS Impressions,
    Clicks_ASIN_Count AS Clicks,
    Cart_Adds_ASIN_Count AS Cart_Adds,
    Purchases_ASIN_Count AS ORDERS,
    Search_Query_Volume AS AMAZON_IMPRESSIONS,
    Clicks_Total_Count AS AMAZON_Clicks,
    Cart_Adds_Total_Count AS AMAZON_Cart_Adds,
    Purchases_Total_Count AS AMAZON_ORDERS,
    'SQP' AS DATA_SOURCE
  FROM `onyga-482313.OI.SRC_ACC_SQP_WEEKLY`;

  SET sqp_record_count = @@row_count;

  -- Step 3: INSERT delta calculation (SCP - SQP)
  -- Aggregate SQP first by ASIN+Date, then calculate delta to avoid duplicate rows
  INSERT INTO `onyga-482313.OI.STG_AMAZON_SEARCH_PERFORMANCE_WEEKLY` (
    Reporting_Date,
    ASIN,
    Search_Query,
    Search_Query_Score,
    Impressions,
    Clicks,
    Cart_Adds,
    ORDERS,
    AMAZON_IMPRESSIONS,
    AMAZON_Clicks,
    AMAZON_Cart_Adds,
    AMAZON_ORDERS,
    DATA_SOURCE
  )
  WITH sqp_aggregated AS (
    -- Aggregate SQP by Reporting_Date and ASIN to get totals per ASIN+Date
    SELECT
      Reporting_Date,
      ASIN,
      SUM(Impressions_ASIN_Count) AS total_impressions,
      SUM(Clicks_ASIN_Count) AS total_clicks,
      SUM(Cart_Adds_ASIN_Count) AS total_cart_adds,
      SUM(Purchases_ASIN_Count) AS total_orders
    FROM `onyga-482313.OI.SRC_ACC_SQP_WEEKLY`
    GROUP BY Reporting_Date, ASIN
  )
  SELECT
    scp.Reporting_Date,
    scp.ASIN,
    CAST(NULL AS STRING) AS Search_Query,  -- NULL for delta rows
    CAST(NULL AS FLOAT64) AS Search_Query_Score,  -- NULL for delta rows
    -- Delta calculation: SCP - SQP aggregated (only if >= 0)
    GREATEST(
      COALESCE(scp.Impressions_Impressions, 0) - COALESCE(sqp.total_impressions, 0),
      0
    ) AS Impressions,
    GREATEST(
      COALESCE(scp.Clicks_Clicks, 0) - COALESCE(sqp.total_clicks, 0),
      0
    ) AS Clicks,
    GREATEST(
      COALESCE(scp.Cart_Adds_Cart_Adds, 0) - COALESCE(sqp.total_cart_adds, 0),
      0
    ) AS Cart_Adds,
    -- ORDERS delta calculation: SCP - SQP (only if >= 0)
    GREATEST(
      COALESCE(scp.Purchases_Purchases, 0) - COALESCE(sqp.total_orders, 0),
      0
    ) AS ORDERS,
    -- AMAZON_* fields are NULL for delta rows
    NULL AS AMAZON_IMPRESSIONS,
    NULL AS AMAZON_Clicks,
    NULL AS AMAZON_Cart_Adds,
    NULL AS AMAZON_ORDERS,
    'Delta SCP - SQP' AS DATA_SOURCE
  FROM `onyga-482313.OI.SRC_ACC_SCP_WEEKLY` scp
  LEFT JOIN sqp_aggregated sqp
    ON scp.Reporting_Date = sqp.Reporting_Date
    AND scp.ASIN = sqp.ASIN
  WHERE
    -- Only include rows where at least one delta is positive (not all zeros)
    (
      COALESCE(scp.Impressions_Impressions, 0) - COALESCE(sqp.total_impressions, 0) > 0
      OR COALESCE(scp.Clicks_Clicks, 0) - COALESCE(sqp.total_clicks, 0) > 0
      OR COALESCE(scp.Cart_Adds_Cart_Adds, 0) - COALESCE(sqp.total_cart_adds, 0) > 0
      OR COALESCE(scp.Purchases_Purchases, 0) - COALESCE(sqp.total_orders, 0) > 0
    );

  SET delta_record_count = @@row_count;
  SET end_time = CURRENT_TIMESTAMP();

  -- Log the operation results
  SELECT FORMAT(
    'SP_LOAD_STG_AMAZON_SEARCH_PERFORMANCE_WEEKLY completed:\n' ||
    '  SQP records inserted: %d\n' ||
    '  Delta (SCP - SQP) records inserted: %d\n' ||
    '  Total records: %d\n' ||
    '  Duration: %d seconds\n' ||
    '  Completed at: %s',
    sqp_record_count,
    delta_record_count,
    sqp_record_count + delta_record_count,
    TIMESTAMP_DIFF(end_time, start_time, SECOND),
    CAST(end_time AS STRING)
  ) as operation_summary;
END;
