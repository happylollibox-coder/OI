-- =============================================
-- Purchase Order Snapshot Table
-- =============================================
-- 
-- Creates a snapshot table tracking PO state from start_date (order_date) 
-- to end_date (when all shipments are paid AND PO payments are paid)
--
-- Uses TimeDIM to generate snapshot dates
-- =============================================

CREATE OR REPLACE TABLE `onyga-482313.OI.STG_PO_SNAPSHOT` AS

WITH purchase_orders AS (
  SELECT 
    po.purchase_order_id,
    po.order_date AS start_date,
    po.manufacturer_name,
    po.product_name,
    po.product_asin,
    po.quantity,
    po.unit_price,
    po.total_amount,
    po.currency,
    po.payment_status,
    po.created_at,
    po.updated_at
  FROM `onyga-482313.OI.DE_PURCHASE_ORDERS` po
),

po_payments AS (
  SELECT 
    p.purchase_order_id,
    SUM(p.payment_amount) AS total_paid
  FROM `onyga-482313.OI.DE_VENDOR_PAYMENTS` p
  GROUP BY p.purchase_order_id
),

shipment_payments AS (
  SELECT 
    s.purchase_order_id,
    SUM(CASE WHEN s.is_paid THEN s.cost_shipped ELSE 0 END) AS total_shipment_paid,
    SUM(s.cost_shipped) AS total_shipment_cost,
    MAX(CASE WHEN s.is_paid AND s.paid_date IS NOT NULL THEN s.paid_date ELSE NULL END) AS last_shipment_paid_date
  FROM `onyga-482313.OI.DE_MANUFACTURER_SHIPMENTS` s
  GROUP BY s.purchase_order_id
),

po_end_dates AS (
  SELECT 
    po.purchase_order_id,
    po.start_date,
    po.total_amount,
    COALESCE(pp.total_paid, 0) AS total_paid,
    COALESCE(sp.total_shipment_cost, 0) AS total_shipment_cost,
    COALESCE(sp.total_shipment_paid, 0) AS total_shipment_paid,
    
    -- Calculate end_date: when both PO is fully paid AND all shipments are paid
    CASE 
      -- If PO is fully paid and all shipments are paid
      WHEN COALESCE(pp.total_paid, 0) >= po.total_amount 
        AND COALESCE(sp.total_shipment_paid, 0) >= COALESCE(sp.total_shipment_cost, 0)
        AND COALESCE(sp.total_shipment_cost, 0) > 0
        THEN COALESCE(sp.last_shipment_paid_date, 
                     (SELECT MAX(payment_date) 
                      FROM `onyga-482313.OI.DE_VENDOR_PAYMENTS` p2 
                      WHERE p2.purchase_order_id = po.purchase_order_id))
      -- If PO is fully paid but no shipments yet
      WHEN COALESCE(pp.total_paid, 0) >= po.total_amount 
        AND COALESCE(sp.total_shipment_cost, 0) = 0
        THEN (SELECT MAX(payment_date) 
              FROM `onyga-482313.OI.DE_VENDOR_PAYMENTS` p2 
              WHERE p2.purchase_order_id = po.purchase_order_id)
      -- If no payments and no shipments, end_date is NULL (still active)
      WHEN COALESCE(pp.total_paid, 0) = 0 
        AND COALESCE(sp.total_shipment_cost, 0) = 0
        THEN NULL
      -- Otherwise, still active (not fully paid)
      ELSE NULL
    END AS end_date
    
  FROM purchase_orders po
  LEFT JOIN po_payments pp ON po.purchase_order_id = pp.purchase_order_id
  LEFT JOIN shipment_payments sp ON po.purchase_order_id = sp.purchase_order_id
),

po_snapshots AS (
  SELECT 
    t.full_date AS snapshot_date,
    t.year,
    t.month,
    t.month_key,
    t.quarter,
    t.quarter_key,
    po.purchase_order_id,
    po.start_date,
    po.end_date,
    po.manufacturer_name,
    po.product_name,
    po.product_asin,
    po.quantity,
    po.unit_price,
    po.total_amount,
    po.currency,
    po.payment_status,
    
    -- Calculate remaining amounts as of snapshot date
    COALESCE((
      SELECT SUM(p2.payment_amount)
      FROM `onyga-482313.OI.DE_VENDOR_PAYMENTS` p2
      WHERE p2.purchase_order_id = po.purchase_order_id
        AND p2.payment_date <= t.full_date
    ), 0) AS total_paid_as_of_snapshot,
    
    po.total_amount - COALESCE((
      SELECT SUM(p2.payment_amount)
      FROM `onyga-482313.OI.DE_VENDOR_PAYMENTS` p2
      WHERE p2.purchase_order_id = po.purchase_order_id
        AND p2.payment_date <= t.full_date
    ), 0) AS amount_remaining_as_of_snapshot,
    
    -- Shipment quantities and costs as of snapshot date
    COALESCE((
      SELECT SUM(s2.quantity_shipped)
      FROM `onyga-482313.OI.DE_MANUFACTURER_SHIPMENTS` s2
      WHERE s2.purchase_order_id = po.purchase_order_id
        AND s2.shipment_date <= t.full_date
    ), 0) AS total_quantity_shipped_as_of_snapshot,
    
    po.quantity - COALESCE((
      SELECT SUM(s2.quantity_shipped)
      FROM `onyga-482313.OI.DE_MANUFACTURER_SHIPMENTS` s2
      WHERE s2.purchase_order_id = po.purchase_order_id
        AND s2.shipment_date <= t.full_date
    ), 0) AS remaining_quantity_to_ship_as_of_snapshot,
    
    COALESCE((
      SELECT SUM(s2.cost_shipped)
      FROM `onyga-482313.OI.DE_MANUFACTURER_SHIPMENTS` s2
      WHERE s2.purchase_order_id = po.purchase_order_id
        AND s2.shipment_date <= t.full_date
    ), 0) AS total_shipment_cost_as_of_snapshot,
    
    COALESCE((
      SELECT SUM(CASE WHEN s2.is_paid AND s2.paid_date <= t.full_date THEN s2.cost_shipped ELSE 0 END)
      FROM `onyga-482313.OI.DE_MANUFACTURER_SHIPMENTS` s2
      WHERE s2.purchase_order_id = po.purchase_order_id
    ), 0) AS total_shipment_paid_as_of_snapshot,
    
    COALESCE((
      SELECT SUM(s2.cost_shipped)
      FROM `onyga-482313.OI.DE_MANUFACTURER_SHIPMENTS` s2
      WHERE s2.purchase_order_id = po.purchase_order_id
        AND s2.shipment_date <= t.full_date
    ), 0) - COALESCE((
      SELECT SUM(CASE WHEN s2.is_paid AND s2.paid_date <= t.full_date THEN s2.cost_shipped ELSE 0 END)
      FROM `onyga-482313.OI.DE_MANUFACTURER_SHIPMENTS` s2
      WHERE s2.purchase_order_id = po.purchase_order_id
    ), 0) AS remaining_shipments_cost_as_of_snapshot,
    
    -- Remaining manufactured (for SYLVIA) as of snapshot date
    CASE 
      WHEN po.manufacturer_name = 'SYLVIA' THEN
        po.total_amount - COALESCE((
          SELECT SUM(p2.payment_amount)
          FROM `onyga-482313.OI.DE_VENDOR_PAYMENTS` p2
          WHERE p2.purchase_order_id = po.purchase_order_id
            AND p2.payment_date <= t.full_date
        ), 0)
      ELSE 0
    END AS remaining_manufactured_as_of_snapshot,
    
    -- Remaining shipments estimated as of snapshot date
    CASE 
      WHEN po.quantity - COALESCE((
        SELECT SUM(s2.quantity_shipped)
        FROM `onyga-482313.OI.DE_MANUFACTURER_SHIPMENTS` s2
        WHERE s2.purchase_order_id = po.purchase_order_id
          AND s2.shipment_date <= t.full_date
      ), 0) > 0 THEN
        COALESCE(
          -- Same PO shipments
          (SELECT AVG(unit_cost) 
           FROM `onyga-482313.OI.DE_MANUFACTURER_SHIPMENTS` s2 
           WHERE s2.purchase_order_id = po.purchase_order_id 
             AND s2.unit_cost IS NOT NULL
             AND s2.shipment_date <= t.full_date),
          -- Same product shipments
          (SELECT AVG(s3.unit_cost)
           FROM `onyga-482313.OI.DE_MANUFACTURER_SHIPMENTS` s3
           JOIN purchase_orders po2 ON s3.purchase_order_id = po2.purchase_order_id
           WHERE po2.product_name = po.product_name
             AND s3.unit_cost IS NOT NULL
             AND s3.shipment_date >= DATE_SUB(t.full_date, INTERVAL 12 MONTH)
             AND s3.shipment_date <= t.full_date),
          -- Last 12 months average
          (SELECT AVG(unit_cost)
           FROM `onyga-482313.OI.DE_MANUFACTURER_SHIPMENTS` s4
           WHERE s4.unit_cost IS NOT NULL
             AND s4.shipment_date >= DATE_SUB(t.full_date, INTERVAL 12 MONTH)
             AND s4.shipment_date <= t.full_date)
        ) * (po.quantity - COALESCE((
          SELECT SUM(s2.quantity_shipped)
          FROM `onyga-482313.OI.DE_MANUFACTURER_SHIPMENTS` s2
          WHERE s2.purchase_order_id = po.purchase_order_id
            AND s2.shipment_date <= t.full_date
        ), 0))
      ELSE 0
    END AS remaining_shipments_estimated_as_of_snapshot,
    
    -- Status flags
    CASE 
      WHEN po.end_date IS NOT NULL AND t.full_date >= po.end_date THEN TRUE
      ELSE FALSE
    END AS is_completed,
    
    CASE 
      WHEN po.end_date IS NULL OR t.full_date < po.end_date THEN TRUE
      ELSE FALSE
    END AS is_active
    
  FROM `onyga-482313.OI.TimeDIM` t
  CROSS JOIN po_end_dates po
  WHERE t.full_date >= po.start_date  -- Start from PO date
    AND (po.end_date IS NULL OR t.full_date <= po.end_date)  -- End when PO is completed
    AND (
      -- Include month-end dates
      t.full_date = LAST_DAY(t.full_date, MONTH)
      -- Include current date
      OR t.full_date = CURRENT_DATE()
      -- Include start_date and end_date
      OR t.full_date = po.start_date
      OR (po.end_date IS NOT NULL AND t.full_date = po.end_date)
    )
)

SELECT 
  snapshot_date,
  year,
  month,
  month_key,
  quarter,
  quarter_key,
  purchase_order_id,
  start_date,
  end_date,
  manufacturer_name,
  product_name,
  product_asin,
  quantity,
  unit_price,
  total_amount,
  currency,
  payment_status,
  
  -- Payment Info (as of snapshot)
  total_paid_as_of_snapshot,
  amount_remaining_as_of_snapshot,
  
  -- Shipment Info (as of snapshot)
  total_quantity_shipped_as_of_snapshot,
  remaining_quantity_to_ship_as_of_snapshot,
  total_shipment_cost_as_of_snapshot,
  total_shipment_paid_as_of_snapshot,
  remaining_shipments_cost_as_of_snapshot,
  
  -- Remaining Costs (as of snapshot)
  remaining_manufactured_as_of_snapshot AS remaining_manufactured_cost,
  remaining_shipments_cost_as_of_snapshot AS remaining_shipments_cost,
  remaining_shipments_estimated_as_of_snapshot AS remaining_shipments_estimated_cost,
  
  -- Status
  is_completed,
  is_active,
  
  -- Metadata
  CURRENT_TIMESTAMP() AS snapshot_created_at

FROM po_snapshots
ORDER BY 
  purchase_order_id,
  snapshot_date;
