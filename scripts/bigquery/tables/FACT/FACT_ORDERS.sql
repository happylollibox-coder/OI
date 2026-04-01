-- =============================================
-- OI Database Project - FACT_ORDERS Table
-- =============================================
-- Fact table for Purchase Orders
-- Populated by SP_DATA_ENTRY_UPDATES stored procedure
-- =============================================

CREATE TABLE IF NOT EXISTS `onyga-482313.OI.FACT_ORDERS` (
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
  
  -- Calculated fields from SP_DATA_ENTRY_UPDATES
  LAST_PAYMENT_DATE DATE,
  LAST_SHIPMENT_DATE DATE,
  LAST_ESTIMATED_ARRIVAL_DATE DATE,
  END_DATE DATE,
  
  -- Metadata
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP(),
  snapshot_date DATE DEFAULT CURRENT_DATE(), -- Date when this snapshot was created
  
  PRIMARY KEY (purchase_order_id) NOT ENFORCED
)
PARTITION BY snapshot_date
CLUSTER BY manufacturer_name, order_date;
