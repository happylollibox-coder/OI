-- =============================================
-- OI Database Project - SP_MERGE_SQP_WEEKLY Stored Procedure
-- =============================================
--
-- Purpose: Merge weekly search query performance data into STG_SQP_WEEKLY
-- Only updates when data changes, inserts new records
-- Source: SRC_ACC_SQP_WEEKLY (Daton-accumulated, replaces legacy OpenBridge)
-- Project: onyga-482313
-- Dataset: OI
--
-- =============================================

CREATE OR REPLACE PROCEDURE `onyga-482313.OI.SP_MERGE_SQP_WEEKLY`()
OPTIONS (
  description = "Merge weekly search query performance data from SRC_ACC_SQP_WEEKLY into STG_SQP_WEEKLY. Only updates if data changed, inserts new records."
)
BEGIN
  -- Declare variables for logging
  DECLARE matched_count INT64 DEFAULT 0;
  DECLARE start_time TIMESTAMP;
  DECLARE end_time TIMESTAMP;

  SET start_time = CURRENT_TIMESTAMP();

  -- MERGE data from Daton accumulator into staging table
  MERGE `onyga-482313.OI.STG_SQP_WEEKLY` AS stg
  USING (
    SELECT
      -- Query text and ASIN
      Search_Query AS query_text,
      ASIN,
      
      -- Extract Year and Week from Reporting_Date (week end date)
      EXTRACT(YEAR FROM Reporting_Date) AS Year,
      EXTRACT(WEEK FROM Reporting_Date) AS Week,
      Reporting_Date AS ob_date,
      
      -- Week boundaries
      DATE_TRUNC(Reporting_Date, WEEK(MONDAY)) AS week_start_date,
      DATE_ADD(DATE_TRUNC(Reporting_Date, WEEK(MONDAY)), INTERVAL 6 DAY) AS week_end_date,
      
      -- Performance Metrics
      Impressions_ASIN_Count AS impressions,
      Clicks_ASIN_Count AS clicks,
      -- Calculate click_through_rate: (clicks / impressions) * 100
      CASE 
        WHEN Impressions_ASIN_Count > 0 
        THEN (CAST(Clicks_ASIN_Count AS FLOAT64) / Impressions_ASIN_Count) * 100.0
        ELSE 0.0
      END AS click_through_rate,
      Cart_Adds_ASIN_Count AS cart_adds,
      Purchases_ASIN_Count AS conversions,
      -- Calculate conversion_rate: (conversions / clicks) * 100
      CASE 
        WHEN Clicks_ASIN_Count > 0 
        THEN (CAST(Purchases_ASIN_Count AS FLOAT64) / Clicks_ASIN_Count) * 100.0
        ELSE 0.0
      END AS conversion_rate,
      -- Sales amount: purchase_count * median_price
      CASE 
        WHEN Purchases_ASIN_Count > 0 
          AND Purchases_ASIN_Price_Median IS NOT NULL
        THEN Purchases_ASIN_Count * Purchases_ASIN_Price_Median
        ELSE NULL
      END AS sales_amount,
      CAST(NULL AS STRING) AS sales_currency_code,
      
      -- Total Count Metrics (across all ASINs for the query)
      Impressions_Total_Count AS TOTAL_IMPRESSIONS,
      Clicks_Total_Count AS TOTAL_CLICKS,
      Cart_Adds_Total_Count AS TOTAL_CART_ADDS,
      Purchases_Total_Count AS TOTAL_PURCHASES,
      
      -- Additional metrics
      CAST(NULL AS INT64) AS query_rank,
      CAST(NULL AS FLOAT64) AS avg_position,
      
      -- Daton Metadata (mapped to ob_ columns for backward compatibility)
      source_file AS ob_file_name,
      CAST(NULL AS STRING) AS ob_marketplace_id,
      CAST(NULL AS STRING) AS ob_seller_id,
      CAST(NULL AS STRING) AS ob_transaction_id,
      Reporting_Date AS ob_modified_date,
      CAST(processed_at AS STRING) AS ob_processed_at
      
    FROM `onyga-482313.OI.SRC_ACC_SQP_WEEKLY`
    WHERE ASIN IS NOT NULL
      AND Search_Query IS NOT NULL
  ) AS source
  ON (
    -- Match on primary key dimensions: query_text, ASIN, Year, Week
    COALESCE(stg.query_text, '') = COALESCE(source.query_text, '')
    AND COALESCE(stg.ASIN, '') = COALESCE(source.ASIN, '')
    AND stg.Year = source.Year
    AND stg.Week = source.Week
  )
  WHEN MATCHED AND (
    -- Only update if any metric value has changed
    COALESCE(stg.impressions, 0) != COALESCE(source.impressions, 0)
    OR COALESCE(stg.clicks, 0) != COALESCE(source.clicks, 0)
    OR COALESCE(stg.cart_adds, 0) != COALESCE(source.cart_adds, 0)
    OR COALESCE(stg.conversions, 0) != COALESCE(source.conversions, 0)
    OR COALESCE(stg.sales_amount, 0) != COALESCE(source.sales_amount, 0)
    OR COALESCE(stg.TOTAL_IMPRESSIONS, 0) != COALESCE(source.TOTAL_IMPRESSIONS, 0)
    OR COALESCE(stg.TOTAL_CLICKS, 0) != COALESCE(source.TOTAL_CLICKS, 0)
    OR COALESCE(stg.TOTAL_CART_ADDS, 0) != COALESCE(source.TOTAL_CART_ADDS, 0)
    OR COALESCE(stg.TOTAL_PURCHASES, 0) != COALESCE(source.TOTAL_PURCHASES, 0)
  ) THEN
    -- Update all fields with new values
    UPDATE SET
      ob_date = source.ob_date,
      week_start_date = source.week_start_date,
      week_end_date = source.week_end_date,
      
      -- Performance Metrics
      impressions = source.impressions,
      clicks = source.clicks,
      click_through_rate = source.click_through_rate,
      cart_adds = source.cart_adds,
      conversions = source.conversions,
      conversion_rate = source.conversion_rate,
      sales_amount = source.sales_amount,
      sales_currency_code = source.sales_currency_code,
      TOTAL_IMPRESSIONS = source.TOTAL_IMPRESSIONS,
      TOTAL_CLICKS = source.TOTAL_CLICKS,
      TOTAL_CART_ADDS = source.TOTAL_CART_ADDS,
      TOTAL_PURCHASES = source.TOTAL_PURCHASES,
      query_rank = source.query_rank,
      avg_position = source.avg_position,
      
      -- Metadata
      ob_file_name = source.ob_file_name,
      ob_marketplace_id = source.ob_marketplace_id,
      ob_seller_id = source.ob_seller_id,
      ob_transaction_id = source.ob_transaction_id,
      ob_modified_date = source.ob_modified_date,
      ob_processed_at = source.ob_processed_at
  WHEN NOT MATCHED THEN
    -- Insert new records
    INSERT (
      query_text,
      ASIN,
      Year,
      Week,
      ob_date,
      week_start_date,
      week_end_date,
      
      -- Performance Metrics
      impressions,
      clicks,
      click_through_rate,
      cart_adds,
      conversions,
      conversion_rate,
      sales_amount,
      sales_currency_code,
      TOTAL_IMPRESSIONS,
      TOTAL_CLICKS,
      TOTAL_CART_ADDS,
      TOTAL_PURCHASES,
      query_rank,
      avg_position,
      
      -- Metadata
      ob_file_name,
      ob_marketplace_id,
      ob_seller_id,
      ob_transaction_id,
      ob_modified_date,
      ob_processed_at
    )
    VALUES (
      source.query_text,
      source.ASIN,
      source.Year,
      source.Week,
      source.ob_date,
      source.week_start_date,
      source.week_end_date,
      
      -- Performance Metrics
      source.impressions,
      source.clicks,
      source.click_through_rate,
      source.cart_adds,
      source.conversions,
      source.conversion_rate,
      source.sales_amount,
      source.sales_currency_code,
      source.TOTAL_IMPRESSIONS,
      source.TOTAL_CLICKS,
      source.TOTAL_CART_ADDS,
      source.TOTAL_PURCHASES,
      source.query_rank,
      source.avg_position,
      
      -- Metadata
      source.ob_file_name,
      source.ob_marketplace_id,
      source.ob_seller_id,
      source.ob_transaction_id,
      source.ob_modified_date,
      source.ob_processed_at
    );

  SET matched_count = @@row_count;
  SET end_time = CURRENT_TIMESTAMP();

  -- Log the operation results
  SELECT FORMAT(
    'SP_MERGE_SQP_WEEKLY completed:\n' ||
    '  Total rows affected: %d\n' ||
    '  Duration: %d seconds\n' ||
    '  Completed at: %s',
    matched_count,
    TIMESTAMP_DIFF(end_time, start_time, SECOND),
    CAST(end_time AS STRING)
  ) as operation_summary;
END;
