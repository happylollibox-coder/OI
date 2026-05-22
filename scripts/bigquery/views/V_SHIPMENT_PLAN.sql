-- V_SHIPMENT_PLAN: Thin classification layer for shipment recommendations
-- Single source of truth for: shipment type, priority, dates, quantities
-- Reads all demand/forecast data from V_PLAN_FORECAST (Invariant #9)
-- Transit days from DE_LIST_OF_VALUES (Invariant #10: no hardcoded values)
--
-- Shipment Types:
--   AWD_MAINTENANCE — MFR→AWD via SLOW_SEA for products with DOC < 90 days
--   NEW_PO_REQUIRED — PO→MFR→AWD for products needing new purchase orders
--   Q4_BULK         — MFR→AWD via AWD_SLOW_SEA, weekly consolidated Jun-Aug
--
-- Priority: CEIL(weeks_to_OOS / 7) + 1 (from V_PLAN_FORECAST.emergency_priority)
--   P1 = OOS today, P2 = OOS within 1 week, etc.
--   Manufacturer uses priority to decide what to push first.
--
-- Dependencies:
--   V_PLAN_FORECAST (demand, inventory, supply readiness, OOS timing)
--   DE_LIST_OF_VALUES (transit days per shipment type)

CREATE OR REPLACE VIEW `onyga-482313.OI.V_SHIPMENT_PLAN` AS

WITH
-- Transit days from DE_LIST_OF_VALUES (no hardcoded values)
transit AS (
  SELECT value_id, CAST(attr1_value AS INT64) AS days
  FROM `onyga-482313.OI.DE_LIST_OF_VALUES`
  WHERE lov_set = 'SHIPMENT_TYPE'
),
slow_sea AS (SELECT days FROM transit WHERE value_id = 'SLOW_SEA'),
fast_sea AS (SELECT days FROM transit WHERE value_id = 'FAST_SEA'),
awd_slow AS (SELECT days FROM transit WHERE value_id = 'AWD_SLOW_SEA'),

-- AWD→FBA transfer buffer (days)
awd_fba_buffer AS (SELECT 5 AS days),

-- Products needing replenishment (DOC < 90 days)
replenish AS (
  SELECT p.*
  FROM `onyga-482313.OI.V_PLAN_FORECAST` p
  WHERE p.daily_rate > 0 AND p.is_emergency = TRUE
),

-- Q4 bulk: Wednesday ship dates from June 1 → August 31
q4_wednesdays AS (
  SELECT d AS ship_date,
    DATE_SUB(d, INTERVAL 6 DAY) AS amazon_plan_date,
    ROW_NUMBER() OVER (ORDER BY d) AS shipment_num
  FROM UNNEST(GENERATE_DATE_ARRAY(
    DATE(EXTRACT(YEAR FROM CURRENT_DATE()), 6, 1),
    DATE(EXTRACT(YEAR FROM CURRENT_DATE()), 8, 31),
    INTERVAL 1 DAY
  )) d
  WHERE EXTRACT(DAYOFWEEK FROM d) = 4  -- Wednesday = 4 in BQ
),
q4_count AS (SELECT COUNT(*) AS n FROM q4_wednesdays)

-- === TYPE 1: AWD MAINTENANCE (ship existing mfr stock → AWD) ===
SELECT
  r.product,
  'AWD_MAINTENANCE' AS shipment_type,
  'MFR→AWD' AS route,
  r.emergency_priority AS priority,
  r.days_until_oos,
  DATE_ADD(CURRENT_DATE(), INTERVAL r.days_until_oos DAY) AS oos_date,
  -- Last day to ship: OOS date minus SLOW_SEA transit minus AWD→FBA buffer
  DATE_ADD(CURRENT_DATE(), INTERVAL CAST(r.days_until_oos - ss.days - ab.days AS INT64) DAY) AS last_day_to_ship,
  -- Ship qty = what's ready at manufacturer (capped at demand gap)
  LEAST(r.ready_to_ship, CAST(r.demand_90d - r.available_stock AS INT64)) AS ship_qty,
  r.ready_to_ship AS mfr_ready,
  r.in_production AS mfr_in_prod,
  FALSE AS needs_new_po,
  CAST(NULL AS INT64) AS po_qty,
  -- Ship Wednesday: next Wed after stock ready (ready_to_ship > 0 means today)
  DATE_ADD(CURRENT_DATE(),
    INTERVAL MOD(11 - EXTRACT(DAYOFWEEK FROM CURRENT_DATE()), 7) DAY
  ) AS ship_wednesday,
  -- Amazon plan Thursday: 6 days before ship
  DATE_SUB(
    DATE_ADD(CURRENT_DATE(),
      INTERVAL MOD(11 - EXTRACT(DAYOFWEEK FROM CURRENT_DATE()), 7) DAY),
    INTERVAL 6 DAY
  ) AS amazon_plan_date,
  -- Arrival: ship + SLOW_SEA
  DATE_ADD(
    DATE_ADD(CURRENT_DATE(),
      INTERVAL MOD(11 - EXTRACT(DAYOFWEEK FROM CURRENT_DATE()), 7) DAY),
    INTERVAL ss.days DAY
  ) AS arrival_date,
  'SLOW_SEA' AS transit_type,
  ss.days AS transit_days,
  CAST(NULL AS INT64) AS shipment_num,
  r.available_stock,
  r.demand_90d,
  r.proportional_daily_demand
FROM replenish r
CROSS JOIN slow_sea ss
CROSS JOIN awd_fba_buffer ab
WHERE r.ready_to_ship > 0

UNION ALL

-- === TYPE 2: NEW PO REQUIRED (shortfall needs new PO → MFR → AWD) ===
SELECT
  r.product,
  'NEW_PO_REQUIRED' AS shipment_type,
  'PO→MFR→AWD' AS route,
  r.emergency_priority AS priority,
  r.days_until_oos,
  DATE_ADD(CURRENT_DATE(), INTERVAL r.days_until_oos DAY) AS oos_date,
  DATE_ADD(CURRENT_DATE(), INTERVAL CAST(r.days_until_oos - ss.days - ab.days AS INT64) DAY) AS last_day_to_ship,
  -- PO qty = shortfall (demand gap minus what's already ready/in-prod)
  GREATEST(0, CAST(r.demand_90d AS INT64) - r.available_stock - r.ready_to_ship - r.in_production) AS ship_qty,
  0 AS mfr_ready,
  r.in_production AS mfr_in_prod,
  TRUE AS needs_new_po,
  GREATEST(0, CAST(r.demand_90d AS INT64) - r.available_stock - r.ready_to_ship - r.in_production) AS po_qty,
  -- Ship Wednesday: after manufacture_day
  DATE_ADD(
    DATE_ADD(CURRENT_DATE(), INTERVAL r.manufacture_day DAY),
    INTERVAL MOD(11 - EXTRACT(DAYOFWEEK FROM DATE_ADD(CURRENT_DATE(), INTERVAL r.manufacture_day DAY)), 7) DAY
  ) AS ship_wednesday,
  DATE_SUB(
    DATE_ADD(
      DATE_ADD(CURRENT_DATE(), INTERVAL r.manufacture_day DAY),
      INTERVAL MOD(11 - EXTRACT(DAYOFWEEK FROM DATE_ADD(CURRENT_DATE(), INTERVAL r.manufacture_day DAY)), 7) DAY),
    INTERVAL 6 DAY
  ) AS amazon_plan_date,
  DATE_ADD(
    DATE_ADD(
      DATE_ADD(CURRENT_DATE(), INTERVAL r.manufacture_day DAY),
      INTERVAL MOD(11 - EXTRACT(DAYOFWEEK FROM DATE_ADD(CURRENT_DATE(), INTERVAL r.manufacture_day DAY)), 7) DAY),
    INTERVAL ss.days DAY
  ) AS arrival_date,
  'SLOW_SEA' AS transit_type,
  ss.days AS transit_days,
  CAST(NULL AS INT64) AS shipment_num,
  r.available_stock,
  r.demand_90d,
  r.proportional_daily_demand
FROM replenish r
CROSS JOIN slow_sea ss
CROSS JOIN awd_fba_buffer ab
WHERE r.ready_to_ship < (r.demand_90d - r.available_stock)
  AND r.in_production = 0

UNION ALL

-- === TYPE 3: Q4 BULK (all products, weekly consolidated Jun-Aug → AWD) ===
SELECT
  p.product,
  'Q4_BULK' AS shipment_type,
  'MFR→AWD' AS route,
  -- Q4 priority is always lower than emergency (emergency_priority + 100)
  p.emergency_priority + 100 AS priority,
  p.days_until_oos,
  DATE_ADD(CURRENT_DATE(), INTERVAL p.days_until_oos DAY) AS oos_date,
  CAST(NULL AS DATE) AS last_day_to_ship,
  -- Ship qty = Q4 demand evenly split across Wednesdays
  CAST(CEIL(p.q4_demand / c.n) AS INT64) AS ship_qty,
  p.ready_to_ship AS mfr_ready,
  p.in_production AS mfr_in_prod,
  -- Needs PO if pipeline (ready + in_prod) < Q4 demand
  (p.ready_to_ship + p.in_production) < p.q4_demand AS needs_new_po,
  CASE WHEN (p.ready_to_ship + p.in_production) < p.q4_demand
    THEN CAST(p.q4_demand AS INT64) - p.ready_to_ship - p.in_production
    ELSE NULL
  END AS po_qty,
  w.ship_date AS ship_wednesday,
  w.amazon_plan_date,
  DATE_ADD(w.ship_date, INTERVAL asea.days DAY) AS arrival_date,
  'AWD_SLOW_SEA' AS transit_type,
  asea.days AS transit_days,
  CAST(w.shipment_num AS INT64) AS shipment_num,
  p.available_stock,
  p.demand_90d,
  p.proportional_daily_demand
FROM `onyga-482313.OI.V_PLAN_FORECAST` p
CROSS JOIN q4_wednesdays w
CROSS JOIN q4_count c
CROSS JOIN awd_slow asea
WHERE p.daily_rate > 0
  AND p.q4_demand > 0
  AND w.ship_date >= CURRENT_DATE()

ORDER BY priority ASC, ship_wednesday ASC, product;
