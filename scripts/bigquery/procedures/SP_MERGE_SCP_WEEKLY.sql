-- =============================================
-- OI Database Project - SP_MERGE_SCP_WEEKLY Stored Procedure
-- =============================================
--
-- Purpose: Merge weekly ASIN performance data into STG_SCP_WEEKLY
-- Simple upsert pattern - updates existing records, inserts new ones
-- Source: SRC_ACC_SCP_WEEKLY (Daton-accumulated, replaces legacy OpenBridge)
-- Project: onyga-482313
-- Dataset: OI
--
-- =============================================

CREATE OR REPLACE PROCEDURE `onyga-482313.OI.SP_MERGE_SCP_WEEKLY`()
OPTIONS (
  description = "Merge weekly ASIN performance data from SRC_ACC_SCP_WEEKLY into STG_SCP_WEEKLY. Updates existing records, inserts new ones."
)
BEGIN
  -- Declare variables for logging
  DECLARE total_affected INT64 DEFAULT 0;
  DECLARE start_time TIMESTAMP;
  DECLARE end_time TIMESTAMP;

  SET start_time = CURRENT_TIMESTAMP();

  -- MERGE data from Daton accumulator into staging table
  -- Match on ASIN, Year, Week
  MERGE `onyga-482313.OI.STG_SCP_WEEKLY` AS stg
  USING (
    SELECT
      ASIN,
      EXTRACT(YEAR FROM Reporting_Date) AS Year,
      EXTRACT(WEEK FROM Reporting_Date) AS Week,
      Reporting_Date AS ob_date,
      DATE_TRUNC(Reporting_Date, WEEK(MONDAY)) AS week_start_date,
      DATE_ADD(DATE_TRUNC(Reporting_Date, WEEK(MONDAY)), INTERVAL 6 DAY) AS week_end_date,
      
      -- Performance Metrics (matching STG_SCP_WEEKLY naming convention)
      Impressions_Impressions AS impressions,
      Clicks_Clicks AS clicks,
      Clicks_Click_Rate_CTR AS click_through_rate,
      Cart_Adds_Cart_Adds AS cart_adds,
      Purchases_Purchases AS conversions,
      Purchases_Conversion_Rate AS conversion_rate,
      Purchases_Search_Traffic_Sales AS sales_amount,
      CAST(NULL AS STRING) AS sales_currency_code,
      
      -- Daton Metadata (mapped to ob_ columns for backward compatibility)
      source_file AS ob_file_name,
      CAST(NULL AS STRING) AS ob_marketplace_id,
      CAST(NULL AS STRING) AS ob_seller_id,
      CAST(NULL AS STRING) AS ob_transaction_id,
      Reporting_Date AS ob_modified_date,
      CAST(processed_at AS STRING) AS ob_processed_at
    FROM `onyga-482313.OI.SRC_ACC_SCP_WEEKLY`
    WHERE ASIN IS NOT NULL
  ) AS source
  ON (
    stg.ASIN = source.ASIN
    AND stg.Year = source.Year
    AND stg.Week = source.Week
  )
  WHEN MATCHED THEN
    -- Update all fields with latest data (no change detection)
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
      
      -- Metadata
      ob_file_name,
      ob_marketplace_id,
      ob_seller_id,
      ob_transaction_id,
      ob_modified_date,
      ob_processed_at
    )
    VALUES (
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
      
      -- Metadata
      source.ob_file_name,
      source.ob_marketplace_id,
      source.ob_seller_id,
      source.ob_transaction_id,
      source.ob_modified_date,
      source.ob_processed_at
    );

  SET total_affected = @@row_count;
  SET end_time = CURRENT_TIMESTAMP();

  -- Log the operation results
  SELECT FORMAT(
    'SP_MERGE_SCP_WEEKLY completed:\n' ||
    '  Total rows affected: %d\n' ||
    '  Duration: %d seconds\n' ||
    '  Completed at: %s',
    total_affected,
    TIMESTAMP_DIFF(end_time, start_time, SECOND),
    CAST(end_time AS STRING)
  ) as operation_summary;
END;
