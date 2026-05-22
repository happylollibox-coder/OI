-- DE_ALERTS: Alert queue for shipment planning engine v2
-- Created: 2026-04-20
CREATE TABLE IF NOT EXISTS `onyga-482313.OI.DE_ALERTS` (
  id STRING NOT NULL,                    -- UUID
  alert_type STRING NOT NULL,            -- CREATE_PO, CREATE_SHIPMENT, UPDATE_AWD_TARGET, SALES_DEVIATION
  product_asin STRING,                   -- Product ASIN (nullable for multi-product alerts)
  product_name STRING,                   -- Product short name
  severity STRING,                       -- CRITICAL, WARNING, INFO
  title STRING NOT NULL,                 -- Short alert title
  description STRING,                    -- Detailed message with quantities/dates
  suggested_qty INT64,                   -- Suggested PO/shipment quantity
  suggested_split_fba INT64,             -- Split: units to FBA direct
  suggested_split_awd INT64,             -- Split: units to AWD
  fba_doc FLOAT64,                       -- FBA days-of-coverage at alert time
  system_doc FLOAT64,                    -- System (FBA+AWD+pipeline) DOC
  breach_date DATE,                      -- Projected date FBA DOC drops below 30
  related_po_id STRING,                  -- FK to DE_PURCHASE_ORDERS.id
  related_shipment_id STRING,            -- FK to DE_MANUFACTURER_SHIPMENTS.id
  status STRING,                         -- OPEN, DONE, CANCELLED, SNOOZED, AUTO_RESOLVED
  created_at TIMESTAMP,                  -- Alert creation time
  resolved_at TIMESTAMP,                 -- When user resolved
  resolved_by STRING,                    -- User who resolved
  notes STRING,                          -- User notes on resolution
  fire_day STRING,                       -- Day of week for recurring alerts (THURSDAY)
  action_type STRING,                    -- e.g., 'MODAL_CREATE_PO', 'MODAL_CREATE_SHIPMENT', 'LINK_PLAN_STRATEGY'
  action_payload JSON,                   -- Structured payload for the frontend
  snooze_until TIMESTAMP,                -- For delaying alerts
  related_plan_id STRING,                -- To link deviations to a specific frozen plan
  updated_at TIMESTAMP                   -- Last time the system updated the alert's numbers
)
OPTIONS (description = 'Alert queue for shipment planning engine v2');
