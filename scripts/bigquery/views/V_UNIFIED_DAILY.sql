-- =============================================
-- OI Database Project - V_UNIFIED_DAILY
-- =============================================
--
-- Purpose: Single source of truth for dashboard performance metrics.
--          Joins business performance (FACT_AMAZON_PERFORMANCE_DAILY) with
--          ads spend (FACT_AMAZON_ADS) at the (asin × date) grain.
--
-- Ads Attribution: most_advertised_asin_impressions ONLY
-- Grain: One row per ASIN per DATE
--
-- Consumers: UnifiedPerformance Cube (sole consumer)
--            Replaces: Summary, WeeklyTrends, WeeklyTrendsByAsin,
--                      MonthlyTrends, MonthlyTrendsByAsin
--
-- Rules compliance:
--   [x] BQ R1: Single source for joins (ads + perf joined once here)
--   [x] BQ R2: Uses UDFs (FN_COGS)
--   [x] BQ R5: Grain matches Cube grain (asin × date)
--   [x] BQ R6: Explicit columns (no SELECT *)
--   [x] BQ R7: Filters pushed early in CTEs
--   [x] Cube R2: View for sql_table reference
--   [x] Cube R5: Finest grain (daily)
-- =============================================

CREATE OR REPLACE VIEW `onyga-482313.OI.V_UNIFIED_DAILY` AS

WITH
-- Business performance: one row per ASIN per day
-- Collapses multiple DATA_SOURCE rows (Organic, SB, SP, etc.)
perf AS (
  SELECT
    p.PURCHASED_ASIN AS asin,
    p.DATE AS date,
    SUM(p.PURCHASED_AMOUNT_USD) AS sales,
    SUM(p.PURCHASED_ORDERS) AS orders,
    SUM(p.PURCHASED_UNITS) AS units,
    SUM(p.ASIN_SESSIONS) AS sessions,
    SUM(`onyga-482313.OI.FN_COGS`(p.PURCHASED_UNITS, p.TOTAL_COST_PER_UNIT)) AS cogs,
    SUM(CASE WHEN p.Performance_TYPE = 'Organic' THEN p.PURCHASED_UNITS ELSE 0 END) AS organic_units
  FROM `onyga-482313.OI.FACT_AMAZON_PERFORMANCE_DAILY` p
  WHERE p.PURCHASED_ASIN IS NOT NULL
  GROUP BY 1, 2
),

-- Ads metrics: one row per ASIN per day
-- Attribution: most_advertised_asin_impressions ONLY
ads AS (
  SELECT
    a.most_advertised_asin_impressions AS asin,
    a.date,
    SUM(a.Ads_cost) AS ad_cost,
    SUM(a.Ads_clicks) AS clicks,
    SUM(a.Ads_impressions) AS impressions,
    SUM(a.Ads_orders) AS ad_orders
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` a
  WHERE a.most_advertised_asin_impressions IS NOT NULL
  GROUP BY 1, 2
)

-- Final join: FULL OUTER JOIN ensures no data is lost
-- Product family and time dimensions enriched here
SELECT
  fm.family AS family,
  fm.product_short_name AS product_short_name,
  COALESCE(p.asin, a.asin) AS asin,
  COALESCE(p.date, a.date) AS date,
  dt.week_start_date AS week_start_date,
  DATE_TRUNC(COALESCE(p.date, a.date), MONTH) AS month_start,
  -- Business metrics
  COALESCE(p.sales, 0) AS sales,
  COALESCE(p.orders, 0) AS orders,
  COALESCE(p.units, 0) AS units,
  COALESCE(p.sessions, 0) AS sessions,
  COALESCE(p.cogs, 0) AS cogs,
  COALESCE(p.organic_units, 0) AS organic_units,
  -- Ads metrics
  COALESCE(a.ad_cost, 0) AS ad_cost,
  COALESCE(a.clicks, 0) AS clicks,
  COALESCE(a.impressions, 0) AS impressions,
  COALESCE(a.ad_orders, 0) AS ad_orders
FROM perf p
FULL OUTER JOIN ads a ON p.asin = a.asin AND p.date = a.date
JOIN `onyga-482313.OI.V_PRODUCT_FAMILY_MAP` fm
  ON COALESCE(p.asin, a.asin) = fm.asin
JOIN `onyga-482313.OI.DIM_TIME` dt
  ON COALESCE(p.date, a.date) = dt.full_date;
