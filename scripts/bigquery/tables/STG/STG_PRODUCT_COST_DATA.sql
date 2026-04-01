-- =============================================
-- OI Database Project - STG_PRODUCT_COST_DATA Table
-- =============================================
--
-- Purpose: Staging table for manual product cost and logistics data
-- Used to update DIM_PRODUCT with cost, shipping, FBA, and logistics information
-- Project: onyga-482313
-- Dataset: OI
--
-- =============================================

-- Create staging table for product cost and logistics data
CREATE OR REPLACE TABLE `onyga-482313.OI.STG_PRODUCT_COST_DATA` (
  asin STRING NOT NULL, -- ASIN for joining to DIM_PRODUCT
  parent_name STRING, -- Parent product name
  sku STRING, -- Main SKU
  cost_of_goods FLOAT64, -- Cost of goods (COGS)
  shipping_cost FLOAT64, -- Shipping cost per unit
  manufacture_day INT64, -- Manufacturing days
  shipment_days INT64, -- Shipment days
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP(),
  
  PRIMARY KEY (asin) NOT ENFORCED
)
CLUSTER BY asin;

-- =============================================
-- TABLE DESCRIPTION
-- =============================================
--
-- This staging table holds manual product cost and logistics data that is
-- not available in Fivetran sources. Data can be loaded via:
-- - BigQuery Console UI (manual entry)
-- - CSV/JSON file upload
-- - INSERT statements
-- - Google Sheets import
--
-- The data is then merged into DIM_PRODUCT using SP_UPDATE_PRODUCT_COST_DATA
-- or via direct UPDATE/MERGE statements.
--
-- Key Features:
-- - asin: Primary key for joining to DIM_PRODUCT
-- - parent_name: Parent product name (new field)
-- - sku: Main SKU (updates sku field in DIM_PRODUCT)
-- - Cost fields: cost_of_goods, shipping_cost
-- - Logistics fields: manufacture_day, shipment_days
--
-- Usage:
-- 1. Load data into this staging table (via UI, CSV, or SQL)
-- 2. Run SP_UPDATE_PRODUCT_COST_DATA to merge data into DIM_PRODUCT
-- 3. Data persists in DIM_PRODUCT even if staging table is cleared
--
-- =============================================
