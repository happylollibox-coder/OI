-- =============================================
-- OI Database Project - STG_FBA_INVENTORY_MONTHLY_SNAPSHOT Table
-- =============================================
--
-- Purpose: Monthly snapshot table for FBA inventory summary data
-- Only current month is updated, previous months are frozen
-- Project: onyga-482313
-- Dataset: OI
--
-- =============================================

CREATE OR REPLACE TABLE `onyga-482313.OI.STG_FBA_INVENTORY_MONTHLY_SNAPSHOT` (
  -- Month identifier (YYYY-MM format)
  snapshot_month STRING NOT NULL,  -- Format: YYYY-MM
  snapshot_year INT64 NOT NULL,
  snapshot_month_num INT64 NOT NULL,
  
  -- Product dimension key
  product_id INT64,  -- FK to DIM_PRODUCT
  
  -- Product identifiers from source
  asin STRING,
  fnsku STRING,
  seller_sku STRING,
  
  -- All fields from fba_inventory_summary (adjust based on actual schema)
  -- Note: These fields should match the source table structure
  -- Common FBA inventory fields:
  product_name STRING,
  condition_type STRING,
  warehouse_condition_code STRING,
  quantity_available INT64,
  quantity_reserved INT64,
  quantity_unfulfillable INT64,
  quantity_total INT64,
  inbound_quantity INT64,
  inbound_working INT64,
  inbound_shipped INT64,
  inbound_receiving INT64,
  reserved_fc_transfers INT64,
  reserved_fc_processing INT64,
  reserved_customer_orders INT64,
  unfulfillable_quantity INT64,
  unfulfillable_customer_damage INT64,
  unfulfillable_warehouse_damage INT64,
  unfulfillable_distributor_damage INT64,
  unfulfillable_carrier_damage INT64,
  unfulfillable_defective INT64,
  unfulfillable_expired INT64,
  
  -- Source metadata
  granularity_id STRING,  -- Should be 'ATVPDKIKX0DER'
  snapshot_date DATE NOT NULL,  -- Date when snapshot was taken
  
  -- Audit fields
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP(),
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP(),
  
  -- Primary Key
  PRIMARY KEY (snapshot_month, asin, fnsku) NOT ENFORCED
)
PARTITION BY snapshot_year
CLUSTER BY snapshot_month, asin;

-- =============================================
-- TABLE DESCRIPTION
-- =============================================
--
-- This table holds monthly snapshots of FBA inventory data.
-- Key Features:
-- - Only current month is updated (previous months are frozen)
-- - Filtered by granularity_id = 'ATVPDKIKX0DER'
-- - Joined to DIM_PRODUCT for product dimension data
-- - Partitioned by year for performance
--
-- The SP_UPDATE_FBA_INVENTORY_MONTHLY_SNAPSHOT procedure manages this table:
-- - Updates current month's snapshot
-- - Inserts new month when month changes
-- - Previous months remain unchanged
--
-- =============================================
