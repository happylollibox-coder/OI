-- =============================================
-- V_SUPPLY_ORDERS_DASHBOARD
-- Enriched Purchase Orders with payment & shipment status
-- Mirrors data-entry-app get_purchase_orders_with_status() logic
-- Aggregates multi-product POs into a single row per PO
-- =============================================

CREATE OR REPLACE VIEW `onyga-482313.OI.V_SUPPLY_ORDERS_DASHBOARD` AS

WITH po_aggregated AS (
  -- Collapse multi-product POs into one row per purchase_order_id
  SELECT
    po.purchase_order_id,
    MIN(po.order_date) AS order_date,
    ANY_VALUE(po.manufacturer_name) AS manufacturer_name,
    STRING_AGG(DISTINCT CAST(po.product_id AS STRING), ', ') AS product_id,
    STRING_AGG(DISTINCT po.product_asin, ', ') AS product_asin,
    STRING_AGG(DISTINCT po.product_name, ', ') AS product_name,
    SUM(po.quantity) AS quantity,
    SUM(COALESCE(po.ready_quantity, 0)) AS ready_quantity,
    SUM(po.total_amount) AS total_amount,
    ANY_VALUE(po.currency) AS currency,
    STRING_AGG(DISTINCT po.notes, ' | ') AS notes,
    MIN(po.created_at) AS created_at,
    DATE_ADD(MIN(po.order_date), INTERVAL CAST(COALESCE(MAX(dim.manufacture_day), 30) AS INT64) DAY) AS expected_ready_date,
    MAX(po.estimated_arrival_date) AS estimated_arrival_date
  FROM `onyga-482313.OI.DE_PURCHASE_ORDERS` po
  LEFT JOIN `onyga-482313.OI.DIM_PRODUCT` dim ON po.product_id = dim.product_id
  GROUP BY po.purchase_order_id
),

payment_totals AS (
  SELECT
    purchase_order_id,
    SUM(payment_amount) AS total_paid
  FROM `onyga-482313.OI.DE_VENDOR_PAYMENTS`
  GROUP BY purchase_order_id
),

shipment_totals AS (
  SELECT
    sl.purchase_order_id,
    SUM(COALESCE(sl.allocated_cost, 0)) AS total_shipment_cost,
    SUM(CASE WHEN s.is_paid = TRUE THEN COALESCE(sl.allocated_cost, 0) ELSE 0 END) AS paid_shipment_cost
  FROM `onyga-482313.OI.DE_SHIPMENT_LINES` sl
  INNER JOIN `onyga-482313.OI.DE_MANUFACTURER_SHIPMENTS` s ON sl.shipment_id = s.shipment_id
  GROUP BY sl.purchase_order_id
),

shipment_quantities AS (
  SELECT
    sl.purchase_order_id,
    SUM(COALESCE(sl.quantity_shipped, 0)) AS total_quantity_shipped
  FROM `onyga-482313.OI.DE_SHIPMENT_LINES` sl
  GROUP BY sl.purchase_order_id
),

-- Quantity shipped without allocated_cost (for estimation)
shipment_qty_without_cost AS (
  SELECT
    sl.purchase_order_id,
    SUM(COALESCE(sl.quantity_shipped, 0)) AS quantity_without_cost
  FROM `onyga-482313.OI.DE_SHIPMENT_LINES` sl
  WHERE sl.quantity_shipped > 0
    AND (sl.allocated_cost IS NULL OR sl.allocated_cost = 0)
  GROUP BY sl.purchase_order_id
),

-- Weighted avg unit cost from shipments in the same PO
po_shipment_unit_cost AS (
  SELECT
    sl.purchase_order_id,
    CASE
      WHEN SUM(COALESCE(sl.quantity_shipped, 0)) > 0
      THEN SUM(COALESCE(sl.allocated_cost, 0)) / SUM(COALESCE(sl.quantity_shipped, 0))
      ELSE NULL
    END AS avg_unit_cost
  FROM `onyga-482313.OI.DE_SHIPMENT_LINES` sl
  WHERE sl.allocated_cost IS NOT NULL AND sl.allocated_cost > 0
    AND sl.quantity_shipped IS NOT NULL AND sl.quantity_shipped > 0
  GROUP BY sl.purchase_order_id
),

-- Fallback: avg unit cost from shipments in last 12 months
last_12m_unit_cost AS (
  SELECT
    CASE
      WHEN SUM(COALESCE(sl.quantity_shipped, 0)) > 0
      THEN SUM(COALESCE(sl.allocated_cost, 0)) / SUM(COALESCE(sl.quantity_shipped, 0))
      ELSE NULL
    END AS avg_unit_cost
  FROM `onyga-482313.OI.DE_SHIPMENT_LINES` sl
  INNER JOIN `onyga-482313.OI.DE_MANUFACTURER_SHIPMENTS` s ON sl.shipment_id = s.shipment_id
  INNER JOIN `onyga-482313.OI.DE_PURCHASE_ORDERS` po ON sl.purchase_order_id = po.purchase_order_id
  WHERE sl.allocated_cost IS NOT NULL AND sl.allocated_cost > 0
    AND sl.quantity_shipped IS NOT NULL AND sl.quantity_shipped > 0
    AND COALESCE(s.shipment_date, po.order_date) >= DATE_SUB(CURRENT_DATE(), INTERVAL 12 MONTH)
)

SELECT
  po.purchase_order_id,
  po.order_date,
  po.manufacturer_name,
  po.product_id,
  po.product_asin,
  po.product_name,
  po.quantity,
  po.ready_quantity,
  po.expected_ready_date,
  po.estimated_arrival_date,
  CAST(NULL AS FLOAT64) AS unit_price,  -- Not meaningful for aggregated multi-product POs
  po.total_amount,
  po.currency,
  po.notes,

  -- Payment aggregates
  COALESCE(pt.total_paid, 0) AS total_paid,
  (po.total_amount - COALESCE(pt.total_paid, 0)) AS unpaid_manufacturer,

  -- Shipment aggregates
  COALESCE(st.total_shipment_cost, 0) AS total_shipment_cost,
  COALESCE(st.paid_shipment_cost, 0) AS paid_shipment_cost,
  (COALESCE(st.total_shipment_cost, 0) - COALESCE(st.paid_shipment_cost, 0)) AS unpaid_shipment,

  -- Combined unpaid
  ((po.total_amount - COALESCE(pt.total_paid, 0))
   + (COALESCE(st.total_shipment_cost, 0) - COALESCE(st.paid_shipment_cost, 0))) AS total_unpaid,

  -- Shipping progress
  COALESCE(sq.total_quantity_shipped, 0) AS total_quantity_shipped,
  (po.quantity - COALESCE(sq.total_quantity_shipped, 0)) AS remaining_to_ship,

  -- Estimated shipment cost for lines without allocated_cost
  CASE
    WHEN COALESCE(sqc.quantity_without_cost, 0) > 0 THEN
      COALESCE(sqc.quantity_without_cost, 0) *
      COALESCE(poc.avg_unit_cost, lm.avg_unit_cost, NULL)
    ELSE NULL
  END AS estimated_shipment_cost,

  -- Payment status
  CASE
    WHEN ABS(COALESCE(pt.total_paid, 0) - po.total_amount) < 0.01
      AND (COALESCE(st.total_shipment_cost, 0) = 0 OR ABS(COALESCE(st.paid_shipment_cost, 0) - COALESCE(st.total_shipment_cost, 0)) < 0.01)
      AND (po.quantity - COALESCE(sq.total_quantity_shipped, 0) <= 0)
    THEN 'Fully Paid'
    WHEN ABS(COALESCE(pt.total_paid, 0) - po.total_amount) < 0.01
      AND (COALESCE(st.total_shipment_cost, 0) = 0 OR ABS(COALESCE(st.paid_shipment_cost, 0) - COALESCE(st.total_shipment_cost, 0)) < 0.01)
    THEN 'PO Paid, Shipment Paid'
    WHEN ABS(COALESCE(pt.total_paid, 0) - po.total_amount) < 0.01
    THEN CONCAT('PO Paid',
                CASE
                  WHEN COALESCE(st.total_shipment_cost, 0) > 0 AND ABS(COALESCE(st.paid_shipment_cost, 0) - COALESCE(st.total_shipment_cost, 0)) >= 0.01
                  THEN ', Pending Shipment Payment'
                  WHEN COALESCE(st.total_shipment_cost, 0) > 0 AND ABS(COALESCE(st.paid_shipment_cost, 0) - COALESCE(st.total_shipment_cost, 0)) < 0.01
                  THEN ', Shipment Paid'
                  ELSE ''
                END)
    ELSE CONCAT('Pending PO Payment',
                CASE
                  WHEN COALESCE(st.total_shipment_cost, 0) > 0 AND ABS(COALESCE(st.paid_shipment_cost, 0) - COALESCE(st.total_shipment_cost, 0)) >= 0.01
                  THEN ', Pending Shipment Payment'
                  WHEN COALESCE(st.total_shipment_cost, 0) > 0 AND ABS(COALESCE(st.paid_shipment_cost, 0) - COALESCE(st.total_shipment_cost, 0)) < 0.01
                  THEN ', Shipment Paid'
                  ELSE ''
                END)
  END AS payment_status,

  -- Is this PO "open" (outstanding PO amount OR remaining quantity to ship)?
  (ABS(COALESCE(pt.total_paid, 0) - po.total_amount) >= 0.01 OR (po.quantity - COALESCE(sq.total_quantity_shipped, 0)) > 0) AS is_open,

  po.created_at

FROM po_aggregated po
LEFT JOIN payment_totals pt ON po.purchase_order_id = pt.purchase_order_id
LEFT JOIN shipment_totals st ON po.purchase_order_id = st.purchase_order_id
LEFT JOIN shipment_quantities sq ON po.purchase_order_id = sq.purchase_order_id
LEFT JOIN shipment_qty_without_cost sqc ON po.purchase_order_id = sqc.purchase_order_id
LEFT JOIN po_shipment_unit_cost poc ON po.purchase_order_id = poc.purchase_order_id
LEFT JOIN last_12m_unit_cost lm ON TRUE;
