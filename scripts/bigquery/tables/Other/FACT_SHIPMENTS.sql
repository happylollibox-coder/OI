-- =============================================
-- OI Database Project - DE_MANUFACTURER_SHIPMENTS Table
-- =============================================
-- Shipment header table — one row per physical shipment
-- Line items (per-PO breakdown) stored in DE_SHIPMENT_LINES
-- =============================================

CREATE OR REPLACE TABLE `onyga-482313.OI.DE_MANUFACTURER_SHIPMENTS` (
  shipment_id STRING NOT NULL,
  shipment_date DATE NOT NULL,
  estimated_arrival_date DATE,
  tracking_number STRING,
  shipment_type STRING, -- 'SLOW_SEA', 'FAST_SEA', 'AIR'
  total_quantity INT64, -- Sum of all line quantities (denormalized)
  kg_price FLOAT64,
  cost_shipped FLOAT64,
  is_paid BOOLEAN DEFAULT FALSE,
  paid_date DATE,
  shipment_status STRING DEFAULT 'PENDING',
  notes STRING,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP(),
  
  PRIMARY KEY (shipment_id) NOT ENFORCED
);
