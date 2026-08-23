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
-- family_label falls back to 'UNMAPPED:<asin>' whenever parent_name is NULL,
-- so two different unmapped ASINs never look like the same product bought
-- twice. That fallback is NOT limited to retired products absent from
-- DIM_PRODUCT — it also catches live, catalogued, currently-selling products
-- that ARE present in DIM_PRODUCT but simply have no family assigned there.
-- Confirmed live: ASIN B0CHJY7XLQ ("Popsicle") and B0CHJZDD3F ("BFF 1") are
-- both active products with is_mapped_product = TRUE and parent_name NULL,
-- so their family_label reads 'UNMAPPED:B0CHJY7XLQ' / 'UNMAPPED:B0CHJZDD3F'
-- despite being fully mapped rows in DIM_PRODUCT.
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

  -- purchase_date, ship_state and is_business_order are 1:1 with the order
  -- (one header row per amazon_order_id in V_SRC_ListOrder), so grouping by
  -- them alongside the order key is safe and lets callers read them here
  -- without a second join back to the header.
  purchase_date,
  ship_state,
  is_business_order,

  COUNT(*)                                  AS line_count,
  COUNT(DISTINCT asin)                      AS distinct_asins,
  COUNT(DISTINCT family_label)              AS distinct_families,
  SUM(quantity_ordered)                     AS units,

  -- item_revenue is the GROSS extended list price (item_price_amount summed):
  -- pre-tax and pre-discount (before promotion_discount_amount). It does not
  -- reconcile to the order total and does not tie to Amazon-reported sales in
  -- SRC_ACC_SALES_TRAFFIC_DAILY. Only units are safe to treat as authoritative.
  ROUND(SUM(item_price_amount), 2)          AS item_revenue,

  -- all_asins_in_dim is TRUE only when every ASIN in the basket has a
  -- DIM_PRODUCT row (is_mapped_product). It does NOT mean every product has a
  -- usable family — DIM_PRODUCT rows can still have parent_name NULL (see
  -- header comment), so distinct_families can count an 'UNMAPPED:' label in a
  -- basket where this column reads TRUE.
  LOGICAL_AND(is_mapped_product)            AS all_asins_in_dim,

  CASE
    WHEN COUNT(DISTINCT asin) > 1     THEN 'MULTI_PRODUCT'
    WHEN SUM(quantity_ordered) > 1    THEN 'MULTI_UNIT_SAME'
    ELSE                                   'SINGLE'
  END                                       AS basket_kind,

  STRING_AGG(DISTINCT product_label ORDER BY product_label) AS basket_label
FROM lines
GROUP BY 1, 2, 3, 4, 5;
