-- =============================================================================================
-- FACT_CUSTOMER_ORDER_ITEM acceptance — every row must read PASS.
-- Run after SP_LOAD_FACT_CUSTOMER_ORDER_ITEM:
--   bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache < FILE
-- Spec: architecture/CUSTOMER_ORDER_BASKETS.md
--
-- Checks:
--   A1 No fan-out: fact row count never exceeds the joined source row count. fact < src is
--      ordinary sync lag (the source is a continuously-syncing feed, the loader runs daily)
--      and PASSes with the lag stated; fact > src is a defect — rows the no-DELETE-arm MERGE
--      in SP_LOAD_FACT_CUSTOMER_ORDER_ITEM would never clean up.
--   A2 Key uniqueness: (selling_partner_id, amazon_order_id, order_item_id) appears once.
--   A3 No NULL keys and no NULL purchase_date.
--   A4 Referential integrity: every fact order exists in V_SRC_ListOrder.
--   A5 Dates are inside the feed's real window (2024-08-01 .. today LA).
--   A6 Header reconciliation: for every non-canceled order in the fact, the item units sum
--      to the header's own unit count. A mismatch means line items are missing for that
--      order, which is the failure mode that silently shrinks baskets.
--   A7 Mapping drift guard: unmapped ASINs stay under 10% of units. ~4% is expected
--      (retired products); a jump means DIM_PRODUCT lost live ASINs. Note: is_mapped_product
--      only tests that a DIM_PRODUCT row exists, not that it carries a family — rows with
--      is_mapped_product = TRUE and parent_name IS NULL pass A7 uncaught; that gap belongs to
--      DIM_PRODUCT's completeness, not this fact.
--   A8 Canceled orders carry no units, so they can never inflate a basket.
--   A9 No source item without an order header: the loader INNER JOINs items to headers, so an
--      item with no matching header is silently dropped and invisible to A1 (missing from both
--      sides of that comparison at once). Both sides here read the same live views in one
--      query, so this check carries no sync-lag artifact.
-- =============================================================================================
WITH
src AS (
  SELECT COUNT(*) AS n
  FROM `onyga-482313.OI.V_SRC_ListOrderItems` i
  JOIN `onyga-482313.OI.V_SRC_ListOrder` o USING (selling_partner_id, amazon_order_id)
),
fact AS (SELECT COUNT(*) AS n FROM `onyga-482313.OI.FACT_CUSTOMER_ORDER_ITEM`),

a1 AS (
  SELECT 'A1 no fan-out (fact never exceeds source)' AS check_name,
         IF((SELECT n FROM fact) <= (SELECT n FROM src), 'PASS', 'FAIL') AS status,
         CASE
           WHEN (SELECT n FROM fact) > (SELECT n FROM src)
             THEN FORMAT('fact=%d source=%d — fact is AHEAD by %d: rows the no-DELETE MERGE never cleaned',
                         (SELECT n FROM fact), (SELECT n FROM src),
                         (SELECT n FROM fact) - (SELECT n FROM src))
           WHEN (SELECT n FROM fact) < (SELECT n FROM src)
             THEN FORMAT('fact=%d source=%d — fact is BEHIND by %d: ordinary sync lag, rerun the loader',
                         (SELECT n FROM fact), (SELECT n FROM src),
                         (SELECT n FROM src) - (SELECT n FROM fact))
           ELSE FORMAT('fact=%d source=%d — exact', (SELECT n FROM fact), (SELECT n FROM src))
         END AS detail
),

a2 AS (
  SELECT 'A2 key uniqueness' AS check_name,
         IF(COUNT(*) = 0, 'PASS', 'FAIL') AS status,
         FORMAT('%d duplicated keys', COUNT(*)) AS detail
  FROM (
    SELECT selling_partner_id, amazon_order_id, order_item_id
    FROM `onyga-482313.OI.FACT_CUSTOMER_ORDER_ITEM`
    GROUP BY 1,2,3 HAVING COUNT(*) > 1
  )
),

a3 AS (
  SELECT 'A3 no null keys or dates' AS check_name,
         IF(COUNT(*) = 0, 'PASS', 'FAIL') AS status,
         FORMAT('%d rows with a null key or date', COUNT(*)) AS detail
  FROM `onyga-482313.OI.FACT_CUSTOMER_ORDER_ITEM`
  WHERE selling_partner_id IS NULL OR amazon_order_id IS NULL
     OR order_item_id IS NULL OR purchase_date IS NULL
),

a4 AS (
  SELECT 'A4 referential integrity to headers' AS check_name,
         IF(COUNT(*) = 0, 'PASS', 'FAIL') AS status,
         FORMAT('%d orphan fact rows', COUNT(*)) AS detail
  FROM `onyga-482313.OI.FACT_CUSTOMER_ORDER_ITEM` f
  LEFT JOIN `onyga-482313.OI.V_SRC_ListOrder` o
    USING (selling_partner_id, amazon_order_id)
  WHERE o.amazon_order_id IS NULL
),

a5 AS (
  SELECT 'A5 dates inside the feed window' AS check_name,
         IF(COUNT(*) = 0, 'PASS', 'FAIL') AS status,
         FORMAT('%d rows outside 2024-08-01..today', COUNT(*)) AS detail
  FROM `onyga-482313.OI.FACT_CUSTOMER_ORDER_ITEM`
  WHERE purchase_date < DATE '2024-08-01'
     OR purchase_date > CURRENT_DATE('America/Los_Angeles')
),

a6 AS (
  SELECT 'A6 item units reconcile to header' AS check_name,
         IF(COUNT(*) = 0, 'PASS', 'FAIL') AS status,
         FORMAT('%d orders whose items do not sum to the header count', COUNT(*)) AS detail
  FROM (
    SELECT selling_partner_id, amazon_order_id
    FROM `onyga-482313.OI.FACT_CUSTOMER_ORDER_ITEM`
    WHERE NOT is_canceled
    GROUP BY 1, 2
    HAVING SUM(quantity_ordered) != MAX(order_units_total)
  )
),

a7 AS (
  SELECT 'A7 unmapped-ASIN share under 10%' AS check_name,
         IF(pct < 10, 'PASS', 'FAIL') AS status,
         FORMAT('%.2f%% of units are unmapped', pct) AS detail
  FROM (
    SELECT 100 * SAFE_DIVIDE(
             SUM(IF(is_mapped_product, 0, quantity_ordered)),
             SUM(quantity_ordered)) AS pct
    FROM `onyga-482313.OI.FACT_CUSTOMER_ORDER_ITEM`
  )
),

a8 AS (
  SELECT 'A8 canceled orders carry no units' AS check_name,
         IF(COUNT(*) = 0, 'PASS', 'FAIL') AS status,
         FORMAT('%d canceled rows with units', COUNT(*)) AS detail
  FROM `onyga-482313.OI.FACT_CUSTOMER_ORDER_ITEM`
  WHERE is_canceled AND quantity_ordered > 0
),

a9 AS (
  SELECT 'A9 no source item without an order header' AS check_name,
         IF(COUNT(*) = 0, 'PASS', 'FAIL') AS status,
         FORMAT('%d source items the loader would silently drop', COUNT(*)) AS detail
  FROM `onyga-482313.OI.V_SRC_ListOrderItems` i
  LEFT JOIN `onyga-482313.OI.V_SRC_ListOrder` o
    USING (selling_partner_id, amazon_order_id)
  WHERE o.amazon_order_id IS NULL
)

SELECT * FROM a1
UNION ALL SELECT * FROM a2
UNION ALL SELECT * FROM a3
UNION ALL SELECT * FROM a4
UNION ALL SELECT * FROM a5
UNION ALL SELECT * FROM a6
UNION ALL SELECT * FROM a7
UNION ALL SELECT * FROM a8
UNION ALL SELECT * FROM a9
ORDER BY check_name;
