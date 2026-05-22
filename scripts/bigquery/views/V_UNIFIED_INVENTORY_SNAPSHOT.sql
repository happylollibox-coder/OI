-- =============================================
-- OI Database Project - V_UNIFIED_INVENTORY_SNAPSHOT
-- =============================================
--
-- Purpose: Unified view across all inventory source types
--
-- Source Types:
--   FBA        = From SRC_ACC_INVENTORY_FBA (historical) + V_SRC_FBAInventorySummary (today)
--                Uses fba_available_quantity = fulfillable + reserved - customer_orders
--   In Transit = afn_inbound_shipped + afn_inbound_receiving from V_SRC_FBAInventorySummary
--                Units shipped to Amazon but not yet checked in
--   AWD        = From SRC_ACC_INVENTORY_AWD (Amazon Warehousing & Distribution)
--
-- Note: Manufacturer source_type is NOT in this view.
--       Manufacturer quantities come from FACT_PURCHASE_ORDER and are added
--       by SP_LOAD_FACT_INVENTORY_SNAPSHOT via UNION ALL.
--
-- Project: onyga-482313
-- Dataset: OI
-- =============================================

CREATE OR REPLACE VIEW `onyga-482313.OI.V_UNIFIED_INVENTORY_SNAPSHOT` AS

-- FBA: fulfillable + reserved - customer_order_reserved
SELECT 
  Date,
  ASIN,
  SUM(fba_qty) AS quantity_balance,
  'FBA' AS source_type
FROM (
  -- Current day: use live data from V_SRC_FBAInventorySummary
  SELECT
    CURRENT_DATE() AS Date,
    src.asin AS ASIN,
    src.fba_available_quantity AS fba_qty
  FROM `onyga-482313.OI.V_SRC_FBAInventorySummary` src

  UNION ALL

  -- Historical days: use SRC_ACC_INVENTORY_FBA
  SELECT 
    acc.Date,
    acc.ASIN,
    acc.`Ending Warehouse Balance` AS fba_qty
  FROM `onyga-482313.OI.SRC_ACC_INVENTORY_FBA` acc
  WHERE acc.Date < CURRENT_DATE()
)
WHERE Date IS NOT NULL AND ASIN IS NOT NULL
GROUP BY Date, ASIN

UNION ALL

-- In Transit: inbound_shipped + inbound_receiving (already in Amazon's US pipeline, not yet checked in)
SELECT
  Date,
  ASIN,
  SUM(in_transit_qty) AS quantity_balance,
  'In Transit' AS source_type
FROM (
  -- Current day: use live data from V_SRC_FBAInventorySummary
  SELECT
    CURRENT_DATE() AS Date,
    src.asin AS ASIN,
    src.in_transit_quantity AS in_transit_qty
  FROM `onyga-482313.OI.V_SRC_FBAInventorySummary` src
  WHERE src.in_transit_quantity > 0

  UNION ALL

  -- Historical days: use SRC_ACC_INVENTORY_FBA
  SELECT 
    acc.Date,
    acc.ASIN,
    acc.in_transit_quantity AS in_transit_qty
  FROM `onyga-482313.OI.SRC_ACC_INVENTORY_FBA` acc
  WHERE acc.Date < CURRENT_DATE()
    AND acc.in_transit_quantity > 0
)
WHERE Date IS NOT NULL AND ASIN IS NOT NULL
GROUP BY Date, ASIN

UNION ALL

-- AWD: Amazon Warehousing & Distribution
SELECT 
  Date,
  ASIN,
  SUM(qty) AS quantity_balance,
  'AWD' AS source_type
FROM (
  -- Current day: use live data from V_SRC_AWDListInventory
  SELECT
    CURRENT_DATE() AS Date,
    src.asin AS ASIN,
    src.onhand_quantity AS qty
  FROM `onyga-482313.OI.V_SRC_AWDListInventory` src

  UNION ALL

  -- Historical days: use SRC_ACC_INVENTORY_AWD
  SELECT 
    acc.Date,
    acc.ASIN,
    acc.`Ending Warehouse Balance` * COALESCE(acc.`Package Quantity`, 1) AS qty
  FROM `onyga-482313.OI.SRC_ACC_INVENTORY_AWD` acc
  WHERE acc.Date < CURRENT_DATE()
)
WHERE Date IS NOT NULL
  AND ASIN IS NOT NULL
GROUP BY Date, ASIN;
