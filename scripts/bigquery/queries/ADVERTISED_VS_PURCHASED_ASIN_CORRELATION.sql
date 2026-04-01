-- =============================================
-- Correlation: advertised_asin vs purchased_asin (within parent & per ASIN)
-- =============================================
--
-- Purpose: From V_SRC_AmazonAds_purchased_product, understand:
--   1. Within a parent: when we advertise variation A, what gets purchased (A, B, C)?
--   2. Per ASIN: when this ASIN is advertised, what is the mix of purchased ASINs?
--
-- Source:  V_SRC_AmazonAds_purchased_product, DIM_PRODUCT
-- Project: onyga-482313, Dataset: OI
--
-- Usage:   Change the date window in the CTE as needed (default last 60 days).
--
-- =============================================

-- -----------------------------------------------------------------------------
-- Part 1: Within parent – advertised_asin × purchased_asin (same parent only)
-- Rows: parent, advertised_asin, purchased_asin, orders, units, sales, share of orders when advertising this ASIN
-- -----------------------------------------------------------------------------
WITH window_days AS (
  SELECT 60 AS days  -- change as needed
),
pp AS (
  SELECT
    pp.advertised_asin,
    pp.purchased_asin,
    SUM(pp.orders) AS orders,
    SUM(pp.units)  AS units,
    SUM(pp.sales)  AS sales
  FROM `onyga-482313.OI.V_SRC_AmazonAds_purchased_product` pp
  CROSS JOIN window_days w
  WHERE pp.date >= DATE_SUB(CURRENT_DATE(), INTERVAL w.days DAY)
    AND pp.advertised_asin IS NOT NULL
    AND LOWER(TRIM(pp.advertised_asin)) NOT IN ('unknown', '')
    AND pp.purchased_asin IS NOT NULL
  GROUP BY 1, 2
),
with_parents AS (
  SELECT
    adv.parent_name AS parent,
    adv.product_short_name AS advertised_product,
    pp.advertised_asin,
    pur.product_short_name AS purchased_product,
    pp.purchased_asin,
    pp.orders,
    pp.units,
    ROUND(pp.sales, 2) AS sales,
    pp.advertised_asin = pp.purchased_asin AS same_asin
  FROM pp
  JOIN `onyga-482313.OI.DIM_PRODUCT` adv ON adv.asin = pp.advertised_asin
  JOIN `onyga-482313.OI.DIM_PRODUCT` pur ON pur.asin = pp.purchased_asin
  WHERE adv.parent_name IS NOT NULL
    AND pur.parent_name IS NOT NULL
    AND adv.parent_name = pur.parent_name  -- same parent only
),
totals_per_advertised AS (
  SELECT
    parent,
    advertised_asin,
    SUM(orders) AS tot_orders,
    SUM(units)  AS tot_units,
    SUM(sales)  AS tot_sales
  FROM with_parents
  GROUP BY 1, 2
)
SELECT
  w.parent,
  w.advertised_asin,
  w.advertised_product,
  w.purchased_asin,
  w.purchased_product,
  w.same_asin,
  w.orders,
  w.units,
  w.sales,
  ROUND(SAFE_DIVIDE(w.orders, t.tot_orders) * 100, 1) AS pct_orders_when_advertising_this_asin,
  ROUND(SAFE_DIVIDE(w.sales, t.tot_sales) * 100, 1) AS pct_sales_when_advertising_this_asin
FROM with_parents w
JOIN totals_per_advertised t
  ON t.parent = w.parent AND t.advertised_asin = w.advertised_asin
ORDER BY w.parent, w.advertised_asin, w.orders DESC;


-- -----------------------------------------------------------------------------
-- Part 2: Per ASIN – when this ASIN is advertised, breakdown of purchased_asin
-- One row per (advertised_asin, purchased_asin) with totals and % of that advertised ASIN’s orders/sales
-- -----------------------------------------------------------------------------
-- Uncomment and run separately for a per-ASIN view (no parent filter; includes cross-parent if any).
--
-- WITH window_days AS (SELECT 60 AS days),
-- pp AS (
--   SELECT
--     pp.advertised_asin,
--     pp.purchased_asin,
--     SUM(pp.orders) AS orders,
--     SUM(pp.units)  AS units,
--     SUM(pp.sales)  AS sales
--   FROM `onyga-482313.OI.V_SRC_AmazonAds_purchased_product` pp
--   CROSS JOIN window_days w
--   WHERE pp.date >= DATE_SUB(CURRENT_DATE(), INTERVAL w.days DAY)
--     AND pp.advertised_asin IS NOT NULL AND LOWER(TRIM(pp.advertised_asin)) NOT IN ('unknown', '')
--     AND pp.purchased_asin IS NOT NULL
--   GROUP BY 1, 2
-- ),
-- totals_adv AS (
--   SELECT advertised_asin, SUM(orders) AS tot_orders, SUM(sales) AS tot_sales
--   FROM pp GROUP BY 1
-- )
-- SELECT
--   pp.advertised_asin,
--   adv.parent_name   AS advertised_parent,
--   adv.product_short_name AS advertised_product,
--   pp.purchased_asin,
--   pur.parent_name   AS purchased_parent,
--   pur.product_short_name AS purchased_product,
--   pp.advertised_asin = pp.purchased_asin AS same_asin,
--   pp.orders, pp.units, ROUND(pp.sales, 2) AS sales,
--   ROUND(SAFE_DIVIDE(pp.orders, t.tot_orders) * 100, 1) AS pct_orders,
--   ROUND(SAFE_DIVIDE(pp.sales, t.tot_sales) * 100, 1) AS pct_sales
-- FROM pp
-- LEFT JOIN `onyga-482313.OI.DIM_PRODUCT` adv ON adv.asin = pp.advertised_asin
-- LEFT JOIN `onyga-482313.OI.DIM_PRODUCT` pur ON pur.asin = pp.purchased_asin
-- JOIN totals_adv t ON t.advertised_asin = pp.advertised_asin
-- ORDER BY pp.advertised_asin, pp.orders DESC;
