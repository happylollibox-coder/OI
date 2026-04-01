-- Drilldown: Find (date, PURCHASED_ASIN) where Ads > Performance (negative delta)
-- These contribute excess to FACT because we cap Organic at 0
WITH ads_by_asin AS (
  SELECT
    DATE,
    PURCHASED_ASIN,
    SUM(PURCHASED_ORDERS) as ads_orders,
    SUM(PURCHASED_UNITS) as ads_units,
    SUM(PURCHASED_AMOUNT_USD) as ads_sales
  FROM `onyga-482313.OI.FACT_AMAZON_PERFORMANCE_DAILY`
  WHERE Performance_TYPE = 'Ads'
  GROUP BY DATE, PURCHASED_ASIN
),
negative_deltas AS (
  SELECT
    p.DATE,
    p.PURCHASED_ASIN,
    p.PURCHASED_ORDERS as perf_orders,
    p.PURCHASED_UNITS as perf_units,
    p.PURCHASED_AMOUNT_USD as perf_sales,
    a.ads_orders,
    a.ads_units,
    a.ads_sales,
    a.ads_orders - p.PURCHASED_ORDERS as orders_excess,
    a.ads_units - p.PURCHASED_UNITS as units_excess,
    a.ads_sales - p.PURCHASED_AMOUNT_USD as sales_excess
  FROM `onyga-482313.OI.STG_AMAZON_PERFORMANCE` p
  JOIN ads_by_asin a ON p.DATE = a.DATE AND p.PURCHASED_ASIN = a.PURCHASED_ASIN
  WHERE p.IS_LOADED = TRUE
  AND (a.ads_orders > p.PURCHASED_ORDERS
    OR a.ads_units > p.PURCHASED_UNITS
    OR a.ads_sales > p.PURCHASED_AMOUNT_USD)
)
SELECT
  'Negative delta (Ads > Perf)' as category,
  COUNT(*) as row_count,
  SUM(orders_excess) as total_orders_excess,
  SUM(units_excess) as total_units_excess,
  ROUND(SUM(sales_excess), 2) as total_sales_excess
FROM negative_deltas;
