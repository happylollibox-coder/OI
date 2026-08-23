-- =============================================
-- OI Database Project - V_ORDER_BASKET
-- =============================================
--
-- Purpose: One row per customer order describing the SHAPE of the basket —
--          how many distinct products, how many units, and a readable label.
--          This is the human-facing surface; V_ORDER_CROSS_SELL is the
--          machine-facing pair table built from the same lines.
--
-- Source: FACT_CUSTOMER_ORDER_ITEM
-- Grain:  One row per (selling_partner_id, amazon_order_id)
--
-- Both exclusions matter and neither is optional:
--   NOT is_canceled       drops orders Amazon canceled outright
--   quantity_ordered > 0  drops canceled LINES on orders that still shipped
-- An order whose every line is canceled disappears entirely, which is correct —
-- it has no basket.
--
-- basket_kind separates the two different questions people ask:
--   SINGLE          one product, one unit
--   MULTI_UNIT_SAME one product, several units  (a "buy two" signal)
--   MULTI_PRODUCT   more than one product       (a cross-sell signal)
--
-- Unmapped ASINs (retired products absent from DIM_PRODUCT) keep their identity
-- as 'UNMAPPED:<asin>' rather than collapsing into one bucket, so two different
-- retired products never look like the same product bought twice.
--
-- Spec: architecture/CUSTOMER_ORDER_BASKETS.md
--
-- =============================================

CREATE OR REPLACE VIEW `onyga-482313.OI.V_ORDER_BASKET` AS

WITH lines AS (
  SELECT
    selling_partner_id,
    amazon_order_id,
    purchase_date,
    ship_state,
    is_business_order,
    asin,
    COALESCE(parent_name, CONCAT('UNMAPPED:', asin))        AS family_label,
    COALESCE(product_short_name, item_title, asin)          AS product_label,
    is_mapped_product,
    quantity_ordered,
    item_price_amount
  FROM `onyga-482313.OI.FACT_CUSTOMER_ORDER_ITEM`
  WHERE NOT is_canceled
    AND quantity_ordered > 0
)

SELECT
  selling_partner_id,
  amazon_order_id,
  purchase_date,
  ship_state,
  is_business_order,

  COUNT(*)                                  AS line_count,
  COUNT(DISTINCT asin)                      AS distinct_asins,
  COUNT(DISTINCT family_label)              AS distinct_families,
  SUM(quantity_ordered)                     AS units,
  ROUND(SUM(item_price_amount), 2)          AS item_revenue,
  LOGICAL_AND(is_mapped_product)            AS all_products_mapped,

  CASE
    WHEN COUNT(DISTINCT asin) > 1     THEN 'MULTI_PRODUCT'
    WHEN SUM(quantity_ordered) > 1    THEN 'MULTI_UNIT_SAME'
    ELSE                                   'SINGLE'
  END                                       AS basket_kind,

  STRING_AGG(DISTINCT product_label ORDER BY product_label) AS basket_label
FROM lines
GROUP BY 1, 2, 3, 4, 5;
