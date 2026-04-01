-- =============================================
-- Purchase Order Snapshot View
-- =============================================
-- 
-- Creates monthly snapshots (end of month + current date) for the last 2 calendar years
-- Shows PO state at each snapshot date with:
--   - All PO fields from DE_PURCHASE_ORDERS
--   - payments_remaining: remaining payment amount as of snapshot date
--   - quantity_remaining_at_manufacturer: remaining quantity not shipped as of snapshot date
--   - quantity_remaining_at_shipment: quantity shipped but not yet arrived (estimated_arrival_date > snapshot_date)
--   - cogs_remaining_at_manufacturer: remaining COGS at manufacturer (quantity_remaining_at_manufacturer * TOTAL_COST_PER_UNIT)
--   - cogs_remaining_at_shipment: remaining COGS in shipment (quantity_remaining_at_shipment * TOTAL_COST_PER_UNIT)
--   - selling_price_remaining_at_manufacturer: remaining selling price at manufacturer
--   - selling_price_remaining_at_shipment: remaining selling price in shipment
--
-- Uses DIM_TIME to generate snapshot dates
-- Uses order_date as start_date (no end_date filter - includes all active POs)
-- =============================================

CREATE OR REPLACE VIEW `onyga-482313.OI.V_PO_SNAPSHOT` AS

WITH snapshot_dates AS (
  -- Generate snapshot dates: month-end dates and current date for last 2 calendar years
  SELECT DISTINCT
    t.full_date AS snapshot_date,
    t.year,
    t.month,
    t.quarter,
    CASE 
      WHEN t.full_date = CURRENT_DATE() THEN TRUE 
      ELSE FALSE 
    END AS is_current_date,
    CASE 
      WHEN t.full_date = LAST_DAY(t.full_date, MONTH) THEN TRUE 
      ELSE FALSE 
    END AS is_month_end
  FROM `onyga-482313.OI.DIM_TIME` t
  WHERE t.full_date >= DATE_SUB(DATE_TRUNC(CURRENT_DATE(), YEAR), INTERVAL 2 YEAR)
    AND t.full_date <= CURRENT_DATE()
    AND (
      -- Include month-end dates
      t.full_date = LAST_DAY(t.full_date, MONTH)
      -- Include current date
      OR t.full_date = CURRENT_DATE()
    )
),

po_with_end_date AS (
  SELECT 
    po.purchase_order_id,
    po.order_date,
    po.manufacturer_name,
    po.product_name,
    po.product_asin,
    po.product_id,
    po.quantity,
    po.unit_price,
    po.total_amount,
    po.currency,
    po.payment_status,
    po.notes,
    po.created_at,
    
    -- Calculate END_DATE: greatest of LAST_PAYMENT_DATE, LAST_SHIPMENT_DATE, and max estimated_arrival_date
    -- (only if both payments and shipments are complete - using current date for calculation)
    CASE
      WHEN (
        -- All payments are paid
        CAST(COALESCE((
          SELECT SUM(p.payment_amount)
          FROM `onyga-482313.OI.DE_VENDOR_PAYMENTS` p
          WHERE p.purchase_order_id = po.purchase_order_id
        ), 0) AS FLOAT64) >= CAST(po.total_amount AS FLOAT64) - 0.01
        -- All shipments are created
        AND COALESCE((
          SELECT SUM(sl.quantity_shipped)
          FROM `onyga-482313.OI.DE_SHIPMENT_LINES` sl
          WHERE sl.purchase_order_id = po.purchase_order_id
        ), 0) >= po.quantity
      )
      THEN GREATEST(
        COALESCE((
          SELECT MAX(p.payment_date)
          FROM `onyga-482313.OI.DE_VENDOR_PAYMENTS` p
          WHERE p.purchase_order_id = po.purchase_order_id
        ), DATE('1900-01-01')),
        COALESCE((
          SELECT MAX(
            CASE 
              WHEN s.is_paid = TRUE AND s.paid_date IS NULL 
              THEN DATE_ADD(s.shipment_date, INTERVAL 30 DAY)
              ELSE s.shipment_date
            END
          )
          FROM `onyga-482313.OI.DE_SHIPMENT_LINES` sl
          INNER JOIN `onyga-482313.OI.DE_MANUFACTURER_SHIPMENTS` s ON sl.shipment_id = s.shipment_id
          WHERE sl.purchase_order_id = po.purchase_order_id
        ), DATE('1900-01-01')),
        COALESCE((
          SELECT MAX(s.estimated_arrival_date)
          FROM `onyga-482313.OI.DE_SHIPMENT_LINES` sl
          INNER JOIN `onyga-482313.OI.DE_MANUFACTURER_SHIPMENTS` s ON sl.shipment_id = s.shipment_id
          WHERE sl.purchase_order_id = po.purchase_order_id
        ), DATE('1900-01-01'))
      )
      ELSE NULL
    END AS end_date
  FROM `onyga-482313.OI.DE_PURCHASE_ORDERS` po
),

po_snapshots AS (
  SELECT 
    sd.snapshot_date,
    sd.year,
    sd.month,
    sd.quarter,
    sd.is_current_date,
    sd.is_month_end,
    
    -- All PO fields
    po.purchase_order_id,
    po.order_date,
    po.manufacturer_name,
    po.product_name,
    po.product_asin,
    po.product_id,
    po.quantity,
    po.unit_price,
    po.total_amount,
    po.currency,
    po.payment_status,
    po.notes,
    po.created_at,
    
    -- Payments remaining as of snapshot date
    -- Calculate: total_amount - sum of payments made up to snapshot_date
    po.total_amount - COALESCE((
      SELECT SUM(p.payment_amount)
      FROM `onyga-482313.OI.DE_VENDOR_PAYMENTS` p
      WHERE p.purchase_order_id = po.purchase_order_id
        AND p.payment_date <= sd.snapshot_date
    ), 0) AS payments_remaining,
    
    -- Quantity remaining at manufacturer: quantity not yet shipped
    -- Calculate: quantity - sum of quantities shipped up to snapshot_date
    po.quantity - COALESCE((
      SELECT SUM(sl.quantity_shipped)
      FROM `onyga-482313.OI.DE_SHIPMENT_LINES` sl
      INNER JOIN `onyga-482313.OI.DE_MANUFACTURER_SHIPMENTS` s ON sl.shipment_id = s.shipment_id
      WHERE sl.purchase_order_id = po.purchase_order_id
        AND s.shipment_date <= sd.snapshot_date
    ), 0) AS quantity_remaining_at_manufacturer,
    
    -- Quantity remaining at shipment: quantity shipped but not yet arrived
    -- Calculate: sum of quantities shipped where estimated_arrival_date > snapshot_date
    COALESCE((
      SELECT SUM(sl.quantity_shipped)
      FROM `onyga-482313.OI.DE_SHIPMENT_LINES` sl
      INNER JOIN `onyga-482313.OI.DE_MANUFACTURER_SHIPMENTS` s ON sl.shipment_id = s.shipment_id
      WHERE sl.purchase_order_id = po.purchase_order_id
        AND s.shipment_date <= sd.snapshot_date
        AND (s.estimated_arrival_date IS NULL OR s.estimated_arrival_date > sd.snapshot_date)
    ), 0) AS quantity_remaining_at_shipment,
    
    -- Product dimension fields for selling price and costs
    pd.listing_price_amount,
    ch.TOTAL_COST_PER_UNIT
    
  FROM snapshot_dates sd
  CROSS JOIN po_with_end_date po
  LEFT JOIN `onyga-482313.OI.DIM_PRODUCT` pd ON (
    po.product_id = pd.product_id
    OR (po.product_id IS NULL AND po.product_asin = pd.asin)
  )
  LEFT JOIN (
    SELECT asin, TOTAL_COST_PER_UNIT,
      ROW_NUMBER() OVER (PARTITION BY asin ORDER BY end_date DESC) as rn
    FROM `onyga-482313.OI.DIM_COSTS_HISTORY`
  ) ch ON pd.asin = ch.asin AND ch.rn = 1
  WHERE 
    -- Only include POs where snapshot_date is on or after order_date and before end_date (if end_date exists)
    sd.snapshot_date >= po.order_date 
    AND (po.end_date IS NULL OR sd.snapshot_date < po.end_date)
)

SELECT 
  snapshot_date,
  year,
  month,
  quarter,
  is_current_date,
  is_month_end,
  
  -- All PO fields
  purchase_order_id,
  order_date,
  manufacturer_name,
  product_name,
  product_asin,
  product_id,
  quantity,
  unit_price,
  total_amount,
  currency,
  payment_status,
  notes,
  created_at,
  
  -- Calculated fields
  payments_remaining,
  quantity_remaining_at_manufacturer,
  quantity_remaining_at_shipment,
  
  -- COGS and Selling Price Remaining at Manufacturer
  quantity_remaining_at_manufacturer * COALESCE(TOTAL_COST_PER_UNIT, 0) AS cogs_remaining_at_manufacturer,
  quantity_remaining_at_manufacturer * COALESCE(listing_price_amount, 0) AS selling_price_remaining_at_manufacturer,
  
  -- COGS and Selling Price Remaining at Shipment
  quantity_remaining_at_shipment * COALESCE(TOTAL_COST_PER_UNIT, 0) AS cogs_remaining_at_shipment,
  quantity_remaining_at_shipment * COALESCE(listing_price_amount, 0) AS selling_price_remaining_at_shipment,
  
  -- Additional calculated fields for convenience
  CASE 
    WHEN payments_remaining <= 0 THEN TRUE 
    ELSE FALSE 
  END AS is_fully_paid_as_of_snapshot,
  
  CASE 
    WHEN quantity_remaining_at_manufacturer <= 0 THEN TRUE 
    ELSE FALSE 
  END AS is_fully_shipped_as_of_snapshot,
  
  CASE 
    WHEN payments_remaining <= 0 AND quantity_remaining_at_manufacturer <= 0 THEN TRUE 
    ELSE FALSE 
  END AS is_complete_as_of_snapshot,
  
  -- Product dimension fields
  TOTAL_COST_PER_UNIT
  
FROM po_snapshots
ORDER BY 
  snapshot_date DESC,
  purchase_order_id;
