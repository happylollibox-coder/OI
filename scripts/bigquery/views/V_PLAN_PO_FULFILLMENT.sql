-- V_PLAN_PO_FULFILLMENT
-- Aggregates Purchase Order quantities by ASIN for plan year tracking.
-- Matched via product_asin for reliable joins (product names differ between POs and DIM_PRODUCT).

CREATE OR REPLACE VIEW `onyga-482313.OI.V_PLAN_PO_FULFILLMENT` AS
SELECT
  po.product_asin AS asin,
  dp.product_short_name AS product_name,
  EXTRACT(YEAR FROM po.order_date) AS order_year,
  SUM(po.quantity) AS total_ordered,
  COUNT(*) AS po_count,
  MIN(po.order_date) AS first_po_date,
  MAX(po.order_date) AS last_po_date
FROM `onyga-482313.OI.DE_PURCHASE_ORDERS` po
LEFT JOIN `onyga-482313.OI.DIM_PRODUCT` dp
  ON po.product_asin = dp.asin
WHERE po.product_asin IS NOT NULL
  AND po.product_asin != ''
GROUP BY po.product_asin, dp.product_short_name, EXTRACT(YEAR FROM po.order_date);
