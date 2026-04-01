-- =============================================
-- Snapshot View: Remaining Costs & Quantities
-- =============================================
-- 
-- Creates monthly snapshots (end of month + current date) for the last 2 calendar years
-- Shows remaining costs and quantities for:
--   - Manufacture (remaining_manufactured)
--   - Shipment (remaining_shipments)
--   - Shipment Estimations (remaining_shipments_estimated)
-- Includes all shipment details for start date calculation
--
-- Uses DIM_TIME to generate snapshot dates
-- =============================================

CREATE OR REPLACE VIEW `onyga-482313.OI.V_SNAPSHOT_REMAINING_COSTS` AS

WITH snapshot_dates AS (
  -- Generate snapshot dates: month-end dates and current date for last 2 calendar years
  SELECT DISTINCT
    t.full_date AS snapshot_date,
    t.year,
    t.month,
    t.month_end_date,
    t.month_key,
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

purchase_orders AS (
  SELECT 
    po.purchase_order_id,
    po.order_date,
    po.manufacturer_name,
    po.product_name,
    po.product_asin,
    po.quantity,
    po.unit_price,
    po.total_amount,
    po.currency,
    po.payment_status
  FROM `onyga-482313.OI.DE_PURCHASE_ORDERS` po
),

shipments AS (
  SELECT 
    s.shipment_id,
    sl.purchase_order_id,
    s.shipment_date,
    s.estimated_arrival_date,
    s.shipment_type,
    sl.quantity_shipped,
    s.cost_shipped,
    CASE
      WHEN sl.quantity_shipped > 0 THEN sl.allocated_cost / sl.quantity_shipped
      ELSE NULL
    END AS unit_cost,
    sl.allocated_cost,
    s.is_paid,
    s.paid_date,
    s.shipment_status,
    s.tracking_number,
    s.kg_price,
    s.notes,
    -- Calculate expected arrival date if not set
    COALESCE(
      s.estimated_arrival_date,
      CASE 
        WHEN s.shipment_date IS NOT NULL AND s.shipment_type = 'SLOW_SEA' 
          THEN DATE_ADD(s.shipment_date, INTERVAL 33 DAY)
        WHEN s.shipment_date IS NOT NULL AND s.shipment_type = 'FAST_SEA' 
          THEN DATE_ADD(s.shipment_date, INTERVAL 27 DAY)
        WHEN s.shipment_date IS NOT NULL AND s.shipment_type = 'AIR' 
          THEN DATE_ADD(s.shipment_date, INTERVAL 10 DAY)
        ELSE NULL
      END
    ) AS calculated_estimated_arrival_date
  FROM `onyga-482313.OI.DE_SHIPMENT_LINES` sl
  INNER JOIN `onyga-482313.OI.DE_MANUFACTURER_SHIPMENTS` s ON sl.shipment_id = s.shipment_id
),

snapshot_calculations AS (
  SELECT 
    sd.snapshot_date,
    sd.year,
    sd.month,
    sd.month_key,
    sd.is_current_date,
    sd.is_month_end,
    
    po.purchase_order_id,
    po.order_date,
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
        AND p2.payment_date <= sd.snapshot_date
    ), 0) AS total_paid_as_of_snapshot,
    
    po.total_amount - COALESCE((
      SELECT SUM(p2.payment_amount)
      FROM `onyga-482313.OI.DE_VENDOR_PAYMENTS` p2
      WHERE p2.purchase_order_id = po.purchase_order_id
        AND p2.payment_date <= sd.snapshot_date
    ), 0) AS amount_remaining_as_of_snapshot,
    
    -- Shipment quantities and costs as of snapshot date
    COALESCE((
      SELECT SUM(s2.quantity_shipped)
      FROM shipments s2
      WHERE s2.purchase_order_id = po.purchase_order_id
        AND s2.shipment_date <= sd.snapshot_date
    ), 0) AS total_quantity_shipped_as_of_snapshot,
    
    po.quantity - COALESCE((
      SELECT SUM(s2.quantity_shipped)
      FROM shipments s2
      WHERE s2.purchase_order_id = po.purchase_order_id
        AND s2.shipment_date <= sd.snapshot_date
    ), 0) AS remaining_quantity_to_ship_as_of_snapshot,
    
    COALESCE((
      SELECT SUM(s2.allocated_cost)
      FROM shipments s2
      WHERE s2.purchase_order_id = po.purchase_order_id
        AND s2.shipment_date <= sd.snapshot_date
    ), 0) AS total_shipment_cost_as_of_snapshot,
    
    COALESCE((
      SELECT SUM(CASE WHEN s2.is_paid AND s2.paid_date <= sd.snapshot_date THEN s2.allocated_cost ELSE 0 END)
      FROM shipments s2
      WHERE s2.purchase_order_id = po.purchase_order_id
    ), 0) AS total_shipment_paid_as_of_snapshot,
    
    COALESCE((
      SELECT SUM(s2.allocated_cost)
      FROM shipments s2
      WHERE s2.purchase_order_id = po.purchase_order_id
        AND s2.shipment_date <= sd.snapshot_date
    ), 0) - COALESCE((
      SELECT SUM(CASE WHEN s2.is_paid AND s2.paid_date <= sd.snapshot_date THEN s2.allocated_cost ELSE 0 END)
      FROM shipments s2
      WHERE s2.purchase_order_id = po.purchase_order_id
    ), 0) AS remaining_shipments_cost_as_of_snapshot,
    
    -- Remaining manufactured (for SYLVIA) as of snapshot date
    CASE 
      WHEN po.manufacturer_name = 'SYLVIA' THEN
        po.total_amount - COALESCE((
          SELECT SUM(p2.payment_amount)
          FROM `onyga-482313.OI.DE_VENDOR_PAYMENTS` p2
          WHERE p2.purchase_order_id = po.purchase_order_id
            AND p2.payment_date <= sd.snapshot_date
        ), 0)
      ELSE 0
    END AS remaining_manufactured_as_of_snapshot,
    
    -- Remaining shipments estimated as of snapshot date
    CASE 
      WHEN po.quantity - COALESCE((
        SELECT SUM(s2.quantity_shipped)
        FROM shipments s2
        WHERE s2.purchase_order_id = po.purchase_order_id
          AND s2.shipment_date <= sd.snapshot_date
      ), 0) > 0 THEN
        COALESCE(
          -- Same PO shipments
          (SELECT AVG(unit_cost) 
           FROM shipments s2 
           WHERE s2.purchase_order_id = po.purchase_order_id 
             AND s2.unit_cost IS NOT NULL
             AND s2.shipment_date <= sd.snapshot_date),
          -- Same product shipments
          (SELECT AVG(s3.unit_cost)
           FROM shipments s3
           JOIN purchase_orders po2 ON s3.purchase_order_id = po2.purchase_order_id
           WHERE po2.product_name = po.product_name
             AND s3.unit_cost IS NOT NULL
             AND s3.shipment_date >= DATE_SUB(sd.snapshot_date, INTERVAL 12 MONTH)
             AND s3.shipment_date <= sd.snapshot_date),
          -- Last 12 months average
          (SELECT AVG(unit_cost)
           FROM shipments s4
           WHERE s4.unit_cost IS NOT NULL
             AND s4.shipment_date >= DATE_SUB(sd.snapshot_date, INTERVAL 12 MONTH)
             AND s4.shipment_date <= sd.snapshot_date)
        ) * (po.quantity - COALESCE((
          SELECT SUM(s2.quantity_shipped)
          FROM shipments s2
          WHERE s2.purchase_order_id = po.purchase_order_id
            AND s2.shipment_date <= sd.snapshot_date
        ), 0))
      ELSE 0
    END AS remaining_shipments_estimated_as_of_snapshot
    
  FROM snapshot_dates sd
  CROSS JOIN purchase_orders po
  WHERE po.order_date <= sd.snapshot_date  -- Only include POs created before or on snapshot date
)

SELECT 
  sc.snapshot_date,
  sc.year,
  sc.month,
  sc.month_key,
  sc.is_current_date,
  sc.is_month_end,
  
  -- Purchase Order Info
  sc.purchase_order_id,
  sc.order_date,
  sc.manufacturer_name,
  sc.product_name,
  sc.product_asin,
  sc.quantity,
  sc.unit_price,
  sc.total_amount,
  sc.currency,
  sc.payment_status,
  
  -- Payment Info (as of snapshot)
  sc.total_paid_as_of_snapshot,
  sc.amount_remaining_as_of_snapshot,
  
  -- Shipment Info (as of snapshot)
  sc.total_quantity_shipped_as_of_snapshot,
  sc.remaining_quantity_to_ship_as_of_snapshot,
  sc.total_shipment_cost_as_of_snapshot,
  sc.total_shipment_paid_as_of_snapshot,
  sc.remaining_shipments_cost_as_of_snapshot,
  
  -- Remaining Costs (as of snapshot)
  sc.remaining_manufactured_as_of_snapshot AS remaining_manufactured_cost,
  sc.remaining_shipments_cost_as_of_snapshot AS remaining_shipments_cost,
  sc.remaining_shipments_estimated_as_of_snapshot AS remaining_shipments_estimated_cost,
  
  -- Shipment Details for Start Date Calculation
  s.shipment_id,
  s.shipment_date,
  s.estimated_arrival_date,
  s.calculated_estimated_arrival_date,
  s.shipment_type,
  s.quantity_shipped,
  s.allocated_cost,
  s.unit_cost,
  s.is_paid,
  s.paid_date,
  s.shipment_status,
  s.tracking_number,
  s.kg_price,
  s.notes AS shipment_notes,
  
  -- Use shipment_date as start_date for calculations
  s.shipment_date AS start_date,
  
  -- Days until estimated arrival (for current/future shipments)
  CASE 
    WHEN s.estimated_arrival_date IS NOT NULL AND s.estimated_arrival_date >= sc.snapshot_date
      THEN DATE_DIFF(s.estimated_arrival_date, sc.snapshot_date, DAY)
    WHEN s.calculated_estimated_arrival_date IS NOT NULL AND s.calculated_estimated_arrival_date >= sc.snapshot_date
      THEN DATE_DIFF(s.calculated_estimated_arrival_date, sc.snapshot_date, DAY)
    ELSE NULL
  END AS days_until_arrival

FROM snapshot_calculations sc
LEFT JOIN shipments s ON sc.purchase_order_id = s.purchase_order_id
  AND s.shipment_date <= sc.snapshot_date  -- Only include shipments that occurred on or before snapshot date
ORDER BY 
  sc.snapshot_date DESC,
  sc.purchase_order_id,
  s.shipment_date DESC;
