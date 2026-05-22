-- DE_SHIPMENT_PLAN: Persists auto-generated or manually edited shipment plans
-- Linked to DE_PLAN_STRATEGY via plan_id
-- One row per product per ship per week

CREATE TABLE IF NOT EXISTS `onyga-482313.OI.DE_SHIPMENT_PLAN` (
  plan_id           STRING    NOT NULL,   -- FK to DE_PLAN_STRATEGY.plan_id
  shipment_week     INT64     NOT NULL,   -- Week number (1, 2, 3...)
  ship_number       INT64     NOT NULL,   -- Ship within week (1 or 2)
  ship_date         DATE      NOT NULL,   -- When this ship leaves port
  est_arrival       DATE      NOT NULL,   -- ship_date + transit_days
  route             STRING    NOT NULL,   -- 'FBA' or 'AWD'
  route_reason      STRING,               -- Cost comparison explanation
  shipment_type     STRING    NOT NULL,   -- FK to DE_LIST_OF_VALUES: AIR, FAST_SEA, SLOW_SEA, AWD_SLOW_SEA
  product           STRING    NOT NULL,   -- Product short name
  quantity          INT64     NOT NULL,   -- Units on this ship
  num_boxes         INT64,                -- Carton count
  total_cubic_feet  FLOAT64,              -- Volume
  est_ship_cost     FLOAT64,              -- quantity × SHIP rate
  est_mfr_cost      FLOAT64,              -- quantity × MFR rate
  status            STRING    NOT NULL DEFAULT 'PLANNED',  -- PLANNED / SHIPPED / CANCELLED
  updated_at        DATETIME  NOT NULL DEFAULT CURRENT_DATETIME()
);
