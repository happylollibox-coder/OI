-- =============================================
-- OI Database Project - SP_LOAD_FACT_INVENTORY_SNAPSHOT
-- =============================================
--
-- Purpose: Load FACT_INVENTORY_SNAPSHOT from V_UNIFIED_INVENTORY_SNAPSHOT
--          and add purchase order data (COGS_AMOUNT, SELL_AMOUNT) from FACT_PURCHASE_ORDER
--
-- Business Logic:
--   1. Start with all rows from V_UNIFIED_INVENTORY_SNAPSHOT
--   2. Left join to FACT_PURCHASE_ORDER on Date = snapshot_date AND ASIN = product_asin
--   3. Aggregate PO data per Date/ASIN:
--      - COGS_AMOUNT = sum of (cogs_remaining_at_manufacturer + cogs_remaining_at_shipment)
--      - SELL_AMOUNT = sum of (selling_price_remaining_at_manufacturer + selling_price_remaining_at_shipment)
--   4. Only include PO snapshots that exist in V_UNIFIED_INVENTORY_SNAPSHOT (matching Date and ASIN)
--
-- Project: onyga-482313
-- Dataset: OI
-- =============================================

CREATE OR REPLACE PROCEDURE `onyga-482313.OI.SP_LOAD_FACT_INVENTORY_SNAPSHOT`()
BEGIN
  -- Delete existing rows for dates that will be reloaded
  DELETE FROM `onyga-482313.OI.FACT_INVENTORY_SNAPSHOT`
  WHERE Date IN (
    SELECT DISTINCT Date 
    FROM `onyga-482313.OI.V_UNIFIED_INVENTORY_SNAPSHOT`
  );
  
  -- Insert data from V_UNIFIED_INVENTORY_SNAPSHOT with aggregated PO data
  INSERT INTO `onyga-482313.OI.FACT_INVENTORY_SNAPSHOT` (
    Date,
    ASIN,
    quantity_balance,
    source_type,
    COGS_AMOUNT,
    SELL_AMOUNT,
    cost_of_goods,
    shipping_cost,
    factless_key,
    loaded_at
  )
  SELECT 
    inv.Date,
    inv.ASIN,
    inv.quantity_balance,
    inv.source_type,
    
    -- Calculate COGS from DIM_COSTS_HISTORY
    -- COGS_AMOUNT = quantity_balance * TOTAL_COST_PER_UNIT
    inv.quantity_balance * COALESCE(ch.TOTAL_COST_PER_UNIT, 0) AS COGS_AMOUNT,
    
    -- Calculate Selling Price from DIM_PRODUCT
    -- SELL_AMOUNT = quantity_balance * listing_price_amount
    inv.quantity_balance * COALESCE(p.listing_price_amount, 0) AS SELL_AMOUNT,
    
    -- Product cost fields from DIM_COSTS_HISTORY
    ch.cost_of_goods,
    ch.shipping_cost,
    
    -- Factless Key: date_key - asin
    CONCAT(CAST(CAST(FORMAT_DATE('%Y%m%d', inv.Date) AS INT64) AS STRING), '-', COALESCE(inv.ASIN, 'UNKNOWN')) AS factless_key,
    
    CURRENT_TIMESTAMP() AS loaded_at
    
  FROM `onyga-482313.OI.V_UNIFIED_INVENTORY_SNAPSHOT` inv
  LEFT JOIN (
    SELECT asin, listing_price_amount 
    FROM `onyga-482313.OI.DIM_PRODUCT` 
    WHERE marketplace = 'ATVPDKIKX0DER'
  ) p ON p.asin = inv.asin
  LEFT JOIN (
    SELECT asin, cost_of_goods, shipping_cost, TOTAL_COST_PER_UNIT,
      ROW_NUMBER() OVER (PARTITION BY asin ORDER BY end_date DESC) as rn
    FROM `onyga-482313.OI.DIM_COSTS_HISTORY`
  ) ch ON ch.asin = inv.asin AND ch.rn = 1
  
  UNION ALL

  SELECT 
    po.snapshot_date AS Date,
    po.product_asin AS ASIN,
    -- quantity_balance = quantity remaining at manufacturer + quantity remaining at shipment
    COALESCE(po.quantity_remaining_at_manufacturer, 0) + COALESCE(po.quantity_remaining_at_shipment, 0) AS quantity_balance,
    'Manufacturer' AS source_type,
    
    -- Aggregate COGS from purchase orders
    -- COGS_AMOUNT = sum of (cogs_remaining_at_manufacturer + cogs_remaining_at_shipment)
    COALESCE(po.cogs_remaining_at_manufacturer, 0) + 
    COALESCE(po.cogs_remaining_at_shipment, 0) AS COGS_AMOUNT,
    
    -- Aggregate Selling Price from purchase orders
    -- SELL_AMOUNT = sum of (selling_price_remaining_at_manufacturer + selling_price_remaining_at_shipment)
    COALESCE(po.selling_price_remaining_at_manufacturer, 0) + 
    COALESCE(po.selling_price_remaining_at_shipment, 0) AS SELL_AMOUNT,
    
    -- Product dimension fields from FACT_PURCHASE_ORDER
    -- Note: If multiple POs exist for same ASIN/Date, we'll take the first one's cost_of_goods and shipping_cost
    po.cost_of_goods,
    po.shipping_cost,
    
    -- Factless Key: date_key - asin
    CONCAT(CAST(CAST(FORMAT_DATE('%Y%m%d', po.snapshot_date) AS INT64) AS STRING), '-', COALESCE(po.product_asin, 'UNKNOWN')) AS factless_key,
    
    CURRENT_TIMESTAMP() AS loaded_at

  FROM `onyga-482313.OI.FACT_PURCHASE_ORDER` po
  INNER JOIN (
    SELECT DISTINCT Date 
    FROM `onyga-482313.OI.V_UNIFIED_INVENTORY_SNAPSHOT`
  ) i ON po.snapshot_date = i.Date
  WHERE 
    -- Only include POs with remaining quantity (quantity_balance > 0)
    (COALESCE(po.quantity_remaining_at_manufacturer, 0) + COALESCE(po.quantity_remaining_at_shipment, 0)) > 0;
END;
