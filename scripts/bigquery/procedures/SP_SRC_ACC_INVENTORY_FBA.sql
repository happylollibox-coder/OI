-- =============================================
-- OI Database Project - SP_SRC_ACC_INVENTORY_FBA
-- =============================================
--
-- Purpose: Daily accumulation of FBA inventory snapshots from Daton
--          (V_SRC_FBAInventorySummary) into SRC_ACC_INVENTORY_FBA.
--
-- Method: INSERT today's snapshot as a new daily row per ASIN.
--         The Daton source is a POINT-IN-TIME snapshot (no date column),
--         so we stamp each load with CURRENT_DATE() and accumulate history.
--
-- Quantity Logic (as of 2026-04-04):
--   Ending Warehouse Balance = fba_available_quantity
--     = afn_fulfillable + afn_reserved - pending_customer_orders
--   This excludes units already sold (customer-order reserved) and
--   excludes inbound_shipped (which are shown as "In Transit" source_type)
--
-- Idempotent: DELETE + INSERT for CURRENT_DATE() to allow safe re-runs.
--
-- Schedule: Daily via SP_ORCHESTRATE_DAILY_REFRESH (before Task 11)
-- Project: onyga-482313
-- Dataset: OI
-- =============================================

CREATE OR REPLACE PROCEDURE `onyga-482313.OI.SP_SRC_ACC_INVENTORY_FBA`()
OPTIONS (
  description = "Daily accumulation of FBA inventory from Daton into SRC_ACC_INVENTORY_FBA"
)
BEGIN
  DECLARE snapshot_date DATE DEFAULT CURRENT_DATE();
  DECLARE inserted_count INT64;

  -- Idempotent: remove today's data if re-running
  DELETE FROM `onyga-482313.OI.SRC_ACC_INVENTORY_FBA`
  WHERE Date = snapshot_date;

  -- Insert today's snapshot from Daton
  -- Uses fba_available_quantity = fulfillable + reserved - customer_order_reserved
  INSERT INTO `onyga-482313.OI.SRC_ACC_INVENTORY_FBA` (
    Date, FNSKU, ASIN, MSKU, Title, Disposition,
    `Starting Warehouse Balance`,
    `In Transit Between Warehouses`,
    Receipts,
    `Customer Shipments`,
    `Customer Returns`,
    `Vendor Returns`,
    `Warehouse Transfer In_Out`,
    Found, Lost, Damaged, Disposed,
    `Other Events`,
    `Ending Warehouse Balance`,
    `Unknown Events`,
    Location, Store,
    in_transit_quantity,
    insert_date, insert_file_name
  )
  SELECT
    snapshot_date AS Date,
    src.FNSKU,
    src.asin AS ASIN,
    src.MSKU,
    src.Title,
    'SELLABLE' AS Disposition,
    -- Movement columns: not tracked in FBA summary, set to 0
    0 AS `Starting Warehouse Balance`,
    0 AS `In Transit Between Warehouses`,
    0 AS Receipts,
    0 AS `Customer Shipments`,
    0 AS `Customer Returns`,
    0 AS `Vendor Returns`,
    0 AS `Warehouse Transfer In_Out`,
    0 AS Found,
    0 AS Lost,
    0 AS Damaged,
    0 AS Disposed,
    0 AS `Other Events`,
    -- fba_available_quantity = fulfillable + reserved - pending_customer_orders
    src.fba_available_quantity AS `Ending Warehouse Balance`,
    0 AS `Unknown Events`,
    'FBA' AS Location,
    'US' AS Store,
    src.in_transit_quantity,
    CURRENT_TIMESTAMP() AS insert_date,
    'SP_SRC_ACC_INVENTORY_FBA' AS insert_file_name
  FROM `onyga-482313.OI.V_SRC_FBAInventorySummary` src;

  SET inserted_count = @@row_count;

  SELECT FORMAT('SP_SRC_ACC_INVENTORY_FBA: Inserted %d FBA rows for %s', inserted_count, CAST(snapshot_date AS STRING)) AS log_message;
END;
