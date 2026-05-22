-- =============================================
-- OI Database Project - SRC_ACC_PRODUCTS Table
-- =============================================
--
-- Purpose: Permanent accumulation table for product catalog data
-- Source: V_SRC_Products (Daton CatalogItems + ActiveListingsReport)
-- Pattern: TRUNCATE + INSERT (full refresh, small table)
-- Project: onyga-482313
-- Dataset: OI
-- Created: 2026-04-03
--
-- =============================================

CREATE OR REPLACE TABLE `onyga-482313.OI.SRC_ACC_PRODUCTS` (
  asin STRING NOT NULL,
  marketplace STRING,
  sku STRING,
  parent_asin STRING,
  marketplace_name STRING,
  marketplace_country_code STRING,
  marketplace_default_currency_code STRING,
  product_name STRING,
  display_name STRING,
  brand STRING,
  manufacturer STRING,
  product_type STRING,
  color STRING,
  launch_date DATE,
  listing_price_currency_code STRING,
  listing_price_amount FLOAT64,
  item_height_unit STRING,
  item_height_value FLOAT64,
  item_length_unit STRING,
  item_length_value FLOAT64,
  item_weight_unit STRING,
  item_weight_value FLOAT64,
  item_width_unit STRING,
  item_width_value FLOAT64,
  package_height_unit STRING,
  package_height_value FLOAT64,
  package_length_unit STRING,
  package_length_value FLOAT64,
  package_weight_unit STRING,
  package_weight_value FLOAT64,
  package_width_unit STRING,
  package_width_value FLOAT64,
  _fivetran_synced TIMESTAMP,
  -- Metadata
  source_file STRING DEFAULT 'DATON_API_AUTO',
  processed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP(),
  PRIMARY KEY (asin) NOT ENFORCED
)
CLUSTER BY asin
OPTIONS (
  description = "Permanent accumulation table for product catalog data. Loaded by SP_SRC_ACC_PRODUCTS from V_SRC_Products."
);
