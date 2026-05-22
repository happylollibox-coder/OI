-- =============================================
-- OI Database Project - SP_SRC_ACC_FEE_PREVIEW
-- =============================================
--
-- Purpose: Load SRC_ACC_FEE_PREVIEW from V_SRC_FeePreview (full refresh)
-- Pattern: TRUNCATE + INSERT (small table, ~10 rows)
-- Source: V_SRC_FeePreview (Daton FeePreviewReport)
-- Project: onyga-482313
-- Dataset: OI
-- Created: 2026-04-03
--
-- =============================================

CREATE OR REPLACE PROCEDURE `onyga-482313.OI.SP_SRC_ACC_FEE_PREVIEW`()
OPTIONS (
  description = "Load SRC_ACC_FEE_PREVIEW from V_SRC_FeePreview. TRUNCATE + INSERT full refresh."
)
BEGIN
  DECLARE v_processed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP();
  DECLARE record_count INT64 DEFAULT 0;
  DECLARE start_time TIMESTAMP;

  SET start_time = CURRENT_TIMESTAMP();

  TRUNCATE TABLE `onyga-482313.OI.SRC_ACC_FEE_PREVIEW`;

  INSERT INTO `onyga-482313.OI.SRC_ACC_FEE_PREVIEW` (
    marketplace_id, asin, sku, fnsku, product_name,
    your_price, sales_price, estimated_fee_total,
    estimated_referral_fee_per_unit, estimated_variable_closing_fee,
    estimated_order_handling_fee_per_order, estimated_pick_pack_fee_per_unit,
    estimated_weight_handling_fee_per_unit, expected_fulfillment_fee_per_unit,
    product_size_tier, currency, _synced_at, source_file, processed_at
  )
  SELECT
    marketplace_id, asin, sku, fnsku, product_name,
    your_price, sales_price, estimated_fee_total,
    estimated_referral_fee_per_unit, estimated_variable_closing_fee,
    estimated_order_handling_fee_per_order, estimated_pick_pack_fee_per_unit,
    estimated_weight_handling_fee_per_unit, expected_fulfillment_fee_per_unit,
    product_size_tier, currency, _synced_at, 'DATON_API_AUTO', v_processed_at
  FROM `onyga-482313.OI.V_SRC_FeePreview`;

  SET record_count = @@row_count;

  SELECT FORMAT(
    'SP_SRC_ACC_FEE_PREVIEW completed: %d records inserted. Duration: %d seconds',
    record_count, TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), start_time, SECOND)
  ) as operation_summary;
END;
