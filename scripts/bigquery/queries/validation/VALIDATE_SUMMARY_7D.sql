-- =============================================
-- Validation: Summary 7d (Home/Family KPIs)
-- =============================================
-- Purpose: Validate summary.json for latest 7-day period. Compare to dashboard Home/Family KPIs.
-- Source: dashboard/refresh_data.py QUERIES["summary.json"] (lines 56-174)
--
-- Logic: biz_start = MAX(date) - 6 days from V_SRC_sales_and_traffic_business_sku_report_daily.
--        This matches the dashboard's dynamic date range.
-- =============================================

WITH family_map AS (
  SELECT asin,
    CASE
      WHEN product_short_name LIKE '%Lollibox%' OR product_short_name LIKE '%Lolli Box%' THEN 'Lollibox'
      WHEN product_short_name LIKE '%LolliME%' OR product_short_name LIKE '%Lolli ME%' THEN 'LolliME'
      WHEN product_short_name LIKE '%Fresh%' THEN 'Fresh'
      WHEN product_short_name LIKE '%Truth%' OR product_short_name LIKE '%Bottle%' THEN 'Bottle'
      ELSE product_short_name
    END as family
  FROM `onyga-482313.OI.DIM_PRODUCT`
  WHERE asin IS NOT NULL AND asin != 'UNKNOWN'
),
latest_costs AS (
  SELECT asin, TOTAL_COST_PER_UNIT, cost_of_goods, shipping_cost, FBA_COST_estimated_fee_total
  FROM `onyga-482313.OI.DIM_COSTS_HISTORY`
  WHERE end_date IS NULL
    OR end_date = (SELECT MAX(end_date) FROM `onyga-482313.OI.DIM_COSTS_HISTORY` c2 WHERE c2.asin = `onyga-482313.OI.DIM_COSTS_HISTORY`.asin)
  QUALIFY ROW_NUMBER() OVER (PARTITION BY asin ORDER BY start_date DESC) = 1
),
date_range AS (
  SELECT
    MAX(date) as latest_biz_date,
    DATE_SUB(MAX(date), INTERVAL 6 DAY) as biz_start,
    DATE_SUB(MAX(date), INTERVAL 13 DAY) as prev_start,
    DATE_SUB(MAX(date), INTERVAL 7 DAY) as prev_end
  FROM `onyga-482313.OI.V_SRC_sales_and_traffic_business_sku_report_daily`
),
biz AS (
  SELECT fm.family, b.date,
    SUM(b.SALES_ORDERS) as orders,
    SUM(b.SALES_QUANTITY) as units,
    SUM(b.SALES_AMOUNT) as sales,
    SUM(b.asin_sessions) as sessions,
    SUM(b.SALES_QUANTITY * COALESCE(lc.TOTAL_COST_PER_UNIT, 0)) as cogs
  FROM `onyga-482313.OI.V_SRC_sales_and_traffic_business_sku_report_daily` b
  JOIN family_map fm ON b.child_asin = fm.asin
  LEFT JOIN latest_costs lc ON b.child_asin = lc.asin
  CROSS JOIN date_range dr
  WHERE b.date >= dr.prev_start
  GROUP BY 1, 2
),
ads AS (
  SELECT fm.family, a.date,
    SUM(a.cost) as ad_cost,
    SUM(a.clicks) as clicks,
    SUM(a.impressions) as impressions,
    SUM(a.orders) as ad_orders
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` a
  JOIN family_map fm ON a.most_advertised_asin_impressions = fm.asin
  CROSS JOIN date_range dr
  WHERE a.date >= dr.prev_start AND a.date <= dr.latest_biz_date
  GROUP BY 1, 2
),
combined AS (
  SELECT
    COALESCE(b.family, a.family) as product_type,
    COALESCE(b.date, a.date) as date,
    COALESCE(b.sales, 0) as sales,
    COALESCE(b.orders, 0) as total_orders,
    COALESCE(b.units, 0) as units,
    COALESCE(b.sessions, 0) as sessions,
    COALESCE(b.cogs, 0) as cogs,
    COALESCE(a.ad_cost, 0) as ad_cost,
    COALESCE(a.clicks, 0) as clicks,
    COALESCE(a.ad_orders, 0) as ad_orders,
    GREATEST(COALESCE(b.orders, 0) - COALESCE(a.ad_orders, 0), 0) as organic_units
  FROM biz b
  FULL OUTER JOIN ads a ON b.family = a.family AND b.date = a.date
),
this_week AS (
  SELECT product_type,
    SUM(sales) as sales_7d, SUM(ad_cost) as ad_cost_7d,
    SUM(cogs) as cogs_7d,
    SUM(total_orders) as orders_7d, SUM(organic_units) as organic_units_7d,
    SUM(clicks) as clicks_7d, SUM(ad_orders) as ad_orders_7d,
    SUM(sessions) as sessions_7d,
    MIN(date) as period_start, MAX(date) as period_end
  FROM combined, date_range dr
  WHERE date >= dr.biz_start
  GROUP BY 1
)
SELECT
  product_type,
  ROUND(sales_7d, 2) as sales_7d,
  ROUND(ad_cost_7d, 2) as ad_cost_7d,
  ROUND(cogs_7d, 2) as cogs_7d,
  ROUND(sales_7d - ad_cost_7d - cogs_7d, 2) as net_profit_7d,
  orders_7d,
  organic_units_7d,
  ad_orders_7d,
  clicks_7d,
  sessions_7d,
  ROUND(SAFE_DIVIDE(sales_7d - ad_cost_7d - cogs_7d, NULLIF(ad_cost_7d, 0)), 2) as net_roas,
  ROUND(SAFE_DIVIDE(organic_units_7d * 100.0, NULLIF(orders_7d, 0)), 1) as organic_pct,
  CAST(period_start AS STRING) as period_start,
  CAST(period_end AS STRING) as period_end
FROM this_week
ORDER BY sales_7d DESC;
