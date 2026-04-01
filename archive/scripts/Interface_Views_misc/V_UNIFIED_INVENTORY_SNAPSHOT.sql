-- =============================================
-- OI Database Project - V_UNIFIED_INVENTORY_SNAPSHOT
-- =============================================
--
-- Purpose: Unified staging view combining FBA and AWD inventory data
-- Business Logic: 
--   - Unions SRC_ACC_INVENTORY_FBA and SRC_ACC_INVENTORY_AWD
--   - Converts AWD packages to units (multiplies by conversion factor)
--   - Groups by Date and ASIN, summing Ending Warehouse Balance
-- Dependencies: SRC_ACC_INVENTORY_FBA, SRC_ACC_INVENTORY_AWD
-- Project: onyga-482313
-- Dataset: OI
-- Updated: 2026-01-13
--
-- =============================================

CREATE OR REPLACE VIEW `onyga-482313.OI.V_UNIFIED_INVENTORY_SNAPSHOT` AS
SELECT 
  Date,
  ASIN,
  SUM(`Ending Warehouse Balance`) AS ending_warehouse_balance,
  'FBA' AS source_type
FROM `onyga-482313.OI.SRC_ACC_INVENTORY_FBA`
WHERE Date IS NOT NULL
  AND ASIN IS NOT NULL
GROUP BY Date, ASIN

UNION ALL

SELECT 
  Date,
  ASIN,
  -- AWD is per package, convert to units
  -- TODO: Replace 1 with actual units_per_package conversion factor if needed
  -- Example: SUM(`Ending Warehouse Balance` * units_per_package) if conversion factor is known
  SUM(`Ending Warehouse Balance` * 1) AS ending_warehouse_balance,
  'AWD' AS source_type
FROM `onyga-482313.OI.SRC_ACC_INVENTORY_AWD`
WHERE Date IS NOT NULL
  AND ASIN IS NOT NULL
GROUP BY Date, ASIN;
