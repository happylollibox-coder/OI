CREATE OR REPLACE VIEW `onyga-482313.OI.V_ADS_COACH_CROSSSELL` AS
-- Cross-sell recommendation view: pairs (target_asin=A, advertise_asin=B) where
-- shoppers who engaged ads for A also bought B, both are our products, and B is
-- not already targeted on A's listing.
-- Grain: (target_asin, advertise_asin) — one row per qualifying cross-sell gap.
WITH thr AS (
  SELECT COALESCE(MAX(IF(threshold_key='CROSS_SELL_MIN_ORDERS', threshold_value, NULL)), 3) AS min_orders
  FROM `onyga-482313.OI.DE_COACH_THRESHOLDS`
  WHERE strategy_id='GLOBAL' AND product_family IS NULL
),
pairs AS (
  SELECT
    pp.advertised_asin AS target_asin,
    pp.purchased_asin  AS advertise_asin,
    SUM(pp.orders)     AS cross_orders_30d,
    ROUND(SUM(pp.sales), 2) AS cross_sales_30d
  FROM `onyga-482313.OI.V_SRC_AmazonAds_purchased_product` pp
  WHERE pp.date >= DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL 30 DAY)
    AND pp.advertised_asin IS NOT NULL
    AND pp.purchased_asin  IS NOT NULL
    AND pp.advertised_asin != pp.purchased_asin
  GROUP BY 1, 2
),
covered AS (
  -- Product-target ads active in the last 30 days: A already advertising B
  SELECT DISTINCT
    REGEXP_EXTRACT(LOWER(fa.targeting), r'asin="?(b0[a-z0-9]{8})"?') AS target_asin,
    COALESCE(fa.most_advertised_asin_impressions, fa.ASIN_BY_CAMPAIGN_NAME) AS advertise_asin
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` fa
  WHERE fa.date >= DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL 30 DAY)
    AND LOWER(fa.targeting) LIKE 'asin=%'
)
SELECT
  p.target_asin,
  p.advertise_asin,
  pa.parent_name    AS target_parent,
  pb.parent_name    AS advertise_parent,
  pa.product_name   AS target_name,
  pb.product_name   AS advertise_name,
  p.cross_orders_30d,
  p.cross_sales_30d,
  CASE
    WHEN p.cross_orders_30d >= 10 THEN 'HIGH'
    WHEN p.cross_orders_30d >= 5  THEN 'MEDIUM'
    ELSE                               'LOW'
  END AS confidence
FROM pairs p
CROSS JOIN thr
JOIN `onyga-482313.OI.DIM_PRODUCT` pa ON p.target_asin   = pa.asin
JOIN `onyga-482313.OI.DIM_PRODUCT` pb ON p.advertise_asin = pb.asin
LEFT JOIN covered c
  ON c.target_asin   = p.target_asin
 AND c.advertise_asin = p.advertise_asin
WHERE p.cross_orders_30d >= thr.min_orders
  AND c.target_asin IS NULL;
