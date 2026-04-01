-- =============================================
-- OI Database Project - STG_PURCHASE_ORDER Table
-- =============================================
-- Staging table for Purchase Orders
-- Populated from V_PO_SNAPSHOT view by SP_DATA_ENTRY_UPDATES
-- =============================================

CREATE TABLE IF NOT EXISTS `onyga-482313.OI.STG_PURCHASE_ORDER` (
  snapshot_date DATE NOT NULL,
  year INT64,
  month INT64,
  quarter INT64,
  is_current_date BOOL,
  is_month_end BOOL,
  
  -- All PO fields
  purchase_order_id STRING NOT NULL,
  order_date DATE NOT NULL,
  manufacturer_name STRING NOT NULL,
  product_id INT64,
  product_asin STRING,
  product_name STRING,
  quantity INT64 NOT NULL,
  unit_price FLOAT64 NOT NULL,
  total_amount FLOAT64 NOT NULL,
  currency STRING DEFAULT 'USD',
  payment_status STRING DEFAULT 'PENDING',
  notes STRING,
  created_at TIMESTAMP,
  LAST_PAYMENT_DATE DATE,
  LAST_SHIPMENT_DATE DATE,
  LAST_ESTIMATED_ARRIVAL_DATE DATE,
  END_DATE DATE,
  
  -- Calculated fields from view
  payments_remaining FLOAT64,
  quantity_remaining_at_manufacturer INT64,
  quantity_remaining_at_shipment INT64,
  cogs_remaining_at_manufacturer FLOAT64,
  cogs_remaining_at_shipment FLOAT64,
  selling_price_remaining_at_manufacturer FLOAT64,
  selling_price_remaining_at_shipment FLOAT64,
  is_fully_paid_as_of_snapshot BOOL,
  is_fully_shipped_as_of_snapshot BOOL,
  is_complete_as_of_snapshot BOOL,
  
  -- Product dimension fields
  cost_of_goods FLOAT64,
  shipping_cost FLOAT64,
  
  -- Metadata
  loaded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP()
)
PARTITION BY snapshot_date
CLUSTER BY manufacturer_name, order_date;
