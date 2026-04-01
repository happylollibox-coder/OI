-- =============================================
-- Validation: FACT_AMAZON_PERFORMANCE_DAILY totals vs STG_AMAZON_PERFORMANCE
-- =============================================
--
-- Purpose: Verify that sum of measures in FACT equals sum in STG_AMAZON_PERFORMANCE
-- Measures: PURCHASED_ORDERS, PURCHASED_UNITS, PURCHASED_AMOUNT_USD, ASIN_SESSIONS, ASIN_PAGE_VIEWS
--
-- Expected: FACT total = STG_AMAZON_PERFORMANCE total (for IS_LOADED=TRUE rows)
-- Note: When Ads > Performance for an ASIN/date (negative delta), we cap Organic at 0,
--       so FACT can exceed Performance for that ASIN. Overall totals may differ in that case.
--
-- =============================================

WITH fact_totals AS (
  SELECT
    SUM(PURCHASED_ORDERS) as total_orders,
    SUM(PURCHASED_UNITS) as total_units,
    SUM(PURCHASED_AMOUNT_USD) as total_sales_usd,
    SUM(COALESCE(ASIN_SESSIONS, 0)) as total_sessions,
    SUM(COALESCE(ASIN_PAGE_VIEWS, 0)) as total_page_views
  FROM `onyga-482313.OI.FACT_AMAZON_PERFORMANCE_DAILY`
),
stg_totals AS (
  SELECT
    SUM(PURCHASED_ORDERS) as total_orders,
    SUM(PURCHASED_UNITS) as total_units,
    SUM(PURCHASED_AMOUNT_USD) as total_sales_usd,
    SUM(COALESCE(ASIN_SESSIONS, 0)) as total_sessions,
    SUM(COALESCE(ASIN_PAGE_VIEWS, 0)) as total_page_views
  FROM `onyga-482313.OI.STG_AMAZON_PERFORMANCE`
  WHERE IS_LOADED = TRUE
)
SELECT
  'PURCHASED_ORDERS' as measure,
  f.total_orders as fact_total,
  s.total_orders as stg_total,
  f.total_orders - s.total_orders as difference,
  CASE WHEN f.total_orders = s.total_orders THEN 'OK' ELSE 'MISMATCH' END as status
FROM fact_totals f, stg_totals s
UNION ALL
SELECT
  'PURCHASED_UNITS',
  f.total_units,
  s.total_units,
  f.total_units - s.total_units,
  CASE WHEN f.total_units = s.total_units THEN 'OK' ELSE 'MISMATCH' END
FROM fact_totals f, stg_totals s
UNION ALL
SELECT
  'PURCHASED_AMOUNT_USD',
  f.total_sales_usd,
  s.total_sales_usd,
  f.total_sales_usd - s.total_sales_usd,
  CASE WHEN f.total_sales_usd = s.total_sales_usd THEN 'OK' ELSE 'MISMATCH' END
FROM fact_totals f, stg_totals s
UNION ALL
SELECT
  'ASIN_SESSIONS',
  f.total_sessions,
  s.total_sessions,
  f.total_sessions - s.total_sessions,
  CASE WHEN f.total_sessions = s.total_sessions THEN 'OK' ELSE 'MISMATCH' END
FROM fact_totals f, stg_totals s
UNION ALL
SELECT
  'ASIN_PAGE_VIEWS',
  f.total_page_views,
  s.total_page_views,
  f.total_page_views - s.total_page_views,
  CASE WHEN f.total_page_views = s.total_page_views THEN 'OK' ELSE 'MISMATCH' END
FROM fact_totals f, stg_totals s
ORDER BY measure;
