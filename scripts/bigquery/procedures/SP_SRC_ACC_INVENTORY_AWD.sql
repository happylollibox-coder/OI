-- =============================================
-- OI Database Project - SP_SRC_ACC_INVENTORY_AWD
-- =============================================
--
-- Purpose: Daily accumulation of AWD inventory snapshots from Daton
--          (V_SRC_AWDListInventory) into SRC_ACC_INVENTORY_AWD.
--
-- Method: INSERT today's snapshot as a new daily row per ASIN.
--         AWD is a current-state snapshot; we accumulate daily history.
--
-- Idempotent: DELETE + INSERT for CURRENT_DATE() to allow safe re-runs.
--
-- Schedule: Daily via SP_ORCHESTRATE_DAILY_REFRESH (Task 10.5)
-- Project: onyga-482313
-- Dataset: OI
-- =============================================

CREATE OR REPLACE PROCEDURE `onyga-482313.OI.SP_SRC_ACC_INVENTORY_AWD`()
OPTIONS (
  description = "Daily accumulation of AWD inventory from Daton V_SRC_AWDListInventory into SRC_ACC_INVENTORY_AWD"
)
BEGIN
  DECLARE snapshot_date DATE DEFAULT CURRENT_DATE();
  DECLARE inserted_count INT64;

  -- Idempotent: remove today's data if re-running
  DELETE FROM `onyga-482313.OI.SRC_ACC_INVENTORY_AWD`
  WHERE Date = snapshot_date;

  -- Insert today's AWD snapshot from Daton
  INSERT INTO `onyga-482313.OI.SRC_ACC_INVENTORY_AWD` (
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
    insert_date, insert_file_name,
    `Package Quantity`
  )
  SELECT
    snapshot_date AS Date,
    '' AS FNSKU,  -- AWD doesn't use FNSKU
    src.asin AS ASIN,
    src.MSKU,
    src.Title,
    'SELLABLE' AS Disposition,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    -- AWD onhand_quantity is already in units
    src.onhand_quantity AS `Ending Warehouse Balance`,
    0 AS `Unknown Events`,
    'AWD' AS Location,
    'US' AS Store,
    CURRENT_TIMESTAMP() AS insert_date,
    'SP_SRC_ACC_INVENTORY_AWD' AS insert_file_name,
    1 AS `Package Quantity`  -- Already in units, no conversion needed
  FROM `onyga-482313.OI.V_SRC_AWDListInventory` src;

  SET inserted_count = @@row_count;

  SELECT FORMAT('SP_SRC_ACC_INVENTORY_AWD: Inserted %d AWD rows for %s', inserted_count, CAST(snapshot_date AS STRING)) AS log_message;
END;
