-- =============================================
-- OI Database Project - SP_MERGE_SQP_WEEKLY Stored Procedure
-- =============================================
--
-- Purpose: Merge weekly search query performance data from OpenBridge into STG_SQP_WEEKLY
-- Only updates when data changes, inserts new records
-- Source: openbridge-482712.DB.sp_ba_search_query_by_week_v1
-- Project: onyga-482313
-- Dataset: OI
--
-- =============================================

CREATE OR REPLACE PROCEDURE `onyga-482313.OI.SP_MERGE_SQP_WEEKLY`()
OPTIONS (
  description = "Merge weekly search query performance data from OpenBridge sp_ba_search_query_by_week_v1 into STG_SQP_WEEKLY. Only updates if data changed, inserts new records."
)
BEGIN
  -- Declare variables for logging
  DECLARE matched_count INT64 DEFAULT 0;
  DECLARE start_time TIMESTAMP;
  DECLARE end_time TIMESTAMP;

  SET start_time = CURRENT_TIMESTAMP();

  -- MERGE data from OpenBridge source into staging table
  MERGE `onyga-482313.OI.STG_SQP_WEEKLY` AS stg
  USING (
    SELECT
      -- Query text and ASIN
      search_query_data_search_query AS query_text,
      asin AS ASIN,
      
      -- Extract Year and Week from end_date (week end date)
      EXTRACT(YEAR FROM end_date) AS Year,
      EXTRACT(WEEK FROM end_date) AS Week,
      ob_date,
      
      -- Week boundaries (use start_date and end_date from source)
      start_date AS week_start_date,
      end_date AS week_end_date,
      
      -- Performance Metrics
      impression_data_asin_impression_count AS impressions,
      click_data_asin_click_count AS clicks,
      -- Calculate click_through_rate: (clicks / impressions) * 100
      CASE 
        WHEN impression_data_asin_impression_count > 0 
        THEN (click_data_asin_click_count / impression_data_asin_impression_count) * 100.0
        ELSE 0.0
      END AS click_through_rate,
      cart_add_data_asin_cart_add_count AS cart_adds,
      purchase_data_asin_purchase_count AS conversions,
      -- Calculate conversion_rate: (conversions / clicks) * 100
      CASE 
        WHEN click_data_asin_click_count > 0 
        THEN (purchase_data_asin_purchase_count / click_data_asin_click_count) * 100.0
        ELSE 0.0
      END AS conversion_rate,
      -- Sales amount: purchase_count * median_price_amount
      CASE 
        WHEN purchase_data_asin_purchase_count > 0 
          AND purchase_data_asin_median_purchase_price_amount IS NOT NULL
        THEN purchase_data_asin_purchase_count * purchase_data_asin_median_purchase_price_amount
        ELSE NULL
      END AS sales_amount,
      purchase_data_asin_median_purchase_price_currency_code AS sales_currency_code,
      
      -- Total Count Metrics (across all ASINs for the query)
      impression_data_total_query_impression_count AS TOTAL_IMPRESSIONS,
      click_data_total_click_count AS TOTAL_CLICKS,
      cart_add_data_total_cart_add_count AS TOTAL_CART_ADDS,
      purchase_data_total_purchase_count AS TOTAL_PURCHASES,
      
      -- Additional metrics (not available in source, set to NULL)
      CAST(NULL AS INT64) AS query_rank,
      CAST(NULL AS FLOAT64) AS avg_position,
      
      -- OpenBridge Metadata
      ob_file_name,
      ob_marketplace_id,
      ob_seller_id,
      ob_transaction_id,
      ob_modified_date,
      ob_processed_at
      
    FROM `openbridge-482712.DB.sp_ba_search_query_by_week_v1`
    WHERE asin IS NOT NULL
      AND search_query_data_search_query IS NOT NULL
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
    -- Compare all key metrics to detect changes
    COALESCE(stg.impressions, 0) != COALESCE(source.impressions, 0)
    OR COALESCE(stg.clicks, 0) != COALESCE(source.clicks, 0)
    OR COALESCE(stg.click_through_rate, 0) != COALESCE(source.click_through_rate, 0)
    OR COALESCE(stg.cart_adds, 0) != COALESCE(source.cart_adds, 0)
    OR COALESCE(stg.conversions, 0) != COALESCE(source.conversions, 0)
    OR COALESCE(stg.conversion_rate, 0) != COALESCE(source.conversion_rate, 0)
    OR COALESCE(stg.sales_amount, 0) != COALESCE(source.sales_amount, 0)
    OR COALESCE(stg.TOTAL_IMPRESSIONS, 0) != COALESCE(source.TOTAL_IMPRESSIONS, 0)
    OR COALESCE(stg.TOTAL_CLICKS, 0) != COALESCE(source.TOTAL_CLICKS, 0)
    OR COALESCE(stg.TOTAL_CART_ADDS, 0) != COALESCE(source.TOTAL_CART_ADDS, 0)
    OR COALESCE(stg.TOTAL_PURCHASES, 0) != COALESCE(source.TOTAL_PURCHASES, 0)
    OR COALESCE(stg.query_rank, 0) != COALESCE(source.query_rank, 0)
    OR COALESCE(stg.avg_position, 0) != COALESCE(source.avg_position, 0)
    OR COALESCE(stg.sales_currency_code, '') != COALESCE(source.sales_currency_code, '')
    OR COALESCE(stg.ob_file_name, '') != COALESCE(source.ob_file_name, '')
    OR COALESCE(stg.ob_marketplace_id, '') != COALESCE(source.ob_marketplace_id, '')
    OR COALESCE(stg.ob_seller_id, '') != COALESCE(source.ob_seller_id, '')
    OR COALESCE(stg.ob_transaction_id, '') != COALESCE(source.ob_transaction_id, '')
    OR stg.ob_modified_date != source.ob_modified_date
    OR COALESCE(stg.ob_processed_at, '') != COALESCE(source.ob_processed_at, '')
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
      
      -- OpenBridge Metadata
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
      
      -- OpenBridge Metadata
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
      
      -- OpenBridge Metadata
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
