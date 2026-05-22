-- =============================================
-- OI Database Project - SRC_ACC_FEE_PREVIEW Table
-- =============================================
--
-- Purpose: Permanent accumulation table for Amazon fee preview data
-- Source: V_SRC_FeePreview (Daton FeePreviewReport)
-- Pattern: TRUNCATE + INSERT (full refresh, small table)
-- Project: onyga-482313
-- Dataset: OI
-- Created: 2026-04-03
--
-- =============================================

CREATE OR REPLACE TABLE `onyga-482313.OI.SRC_ACC_FEE_PREVIEW` (
  marketplace_id STRING NOT NULL,
  asin STRING NOT NULL,
  sku STRING,
  fnsku STRING,
  product_name STRING,
  your_price NUMERIC,
  sales_price NUMERIC,
  estimated_fee_total NUMERIC,
  estimated_referral_fee_per_unit NUMERIC,
  estimated_variable_closing_fee NUMERIC,
  estimated_order_handling_fee_per_order NUMERIC,
  estimated_pick_pack_fee_per_unit NUMERIC,
  estimated_weight_handling_fee_per_unit NUMERIC,
  expected_fulfillment_fee_per_unit NUMERIC,
  product_size_tier STRING,
  currency STRING,
  _synced_at TIMESTAMP,
  -- Metadata
  source_file STRING DEFAULT 'DATON_API_AUTO',
  processed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP(),
  PRIMARY KEY (marketplace_id, asin) NOT ENFORCED
)
CLUSTER BY asin
OPTIONS (
  description = "Permanent accumulation table for Amazon fee preview data. Loaded by SP_SRC_ACC_FEE_PREVIEW from V_SRC_FeePreview."
);
