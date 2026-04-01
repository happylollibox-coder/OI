-- =============================================
-- OI Database Project - SP_UPDATE_PRODUCT_COST_DATA
-- =============================================
--
-- Purpose: Update DIM_PRODUCT with cost and logistics data from staging table
-- Business Logic: MERGE on ASIN to update cost, SKU, and logistics fields
-- Dependencies: STG_PRODUCT_COST_DATA staging table
-- Project: onyga-482313
-- Dataset: OI
-- Updated: 2025-01-01
--
-- =============================================

CREATE OR REPLACE PROCEDURE `onyga-482313.OI.SP_UPDATE_PRODUCT_COST_DATA`()
OPTIONS (
  description = "Update DIM_PRODUCT with cost and logistics data from STG_PRODUCT_COST_DATA staging table"
)
BEGIN
  DECLARE matched_count INT64;
  DECLARE start_time TIMESTAMP;

  SET start_time = CURRENT_TIMESTAMP();

  -- MERGE cost and logistics data from staging table into DIM_PRODUCT
  MERGE `onyga-482313.OI.DIM_PRODUCT` AS dim
  USING `onyga-482313.OI.STG_PRODUCT_COST_DATA` AS staging
  ON dim.asin = staging.asin
  WHEN MATCHED THEN
    UPDATE SET
      parent_name = COALESCE(staging.parent_name, dim.parent_name),
      sku = COALESCE(staging.sku, dim.sku),
      cost_of_goods = COALESCE(staging.cost_of_goods, dim.cost_of_goods),
      shipping_cost = COALESCE(staging.shipping_cost, dim.shipping_cost),
      manufacture_day = COALESCE(staging.manufacture_day, dim.manufacture_day),
      shipment_days = COALESCE(staging.shipment_days, dim.shipment_days),
      updated_at = CURRENT_TIMESTAMP();
  -- Note: Products not in DIM_PRODUCT are skipped (they should be added via SP_MERGE_PRODUCT_DIM first)

  SET matched_count = @@row_count;

  -- Log the operation results
  SELECT FORMAT(
    'SP_UPDATE_PRODUCT_COST_DATA completed: Updated %d rows, Duration: %d seconds',
    matched_count,
    TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), start_time, SECOND)
  ) as operation_summary;
END;
