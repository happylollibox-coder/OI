-- =============================================
-- Best advertised ASIN per parent (which variation to advertise)
-- =============================================
--
-- Purpose: From V_SRC_AmazonAds_purchased_product, rank advertised ASINs
--          within each parent to see which variation drives the most attributed
--          orders/sales (and optionally ROAS when joined to ad cost).
--
-- Source:  V_SRC_AmazonAds_purchased_product, DIM_PRODUCT
-- Optional: FACT_AMAZON_ADS (for cost and ROAS)
--
-- Usage:   Run as-is for last 60 days; change the date filter as needed.
-- Project: onyga-482313, Dataset: OI
--
-- =============================================

-- -----------------------------------------------------------------------------
-- Version 1: Best advertised ASIN by orders and sales (no cost)
-- -----------------------------------------------------------------------------
WITH pp_agg AS (
  SELECT
    pp.advertised_asin,
    SUM(pp.orders)   AS total_orders,
    SUM(pp.units)    AS total_units,
    SUM(pp.sales)    AS total_sales
  FROM `onyga-482313.OI.V_SRC_AmazonAds_purchased_product` pp
  WHERE pp.date >= DATE_SUB(CURRENT_DATE(), INTERVAL 60 DAY)
    AND pp.advertised_asin IS NOT NULL
    AND LOWER(TRIM(pp.advertised_asin)) NOT IN ('unknown', '')
  GROUP BY 1
),
with_parent AS (
  SELECT
    p.parent_name,
    p.product_short_name,
    a.advertised_asin,
    a.total_orders,
    a.total_units,
    ROUND(a.total_sales, 2) AS total_sales,
    ROW_NUMBER() OVER (PARTITION BY p.parent_name ORDER BY a.total_orders DESC, a.total_sales DESC) AS rank_by_orders,
    ROW_NUMBER() OVER (PARTITION BY p.parent_name ORDER BY a.total_sales DESC, a.total_orders DESC) AS rank_by_sales
  FROM pp_agg a
  JOIN `onyga-482313.OI.DIM_PRODUCT` p
    ON p.asin = a.advertised_asin
  WHERE p.parent_name IS NOT NULL
)
SELECT
  parent_name,
  advertised_asin,
  product_short_name,
  total_orders,
  total_units,
  total_sales,
  rank_by_orders   AS best_rank_by_orders,
  rank_by_sales    AS best_rank_by_sales,
  CASE WHEN rank_by_orders = 1 THEN 'BEST' ELSE NULL END AS best_variation_by_orders
FROM with_parent
ORDER BY parent_name, rank_by_orders;


-- -----------------------------------------------------------------------------
-- Version 2: Best advertised ASIN by ROAS (with ad cost from FACT_AMAZON_ADS)
-- -----------------------------------------------------------------------------
-- Uncomment and run separately if you want to rank by efficiency (ROAS).
--
-- WITH pp_agg AS (
--   SELECT
--     pp.advertised_asin,
--     SUM(pp.orders)   AS total_orders,
--     SUM(pp.units)    AS total_units,
--     SUM(pp.sales)    AS total_sales
--   FROM `onyga-482313.OI.V_SRC_AmazonAds_purchased_product` pp
--   WHERE pp.date >= DATE_SUB(CURRENT_DATE(), INTERVAL 60 DAY)
--     AND pp.advertised_asin IS NOT NULL
--     AND LOWER(TRIM(pp.advertised_asin)) NOT IN ('unknown', '')
--   GROUP BY 1
-- ),
-- cost_agg AS (
--   SELECT
--     fa.advertised_asins AS advertised_asin,
--     SUM(fa.cost)        AS total_cost
--   FROM `onyga-482313.OI.FACT_AMAZON_ADS` fa
--   WHERE fa.date >= DATE_SUB(CURRENT_DATE(), INTERVAL 60 DAY)
--     AND fa.advertised_asins IS NOT NULL
--   GROUP BY 1
-- ),
-- with_parent AS (
--   SELECT
--     p.parent_name,
--     p.product_short_name,
--     a.advertised_asin,
--     a.total_orders,
--     a.total_units,
--     ROUND(a.total_sales, 2)     AS total_sales,
--     ROUND(COALESCE(c.total_cost, 0), 2) AS total_cost,
--     ROUND(SAFE_DIVIDE(a.total_sales, NULLIF(c.total_cost, 0)), 2) AS roas
--   FROM pp_agg a
--   JOIN `onyga-482313.OI.DIM_PRODUCT` p ON p.asin = a.advertised_asin
--   LEFT JOIN cost_agg c ON c.advertised_asin = a.advertised_asin
--   WHERE p.parent_name IS NOT NULL
-- ),
-- ranked AS (
--   SELECT
--     *,
--     ROW_NUMBER() OVER (PARTITION BY parent_name ORDER BY roas DESC NULLS LAST, total_orders DESC) AS rank_by_roas
--   FROM with_parent
-- )
-- SELECT
--   parent_name,
--   advertised_asin,
--   product_short_name,
--   total_orders,
--   total_units,
--   total_sales,
--   total_cost,
--   roas,
--   rank_by_roas,
--   CASE WHEN rank_by_roas = 1 THEN 'BEST' ELSE NULL END AS best_variation_by_roas
-- FROM ranked
-- ORDER BY parent_name, rank_by_roas;
