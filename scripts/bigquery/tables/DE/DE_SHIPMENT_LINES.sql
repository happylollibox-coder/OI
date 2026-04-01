-- =============================================
-- OI Database Project - DE_SHIPMENT_LINES Table
-- =============================================
-- Junction table linking shipments to purchase orders
-- A single shipment can include items from multiple POs
-- =============================================

CREATE OR REPLACE TABLE `onyga-482313.OI.DE_SHIPMENT_LINES` (
  line_id STRING NOT NULL,              -- UUID, e.g. SHL_abc123
  shipment_id STRING NOT NULL,          -- FK → DE_MANUFACTURER_SHIPMENTS
  purchase_order_id STRING NOT NULL,    -- FK → DE_PURCHASE_ORDERS
  quantity_shipped INT64 NOT NULL,       -- Units from this PO in this shipment
  num_cartons INT64,                     -- ceil(quantity_shipped / package_quantity)
  cubic_feet_per_carton FLOAT64,         -- From DIM_PRODUCT.package_cubic_feet at creation time
  total_cubic_feet FLOAT64,              -- num_cartons × cubic_feet_per_carton
  allocated_cost FLOAT64,               -- Computed: cubic-feet-proportional share of shipment cost
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP(),
  
  PRIMARY KEY (line_id) NOT ENFORCED
);
