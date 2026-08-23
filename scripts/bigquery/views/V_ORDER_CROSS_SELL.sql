-- =============================================
-- OI Database Project - V_ORDER_CROSS_SELL
-- =============================================
--
-- Purpose: MEASURED same-basket co-purchase. One row per unordered ASIN pair
--          per lookback window, with how often the two appeared in one order
--          and how much more often than chance would predict.
--
-- Source: FACT_CUSTOMER_ORDER_ITEM
-- Grain:  One row per (window_days, asin_a, asin_b) where asin_a < asin_b
--
-- HOW THIS DIFFERS FROM V_ADS_COACH_CROSSSELL — they are not competitors and
-- neither replaces the other:
--   V_ADS_COACH_CROSSSELL reads V_SRC_AmazonAds_purchased_product: "someone
--     clicked an ad for A and later bought B" — ad-attributed, possibly across
--     separate orders, and blind to anything ads never touched.
--   V_ORDER_CROSS_SELL reads actual orders: "A and B were in the SAME basket" —
--     no attribution model, no ad dependency, but no click intent either.
--   Ads-attributed cross-sell answers "what should A's ads target?".
--   Basket cross-sell answers "what do buyers actually put together?".
--
-- WINDOWS: window_days 90 and 365 are rolling from today (LA); 9999 means
-- lifetime. Consumers pick one — never sum across windows, they overlap.
--
-- LIFT is co-occurrence divided by what independence would predict:
--   lift = P(A and B) / (P(A) * P(B))
-- lift = 1 means the pair co-occurs exactly as often as chance. Above 1 is a
-- real affinity. Read it WITH co_orders, never alone: a pair seen in 2 orders
-- can post a spectacular lift and mean nothing.
--
-- items_through_date is carried on every row on purpose. The item feed
-- backfills oldest-first, so a window that extends past items_through_date is
-- reporting on data that has not arrived. Check it before believing a number,
-- and check V_ORDER_ITEM_COVERAGE for the per-month picture.
--
-- same_family compares COALESCE(parent_name, 'UNMAPPED:<asin>') on both sides,
-- not parent_name directly, because plain NULL = NULL. Two different unmapped
-- ASINs then correctly compare as different families; two rows for the SAME
-- unmapped ASIN can't occur here since asin_a < asin_b already prevents a self
-- pair. 'UNMAPPED:<asin>' covers two distinct situations: ASINs genuinely
-- absent from DIM_PRODUCT, and ASINs present there with no family assigned.
-- Example of the second kind: ASIN B0CHJY7XLQ ("Popsicle") and B0CHJZDD3F
-- ("BFF 1") are present in DIM_PRODUCT with no parent_name, but neither is
-- live — oi_is_active = FALSE and no sales since July 2025 — so this is not
-- the retired-and-absent case. both_mapped is a different, stricter test
-- built from two IS NOT NULL checks, and it is never NULL.
--
-- name_a/name_b/family_a/family_b are looked up live from DIM_PRODUCT at
-- query time. V_ORDER_BASKET instead reads the copy of these labels frozen
-- onto FACT_CUSTOMER_ORDER_ITEM at load time, so the two sibling views can
-- disagree briefly on the label for the same ASIN if DIM_PRODUCT changes
-- between a fact load and a query here. No drift exists today; the fact's
-- next load reconciles them.
--
-- Spec: architecture/CUSTOMER_ORDER_BASKETS.md
--
-- =============================================

CREATE OR REPLACE VIEW `onyga-482313.OI.V_ORDER_CROSS_SELL` AS

-- 9999 is a sentinel meaning "lifetime", not a real day count: DATE_SUB with
-- INTERVAL 9999 DAY computes a cutoff of 1999-04-08, which only behaves as
-- "since the beginning" because order history starts 2024-08-03. Arithmetic
-- coincidence, not an asserted invariant — holds until roughly 2051.
WITH windows AS (
  SELECT * FROM UNNEST([90, 365, 9999]) AS window_days
),

horizon AS (
  SELECT MAX(purchase_date) AS items_through_date
  FROM `onyga-482313.OI.FACT_CUSTOMER_ORDER_ITEM`
),

dim AS (
  SELECT asin, parent_name, product_short_name
  FROM `onyga-482313.OI.DIM_PRODUCT`
  QUALIFY ROW_NUMBER() OVER (PARTITION BY asin ORDER BY updated_at DESC, sku) = 1
),

-- One row per (window, order, asin): an order containing the same ASIN on two
-- lines must count once, or every pair involving it doubles. The order key is
-- composite — (selling_partner_id, amazon_order_id), always both, per the
-- SOP's Standing facts — so selling_partner_id travels with amazon_order_id
-- everywhere an order is being counted or joined below, even though only one
-- selling partner exists today.
scoped AS (
  SELECT DISTINCT
    w.window_days,
    f.selling_partner_id,
    f.amazon_order_id,
    f.asin
  FROM `onyga-482313.OI.FACT_CUSTOMER_ORDER_ITEM` f
  CROSS JOIN windows w
  WHERE NOT f.is_canceled
    AND f.quantity_ordered > 0
    AND f.purchase_date >= DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL w.window_days DAY)
),

totals AS (
  SELECT window_days,
         COUNT(DISTINCT CONCAT(selling_partner_id, '#', amazon_order_id)) AS total_orders
  FROM scoped
  GROUP BY 1
),

asin_orders AS (
  SELECT window_days, asin,
         COUNT(DISTINCT CONCAT(selling_partner_id, '#', amazon_order_id)) AS orders_with_asin
  FROM scoped
  GROUP BY 1, 2
),

pairs AS (
  SELECT
    a.window_days,
    a.asin AS asin_a,
    b.asin AS asin_b,
    COUNT(DISTINCT CONCAT(a.selling_partner_id, '#', a.amazon_order_id)) AS co_orders
  FROM scoped a
  JOIN scoped b
    ON  a.window_days        = b.window_days
    AND a.selling_partner_id = b.selling_partner_id
    AND a.amazon_order_id    = b.amazon_order_id
    AND a.asin < b.asin
  GROUP BY 1, 2, 3
)

SELECT
  p.window_days,
  p.asin_a,
  p.asin_b,
  da.product_short_name              AS name_a,
  db.product_short_name              AS name_b,
  da.parent_name                     AS family_a,
  db.parent_name                     AS family_b,
  da.parent_name IS NOT NULL
    AND db.parent_name IS NOT NULL   AS both_mapped,
  COALESCE(da.parent_name, CONCAT('UNMAPPED:', p.asin_a))
    = COALESCE(db.parent_name, CONCAT('UNMAPPED:', p.asin_b))  AS same_family,

  p.co_orders,
  oa.orders_with_asin                AS orders_a,
  ob.orders_with_asin                AS orders_b,
  t.total_orders,

  ROUND(100 * p.co_orders / t.total_orders, 4)        AS support_pct,
  ROUND(100 * p.co_orders / oa.orders_with_asin, 2)   AS pct_of_a_orders,
  ROUND(100 * p.co_orders / ob.orders_with_asin, 2)   AS pct_of_b_orders,
  ROUND(
    SAFE_DIVIDE(
      p.co_orders * t.total_orders,
      oa.orders_with_asin * ob.orders_with_asin
    ), 2)                                             AS lift,

  h.items_through_date
FROM pairs p
JOIN totals t
  USING (window_days)
JOIN asin_orders oa
  ON oa.window_days = p.window_days AND oa.asin = p.asin_a
JOIN asin_orders ob
  ON ob.window_days = p.window_days AND ob.asin = p.asin_b
LEFT JOIN dim da ON da.asin = p.asin_a
LEFT JOIN dim db ON db.asin = p.asin_b
CROSS JOIN horizon h;
