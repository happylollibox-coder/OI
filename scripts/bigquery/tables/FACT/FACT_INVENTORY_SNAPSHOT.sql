-- =============================================
-- OI Database Project - FACT_INVENTORY_SNAPSHOT Table
-- =============================================
-- Fact table for Inventory Snapshots
-- Combines V_UNIFIED_INVENTORY_SNAPSHOT with purchase order data
-- Adds COGS_AMOUNT and SELL_AMOUNT from FACT_PURCHASE_ORDER
-- =============================================

CREATE TABLE IF NOT EXISTS `onyga-482313.OI.FACT_INVENTORY_SNAPSHOT` (
  -- Fields from V_UNIFIED_INVENTORY_SNAPSHOT
  Date DATE NOT NULL,
  ASIN STRING NOT NULL,
  quantity_balance INT64,
  source_type STRING,
  
  -- Additional fields from FACT_PURCHASE_ORDER aggregation
  COGS_AMOUNT FLOAT64,
  SELL_AMOUNT FLOAT64,
  
  -- Product dimension fields
  cost_of_goods FLOAT64,
  shipping_cost FLOAT64,
  
  -- Factless Key
  factless_key STRING NOT NULL,        -- Composite key: date_key - asin (e.g., '20240101-B0123456789')
  
  -- Metadata
  loaded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP()
)
PARTITION BY Date
CLUSTER BY ASIN, source_type;
