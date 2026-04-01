-- Drilldown: Find Ads rows where (date, PURCHASED_ASIN) not in STG_AMAZON_PERFORMANCE
-- These contribute to FACT total but not to Performance total
WITH perf_keys AS (
  SELECT DISTINCT DATE, PURCHASED_ASIN
  FROM `onyga-482313.OI.STG_AMAZON_PERFORMANCE`
  WHERE IS_LOADED = TRUE
),
ads_only_in_fact AS (
  SELECT
    f.DATE,
    f.PURCHASED_ASIN,
    SUM(f.PURCHASED_ORDERS) as orders,
    SUM(f.PURCHASED_UNITS) as units,
    SUM(f.PURCHASED_AMOUNT_USD) as sales_usd
  FROM `onyga-482313.OI.FACT_AMAZON_PERFORMANCE_DAILY` f
  WHERE f.Performance_TYPE = 'Ads'
  AND NOT EXISTS (
    SELECT 1 FROM perf_keys p
    WHERE p.DATE = f.DATE AND p.PURCHASED_ASIN = f.PURCHASED_ASIN
  )
  GROUP BY f.DATE, f.PURCHASED_ASIN
)
SELECT
  'Ads rows not in Performance' as category,
  COUNT(*) as row_count,
  SUM(orders) as total_orders,
  SUM(units) as total_units,
  ROUND(SUM(sales_usd), 2) as total_sales_usd
FROM ads_only_in_fact;
