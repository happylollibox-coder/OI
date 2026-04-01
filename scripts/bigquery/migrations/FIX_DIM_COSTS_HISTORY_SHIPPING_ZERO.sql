-- =============================================
-- Migration: Fix shipping_cost = 0 bug in DIM_COSTS_HISTORY
-- =============================================
--
-- Problem: COALESCE(AVG(s.unit_cost), 0) in SP_LOAD_DIM_COSTS_HISTORY
--          set shipping_cost = 0 when no DE_MANUFACTURER_SHIPMENTS row existed,
--          instead of leaving it NULL for fallback logic.
--
-- Fix: NULL out bogus 0 values where no real shipment data exists,
--      then recalculate TOTAL_COST_PER_UNIT.
--
-- After running this, re-deploy SP_LOAD_DIM_COSTS_HISTORY and call it.
--
-- =============================================

-- Step 1: Set shipping_cost = NULL where it's 0 AND no real shipment data exists for that ASIN
UPDATE `onyga-482313.OI.DIM_COSTS_HISTORY` ch
SET
  shipping_cost = NULL,
  TOTAL_COST_PER_UNIT = COALESCE(ch.cost_of_goods, 0) + COALESCE(ch.FBA_COST_estimated_fee_total, 0)
WHERE ch.shipping_cost = 0
  AND NOT EXISTS (
    SELECT 1
    FROM `onyga-482313.OI.DE_MANUFACTURER_SHIPMENTS` s
    JOIN `onyga-482313.OI.DE_PURCHASE_ORDERS` po
      ON po.purchase_order_id = s.purchase_order_id
    WHERE po.product_asin = ch.asin
      AND s.unit_cost IS NOT NULL
      AND s.unit_cost > 0
  );

-- Step 2: Verify — check remaining shipping_cost = 0 rows (should only be real $0 shipments)
SELECT asin, sku, shipping_cost, cost_of_goods, TOTAL_COST_PER_UNIT, start_date, end_date
FROM `onyga-482313.OI.DIM_COSTS_HISTORY`
WHERE shipping_cost = 0
ORDER BY asin, start_date DESC;
