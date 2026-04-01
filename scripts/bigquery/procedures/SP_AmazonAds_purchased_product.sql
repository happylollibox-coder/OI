-- =============================================
-- OI Database Project - SP_AmazonAds_purchased_product Stored Procedure
-- =============================================
--
-- Purpose: Load STG_AmazonAds_purchased_product with purchased product data
-- Pattern: TRUNCATE + INSERT (full refresh)
-- Source: SRC_ACC_AmazonAds_purchased_product (accumulated data)
-- Project: onyga-482313
-- Dataset: OI
--
-- =============================================

CREATE OR REPLACE PROCEDURE `onyga-482313.OI.SP_AmazonAds_purchased_product`()
OPTIONS (
  description = "Load STG_AmazonAds_purchased_product from SRC_ACC_AmazonAds_purchased_product using TRUNCATE + INSERT."
)
BEGIN
  -- Declare variables for logging
  DECLARE record_count INT64 DEFAULT 0;
  DECLARE start_time TIMESTAMP;
  DECLARE end_time TIMESTAMP;

  SET start_time = CURRENT_TIMESTAMP();

  -- Step 1: TRUNCATE the staging table
  TRUNCATE TABLE `onyga-482313.OI.STG_AmazonAds_purchased_product`;

  -- Step 2: Load data from SRC_ACC (accumulated source)
  INSERT INTO `onyga-482313.OI.STG_AmazonAds_purchased_product` (
    DATE,
    PURCHASED_ASIN,
    advertised_asin,
    campaign_id,
    ad_group_id,
    keyword_id,
    PURCHASED_ORDERS,
    PURCHASED_UNITS,
    PURCHASED_AMOUNT_USD,
    PURCHASED_ORDERS_1d,
    PURCHASED_ORDERS_7d,
    PURCHASED_ORDERS_14d,
    PURCHASED_ORDERS_30d,
    PURCHASED_UNITS_1d,
    PURCHASED_UNITS_7d,
    PURCHASED_UNITS_14d,
    PURCHASED_UNITS_30d,
    PURCHASED_AMOUNT_USD_1d,
    PURCHASED_AMOUNT_USD_7d,
    PURCHASED_AMOUNT_USD_14d,
    PURCHASED_AMOUNT_USD_30d,
    data_source
  )
  SELECT
    DATE,
    PURCHASED_ASIN,
    advertised_asin,
    campaign_id,
    ad_group_id,
    keyword_id,
    PURCHASED_ORDERS,
    PURCHASED_UNITS,
    PURCHASED_AMOUNT_USD,
    PURCHASED_ORDERS_1d,
    PURCHASED_ORDERS_7d,
    PURCHASED_ORDERS_14d,
    PURCHASED_ORDERS_30d,
    PURCHASED_UNITS_1d,
    PURCHASED_UNITS_7d,
    PURCHASED_UNITS_14d,
    PURCHASED_UNITS_30d,
    PURCHASED_AMOUNT_USD_1d,
    PURCHASED_AMOUNT_USD_7d,
    PURCHASED_AMOUNT_USD_14d,
    PURCHASED_AMOUNT_USD_30d,
    data_source
  FROM `onyga-482313.OI.SRC_ACC_AmazonAds_purchased_product`;

  SET record_count = @@row_count;
  SET end_time = CURRENT_TIMESTAMP();

  -- Log the operation results
  SELECT FORMAT(
    'SP_AmazonAds_purchased_product completed:\n' ||
    '  Records inserted: %d\n' ||
    '  Duration: %d seconds\n' ||
    '  Completed at: %s',
    record_count,
    TIMESTAMP_DIFF(end_time, start_time, SECOND),
    CAST(end_time AS STRING)
  ) as operation_summary;
END;
