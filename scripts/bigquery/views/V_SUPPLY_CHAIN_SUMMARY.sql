-- =============================================
-- V_SUPPLY_CHAIN_SUMMARY
-- =============================================
-- Supply chain health per ASIN: days of coverage,
-- next shipment date, and next shipment quantity.
--
-- DOC uses forecast-based daily rate from V_PLAN_FORECAST
-- (standardized across all consumers: SP_GENERATE_ALERTS, 
--  AlertsPage, HomePage product table).
--
-- Sources:
--   FACT_INVENTORY_SNAPSHOT  →  current stock (FBA+AWD), in-transit,
--                               next_shipment_quantity, next_shipment_arrival_date
--   V_PLAN_FORECAST          →  forecast-based daily_rate for DOC
--   DIM_PRODUCT               →  product_short_name, product_type
-- =============================================
CREATE OR REPLACE VIEW `onyga-482313.OI.V_SUPPLY_CHAIN_SUMMARY` AS
WITH latest_date AS (
  SELECT MAX(Date) AS snapshot_date
  FROM `onyga-482313.OI.FACT_INVENTORY_SNAPSHOT`
),

-- Current sellable inventory (FBA + AWD)
sellable AS (
  SELECT
    i.ASIN,
    SUM(i.quantity_balance) AS sellable_qty,
    SUM(CASE WHEN i.source_type = 'AWD' THEN i.quantity_balance ELSE 0 END) AS awd_stock_qty,
    SUM(CASE WHEN i.source_type = 'FBA' THEN i.quantity_balance ELSE 0 END) AS fba_stock_qty
  FROM `onyga-482313.OI.FACT_INVENTORY_SNAPSHOT` i
  CROSS JOIN latest_date ld
  WHERE i.Date = ld.snapshot_date
    AND i.source_type IN ('FBA', 'AWD')
  GROUP BY i.ASIN
),

-- In-transit inventory
in_transit AS (
  SELECT
    i.ASIN,
    SUM(i.quantity_balance) AS in_transit_qty
  FROM `onyga-482313.OI.FACT_INVENTORY_SNAPSHOT` i
  CROSS JOIN latest_date ld
  WHERE i.Date = ld.snapshot_date
    AND i.source_type = 'In Transit'
  GROUP BY i.ASIN
),

-- Incoming AWD Shipments (Physical shipments created)
incoming_awd AS (
  SELECT p.asin, sum(l.quantity_shipped) as awd_incoming_qty
  FROM `onyga-482313.OI.DE_MANUFACTURER_SHIPMENTS` s
  JOIN `onyga-482313.OI.DE_SHIPMENT_LINES` l ON s.shipment_id = l.shipment_id
  JOIN `onyga-482313.OI.DIM_PRODUCT` p ON l.product_id = p.product_id
  WHERE s.shipment_type LIKE '%AWD%'
    AND s.shipment_status = 'PENDING'
  GROUP BY p.asin
),

-- Next shipment (pre-computed in SP_LOAD_FACT_INVENTORY_SNAPSHOT)
next_ship AS (
  SELECT
    i.ASIN,
    MAX(i.next_shipment_arrival_date) AS next_shipment_date,
    MAX(i.next_shipment_quantity)     AS next_shipment_qty
  FROM `onyga-482313.OI.FACT_INVENTORY_SNAPSHOT` i
  CROSS JOIN latest_date ld
  WHERE i.Date = ld.snapshot_date
    AND i.next_shipment_arrival_date IS NOT NULL
  GROUP BY i.ASIN
),

-- Forecast-based data from V_PLAN_FORECAST (single source of truth)
-- Uses walkthrough DOC (month-by-month depletion) for accurate coverage.
forecast_rate AS (
  SELECT asin, daily_rate, proportional_daily_demand,
    sellable_doc_walk, fba_doc_walk,
    demand_30d, demand_45d, demand_60d, demand_90d,
    last_30d_sold, last_30d_planned
  FROM `onyga-482313.OI.V_PLAN_FORECAST`
  WHERE daily_rate > 0 OR proportional_daily_demand > 0 OR last_30d_sold > 0
),

-- Approved AWD Settings
awd_settings AS (
  SELECT asin, approved_min_units, approved_max_units
  FROM `onyga-482313.OI.DE_AWD_SETTINGS`
)

SELECT
  p.asin,
  p.product_short_name,
  p.product_type,
  ld.snapshot_date,

  -- Stock levels
  COALESCE(se.sellable_qty, 0)                                    AS sellable_qty,
  COALESCE(it.in_transit_qty, 0)                                  AS in_transit_qty,
  COALESCE(se.sellable_qty, 0) + COALESCE(it.in_transit_qty, 0)  AS total_available_qty,
  COALESCE(se.fba_stock_qty, 0)                                   AS fba_stock_qty,
  COALESCE(se.awd_stock_qty, 0)                                   AS awd_stock_qty,

  -- Velocity: use 90-day forward average (smooths seasonal dips)
  COALESCE(fr.proportional_daily_demand, fr.daily_rate, 0)        AS daily_velocity,

  -- Days of coverage (walkthrough: month-by-month depletion against forecast)
  CASE WHEN fr.sellable_doc_walk IS NOT NULL AND fr.sellable_doc_walk < 999
    THEN CAST(fr.sellable_doc_walk AS INT64) ELSE NULL END        AS days_of_coverage,
  CASE WHEN fr.fba_doc_walk IS NOT NULL AND fr.fba_doc_walk < 999
    THEN CAST(fr.fba_doc_walk AS INT64) ELSE NULL END             AS fba_days_of_coverage,
  CASE WHEN fr.sellable_doc_walk IS NOT NULL AND fr.fba_doc_walk IS NOT NULL
        AND fr.sellable_doc_walk < 999
    THEN CAST(GREATEST(fr.sellable_doc_walk - fr.fba_doc_walk, 0) AS INT64)
    ELSE NULL END                                                  AS awd_days_of_coverage,

  ns.next_shipment_date,
  CASE
    WHEN ns.next_shipment_date IS NOT NULL
    THEN DATE_DIFF(ns.next_shipment_date, CURRENT_DATE(), DAY)
    ELSE NULL
  END                                                              AS days_to_next_shipment,
  ns.next_shipment_qty                                             AS next_shipment_qty,

  -- AWD Targets (using exact seasonal demand for next 30/45 days; only show if product has AWD stock or incoming AWD shipment)
  CASE WHEN COALESCE(se.awd_stock_qty, 0) > 0 OR COALESCE(ia.awd_incoming_qty, 0) > 0
    THEN CAST(ROUND(COALESCE(NULLIF(fr.demand_30d, 0), fr.daily_rate * 30, 0)) AS INT64)
    ELSE NULL END AS awd_target_min,
  CASE WHEN COALESCE(se.awd_stock_qty, 0) > 0 OR COALESCE(ia.awd_incoming_qty, 0) > 0
    THEN CAST(ROUND(COALESCE(NULLIF(fr.demand_45d, 0), fr.daily_rate * 45, 0)) AS INT64)
    ELSE NULL END AS awd_target_max,
  awd.approved_min_units                                           AS awd_approved_min,
  awd.approved_max_units                                           AS awd_approved_max,

  -- AWD Diff Percentage vs Approved Max (since Max drives the replenishment volume)
  -- Stored as percentage: 15 = 15%.  Frontend thresholds: >10, >20, >30.
  CASE 
    WHEN (COALESCE(se.awd_stock_qty, 0) = 0 AND COALESCE(ia.awd_incoming_qty, 0) = 0) THEN NULL
    WHEN awd.approved_max_units IS NOT NULL AND awd.approved_max_units > 0
    THEN ROUND(ABS(CAST(ROUND(COALESCE(NULLIF(fr.demand_45d, 0), fr.daily_rate * 45, 0)) AS FLOAT64) - awd.approved_max_units) / awd.approved_max_units * 100, 1)
    ELSE 100.0 -- Treat as 100% diff if not approved yet
  END                                                              AS awd_diff_pct,

  -- New stock measures requested
  COALESCE(fr.last_30d_sold, 0)                                    AS last_30d_sold,
  COALESCE(fr.last_30d_planned, 0)                                  AS last_30d_planned,
  COALESCE(fr.demand_30d, 0)                                       AS next_30d_planned,
  GREATEST(COALESCE(fr.demand_60d, 0) - COALESCE(fr.demand_30d, 0), 0) AS next_31_60d_planned,
  GREATEST(COALESCE(fr.demand_90d, 0) - COALESCE(fr.demand_60d, 0), 0) AS next_61_90d_planned

FROM `onyga-482313.OI.DIM_PRODUCT` p
CROSS JOIN latest_date ld
LEFT JOIN sellable se      ON se.ASIN = p.asin
LEFT JOIN in_transit it    ON it.ASIN = p.asin
LEFT JOIN incoming_awd ia  ON ia.ASIN = p.asin
LEFT JOIN next_ship ns     ON ns.ASIN = p.asin
LEFT JOIN forecast_rate fr ON fr.asin = p.asin
LEFT JOIN awd_settings awd ON awd.asin = p.asin
WHERE p.marketplace = 'ATVPDKIKX0DER'
  AND p.asin IS NOT NULL
  AND p.asin != 'UNKNOWN'
  AND (COALESCE(se.sellable_qty, 0) > 0
    OR COALESCE(it.in_transit_qty, 0) > 0
    OR COALESCE(fr.proportional_daily_demand, fr.daily_rate, 0) > 0
    OR ns.next_shipment_date IS NOT NULL);
