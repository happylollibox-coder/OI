-- =============================================
-- OI Database Project - DIM_COSTS_HISTORY Table
-- =============================================
--
-- Purpose: Slowly changing dimension (SCD Type 2) for FBA fee preview + cost data
-- Fee data from fee_preview_report, cost_of_goods/shipping_cost from DIM_PRODUCT
-- Source: fivetran-hl.amazon_selling_partner.fee_preview_report + DIM_PRODUCT
-- Project: onyga-482313
-- Dataset: OI
--
-- =============================================

CREATE TABLE IF NOT EXISTS `onyga-482313.OI.DIM_COSTS_HISTORY` (
  -- Business key (join: marketplace_id, asin, sku)
  marketplace_id STRING,
  asin STRING,
  sku STRING,
  -- Fee preview attributes (align with Fivetran fee_preview_report schema)
  estimated_pick_pack_fee_per_unit FLOAT64,
  FBA_COST_estimated_fee_total FLOAT64,
  FBA_COST_estimated_referral_fee_per_unit FLOAT64,
  -- Cost fields from DIM_PRODUCT
  cost_of_goods FLOAT64,
  shipping_cost FLOAT64,
  TOTAL_COST_PER_UNIT FLOAT64,  -- cost_of_goods + FBA_COST_estimated_fee_total + shipping_cost
  -- Additional fee columns if present in source (adjust to match Fivetran schema)
  fnsku STRING,
  product_name STRING,
  _fivetran_synced TIMESTAMP,
  -- SCD Type 2: version validity
  start_date DATE NOT NULL,
  end_date DATE
)
PARTITION BY start_date
CLUSTER BY marketplace_id, asin, sku
OPTIONS (
  description = "SCD Type 2 dimension for FBA fee preview report. start_date/end_date track version validity. Current record: end_date IS NULL."
);
