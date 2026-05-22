-- =============================================
-- OI Database Project - SP_SRC_ACC_PRODUCTS
-- =============================================
--
-- Purpose: Load SRC_ACC_PRODUCTS from V_SRC_Products (full refresh)
-- Pattern: TRUNCATE + INSERT (small table, ~15 rows)
-- Source: V_SRC_Products (Daton CatalogItems + ActiveListingsReport)
-- Project: onyga-482313
-- Dataset: OI
-- Created: 2026-04-03
--
-- =============================================

CREATE OR REPLACE PROCEDURE `onyga-482313.OI.SP_SRC_ACC_PRODUCTS`()
OPTIONS (
  description = "Load SRC_ACC_PRODUCTS from V_SRC_Products. TRUNCATE + INSERT full refresh."
)
BEGIN
  DECLARE v_processed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP();
  DECLARE record_count INT64 DEFAULT 0;
  DECLARE start_time TIMESTAMP;

  SET start_time = CURRENT_TIMESTAMP();

  TRUNCATE TABLE `onyga-482313.OI.SRC_ACC_PRODUCTS`;

  INSERT INTO `onyga-482313.OI.SRC_ACC_PRODUCTS` (
    asin, marketplace, sku, parent_asin,
    marketplace_name, marketplace_country_code, marketplace_default_currency_code,
    product_name, display_name, brand, manufacturer, product_type, color, launch_date,
    listing_price_currency_code, listing_price_amount,
    item_height_unit, item_height_value, item_length_unit, item_length_value,
    item_weight_unit, item_weight_value, item_width_unit, item_width_value,
    package_height_unit, package_height_value, package_length_unit, package_length_value,
    package_weight_unit, package_weight_value, package_width_unit, package_width_value,
    _fivetran_synced, source_file, processed_at
  )
  SELECT
    asin, marketplace, sku, parent_asin,
    marketplace_name, marketplace_country_code, marketplace_default_currency_code,
    product_name, display_name, brand, manufacturer, product_type, color, launch_date,
    listing_price_currency_code, listing_price_amount,
    item_height_unit, item_height_value, item_length_unit, item_length_value,
    item_weight_unit, item_weight_value, item_width_unit, item_width_value,
    package_height_unit, package_height_value, package_length_unit, package_length_value,
    package_weight_unit, package_weight_value, package_width_unit, package_width_value,
    _fivetran_synced,
    'DATON_API_AUTO',
    v_processed_at
  FROM `onyga-482313.OI.V_SRC_Products`;

  SET record_count = @@row_count;

  SELECT FORMAT(
    'SP_SRC_ACC_PRODUCTS completed: %d records inserted. Duration: %d seconds',
    record_count, TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), start_time, SECOND)
  ) as operation_summary;
END;
