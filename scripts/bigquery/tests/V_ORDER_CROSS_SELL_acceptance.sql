-- =============================================================================================
-- V_ORDER_CROSS_SELL + V_ORDER_BASKET acceptance — every row must read PASS.
-- Run after SP_LOAD_FACT_CUSTOMER_ORDER_ITEM:
--   bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache < FILE
-- Spec: architecture/CUSTOMER_ORDER_BASKETS.md
--
-- Checks:
--   B1 Pairs are unordered and deduplicated: asin_a < asin_b on every row, so a pair
--      never appears twice mirrored.
--   B2 Co-occurrence cannot exceed either side's own order count.
--   B3 support_pct is a real percentage (0 < support <= 100).
--   B4 lift is finite and positive on every row.
--   B5 Every window present has a positive total_orders.
--   B6 Basket arithmetic: a MULTI_PRODUCT basket really does hold >1 distinct ASIN,
--      and a SINGLE basket really is one product and one unit.
--   B7 No canceled order reaches the basket view.
--   B8 Every pair's two ASINs both appear in the fact — no phantom ASINs.
-- =============================================================================================
WITH
b1 AS (
  SELECT 'B1 pairs unordered and deduped' AS check_name,
         IF(COUNT(*) = 0, 'PASS', 'FAIL') AS status,
         FORMAT('%d rows with asin_a >= asin_b', COUNT(*)) AS detail
  FROM `onyga-482313.OI.V_ORDER_CROSS_SELL`
  WHERE asin_a >= asin_b
),

b2 AS (
  SELECT 'B2 co_orders within both sides' AS check_name,
         IF(COUNT(*) = 0, 'PASS', 'FAIL') AS status,
         FORMAT('%d rows where co_orders exceeds orders_a or orders_b', COUNT(*)) AS detail
  FROM `onyga-482313.OI.V_ORDER_CROSS_SELL`
  WHERE co_orders > orders_a OR co_orders > orders_b
),

b3 AS (
  SELECT 'B3 support is a real percentage' AS check_name,
         IF(COUNT(*) = 0, 'PASS', 'FAIL') AS status,
         FORMAT('%d rows with support outside (0,100]', COUNT(*)) AS detail
  FROM `onyga-482313.OI.V_ORDER_CROSS_SELL`
  WHERE support_pct <= 0 OR support_pct > 100
),

b4 AS (
  SELECT 'B4 lift finite and positive' AS check_name,
         IF(COUNT(*) = 0, 'PASS', 'FAIL') AS status,
         FORMAT('%d rows with a null or non-positive lift', COUNT(*)) AS detail
  FROM `onyga-482313.OI.V_ORDER_CROSS_SELL`
  WHERE lift IS NULL OR lift <= 0 OR IS_INF(lift) OR IS_NAN(lift)
),

b5 AS (
  SELECT 'B5 every window has orders' AS check_name,
         IF(COUNT(*) = 0, 'PASS', 'FAIL') AS status,
         FORMAT('%d windows with total_orders <= 0', COUNT(*)) AS detail
  FROM (
    SELECT window_days
    FROM `onyga-482313.OI.V_ORDER_CROSS_SELL`
    GROUP BY 1
    HAVING MAX(total_orders) <= 0
  )
),

b6 AS (
  SELECT 'B6 basket_kind matches its arithmetic' AS check_name,
         IF(COUNT(*) = 0, 'PASS', 'FAIL') AS status,
         FORMAT('%d baskets whose kind contradicts their counts', COUNT(*)) AS detail
  FROM `onyga-482313.OI.V_ORDER_BASKET`
  WHERE (basket_kind = 'MULTI_PRODUCT'   AND distinct_asins <= 1)
     OR (basket_kind = 'MULTI_UNIT_SAME' AND (distinct_asins != 1 OR units <= 1))
     OR (basket_kind = 'SINGLE'          AND (distinct_asins != 1 OR units != 1))
),

b7 AS (
  SELECT 'B7 no canceled order in baskets' AS check_name,
         IF(COUNT(*) = 0, 'PASS', 'FAIL') AS status,
         FORMAT('%d canceled orders leaked into V_ORDER_BASKET', COUNT(*)) AS detail
  FROM `onyga-482313.OI.V_ORDER_BASKET` b
  JOIN `onyga-482313.OI.V_SRC_ListOrder` o
    USING (selling_partner_id, amazon_order_id)
  WHERE o.is_canceled
),

b8 AS (
  SELECT 'B8 no phantom ASINs in pairs' AS check_name,
         IF(COUNT(*) = 0, 'PASS', 'FAIL') AS status,
         FORMAT('%d pair-sides with an ASIN absent from the fact', COUNT(*)) AS detail
  FROM (
    SELECT asin_a AS a FROM `onyga-482313.OI.V_ORDER_CROSS_SELL`
    UNION ALL
    SELECT asin_b FROM `onyga-482313.OI.V_ORDER_CROSS_SELL`
  ) p
  LEFT JOIN (
    SELECT DISTINCT asin FROM `onyga-482313.OI.FACT_CUSTOMER_ORDER_ITEM`
  ) f
    ON f.asin = p.a
  WHERE f.asin IS NULL
)

SELECT * FROM b1
UNION ALL SELECT * FROM b2
UNION ALL SELECT * FROM b3
UNION ALL SELECT * FROM b4
UNION ALL SELECT * FROM b5
UNION ALL SELECT * FROM b6
UNION ALL SELECT * FROM b7
UNION ALL SELECT * FROM b8
ORDER BY check_name;
