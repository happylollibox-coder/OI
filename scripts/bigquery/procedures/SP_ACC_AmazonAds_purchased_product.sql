-- =============================================
-- OI Database Project - SP_ACC_AmazonAds_purchased_product Stored Procedure
-- =============================================
--
-- Purpose: Accumulate purchased product data from view into SRC_ACC table
-- Pattern: MERGE (insert if not exists, update existing except 1d measures)
-- Source: V_SRC_AmazonAds_purchased_product
-- Target: SRC_ACC_AmazonAds_purchased_product
-- Project: onyga-482313
-- Dataset: OI
--
-- Key Behavior:
-- - New rows: INSERT with 1d measures = COALESCE(source_1d, source_default)
--   This captures the early 14d value as a 1d proxy for SB campaigns
-- - Existing rows: UPDATE default + 7d/14d/30d measures, but NOT 1d measures
--   This preserves the early 1d snapshot
--
-- =============================================

CREATE OR REPLACE PROCEDURE `onyga-482313.OI.SP_ACC_AmazonAds_purchased_product`()
OPTIONS (
  description = "Accumulate purchased product data from V_SRC_AmazonAds_purchased_product into SRC_ACC_AmazonAds_purchased_product using MERGE. Preserves 1d measures from first insert, updates all other measures."
)
BEGIN
  DECLARE insert_count INT64 DEFAULT 0;
  DECLARE update_count INT64 DEFAULT 0;
  DECLARE start_time TIMESTAMP;
  DECLARE end_time TIMESTAMP;

  SET start_time = CURRENT_TIMESTAMP();

  MERGE INTO `onyga-482313.OI.SRC_ACC_AmazonAds_purchased_product` AS target
  USING (
    SELECT
      date,
      purchased_asin AS PURCHASED_ASIN,
      advertised_asin,
      campaign_id,
      ad_group_id,
      keyword_id,
      orders AS PURCHASED_ORDERS,
      units AS PURCHASED_UNITS,
      sales AS PURCHASED_AMOUNT_USD,
      orders_1d,
      orders_7d,
      orders_14d,
      orders_30d,
      units_1d,
      units_7d,
      units_14d,
      units_30d,
      sales_1d,
      sales_7d,
      sales_14d,
      sales_30d,
      data_source
    FROM `onyga-482313.OI.V_SRC_AmazonAds_purchased_product`
  ) AS source
  ON  target.DATE = source.date
  AND target.PURCHASED_ASIN = source.PURCHASED_ASIN
  AND target.advertised_asin = source.advertised_asin
  AND target.campaign_id = source.campaign_id
  AND target.ad_group_id = source.ad_group_id
  AND target.keyword_id = source.keyword_id

  WHEN MATCHED THEN UPDATE SET
    -- Update default measures (grow over time for SB)
    target.PURCHASED_ORDERS = source.PURCHASED_ORDERS,
    target.PURCHASED_UNITS = source.PURCHASED_UNITS,
    target.PURCHASED_AMOUNT_USD = source.PURCHASED_AMOUNT_USD,
    -- Update 7d, 14d, 30d (grow over time)
    target.PURCHASED_ORDERS_7d = source.orders_7d,
    target.PURCHASED_ORDERS_14d = source.orders_14d,
    target.PURCHASED_ORDERS_30d = source.orders_30d,
    target.PURCHASED_UNITS_7d = source.units_7d,
    target.PURCHASED_UNITS_14d = source.units_14d,
    target.PURCHASED_UNITS_30d = source.units_30d,
    target.PURCHASED_AMOUNT_USD_7d = source.sales_7d,
    target.PURCHASED_AMOUNT_USD_14d = source.sales_14d,
    target.PURCHASED_AMOUNT_USD_30d = source.sales_30d,
    -- DO NOT update 1d measures (preserve early snapshot)
    target.last_updated_at = CURRENT_TIMESTAMP()

  WHEN NOT MATCHED THEN INSERT (
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
    data_source,
    first_seen_at,
    last_updated_at
  )
  VALUES (
    source.date,
    source.PURCHASED_ASIN,
    source.advertised_asin,
    source.campaign_id,
    source.ad_group_id,
    source.keyword_id,
    source.PURCHASED_ORDERS,
    source.PURCHASED_UNITS,
    source.PURCHASED_AMOUNT_USD,
    -- 1d: use actual 1d if available (SP), otherwise use default (SB early snapshot)
    COALESCE(source.orders_1d, source.PURCHASED_ORDERS),
    source.orders_7d,
    source.orders_14d,
    source.orders_30d,
    COALESCE(source.units_1d, source.PURCHASED_UNITS),
    source.units_7d,
    source.units_14d,
    source.units_30d,
    COALESCE(source.sales_1d, source.PURCHASED_AMOUNT_USD),
    source.sales_7d,
    source.sales_14d,
    source.sales_30d,
    source.data_source,
    CURRENT_TIMESTAMP(),
    CURRENT_TIMESTAMP()
  );

  SET end_time = CURRENT_TIMESTAMP();

  -- Log the operation results
  SELECT FORMAT(
    'SP_ACC_AmazonAds_purchased_product completed:\n' ||
    '  Duration: %d seconds\n' ||
    '  Completed at: %s',
    TIMESTAMP_DIFF(end_time, start_time, SECOND),
    CAST(end_time AS STRING)
  ) as operation_summary;
END;
