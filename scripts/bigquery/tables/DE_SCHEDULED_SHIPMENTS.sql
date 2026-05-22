-- DE_SCHEDULED_SHIPMENTS: Single-table for shipment lifecycle
-- Status lifecycle: SUGGESTED → APPROVED → SCHEDULED → SHIPPED
-- SUGGESTED = SP-generated (refreshed each run, auto-cleared before re-insert)
-- APPROVED = user-confirmed (qty editable)
-- SCHEDULED = manufacturer confirmed (qty locked)
-- SHIPPED = linked to DE_MANUFACTURER_SHIPMENTS
-- SP_GENERATE_SHIPMENT_PLAN reads APPROVED+SCHEDULED to deduct from demand before generating SUGGESTED
CREATE TABLE IF NOT EXISTS `onyga-482313.OI.DE_SCHEDULED_SHIPMENTS` (
  schedule_id STRING NOT NULL,          -- UUID (SP-generated for SUGGESTED, preserved on approval)
  product STRING NOT NULL,
  asin STRING NOT NULL,
  shipment_type INT64 NOT NULL,         -- 1=EMERGENCY, 2=EMERGENCY_PO, 3=AWD_MAINT, 4=Q4_BULK
  shipment_type_name STRING,
  route STRING,
  transit_type STRING,
  transit_days INT64,
  priority INT64,
  days_until_oos FLOAT64,
  ship_qty INT64 NOT NULL,              -- FLOOR'd to full cartons (package_quantity from DIM_PRODUCT)
  ship_cartons INT64,                   -- Number of full cartons
  mfr_ready_before INT64,
  in_production INT64,
  prior_type_allocations INT64,
  needs_new_po BOOL,
  new_po_qty INT64,
  po_ready_date DATE,
  ship_wednesday DATE,
  amazon_plan_date DATE,
  arrival_date DATE,
  shipment_num INT64,
  available_stock INT64,
  fba_stock INT64,
  awd_stock INT64,
  in_transit INT64,
  demand_window FLOAT64,
  demand_awd_window FLOAT64,
  shipment_trigger_reason STRING,
  ship_qty_reason STRING,
  status STRING DEFAULT 'SUGGESTED',    -- SUGGESTED | APPROVED | SCHEDULED | SHIPPED
  approved_at TIMESTAMP,
  scheduled_at TIMESTAMP,               -- set when APPROVED → SCHEDULED
  shipped_at TIMESTAMP,                 -- set when SCHEDULED → SHIPPED
  linked_shipment_id STRING,            -- FK to DE_MANUFACTURER_SHIPMENTS when SHIPPED
  notes STRING
);
