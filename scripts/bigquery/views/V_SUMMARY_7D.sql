-- V_SUMMARY_7D: Pre-computed 7-day summary per product family
-- Used by: Cube Summary schema → HOME page
-- Source: V_UNIFIED_DAILY (asin × date grain)
-- UDFs: FN_NET_PROFIT, FN_NET_ROAS, FN_ORGANIC_PCT (shared logic layer)
-- Outputs: current 7d, previous 7d, and % change per family

CREATE OR REPLACE VIEW `onyga-482313.OI.V_SUMMARY_7D` AS

WITH date_ranges AS (
  SELECT
    MAX(date) AS latest_date,
    DATE_SUB(MAX(date), INTERVAL 6 DAY) AS period_start,   -- current 7d
    DATE_SUB(MAX(date), INTERVAL 7 DAY) AS prev_end,       -- previous 7d end
    DATE_SUB(MAX(date), INTERVAL 13 DAY) AS prev_start     -- previous 7d start
  FROM `onyga-482313.OI.V_UNIFIED_DAILY`
),

current_7d AS (
  SELECT
    u.family AS product_type,
    ANY_VALUE(u.family_color_hex) AS color_hex,
    SUM(u.sales) AS sales_7d,
    SUM(u.ad_cost) AS ad_cost_7d,
    SUM(u.cogs) AS cogs_7d,
    SUM(u.orders) AS orders_7d,
    SUM(u.organic_units) AS organic_units_7d,
    SUM(u.ad_orders) AS ad_orders_7d,
    SUM(u.clicks) AS clicks_7d,
    SUM(u.sessions) AS sessions_7d,
    SUM(u.units) AS units_7d
  FROM `onyga-482313.OI.V_UNIFIED_DAILY` u
  CROSS JOIN date_ranges dr
  WHERE u.date BETWEEN dr.period_start AND dr.latest_date
  GROUP BY 1
),

prev_7d AS (
  SELECT
    u.family AS product_type,
    SUM(u.sales) AS sales_prev_7d,
    SUM(u.ad_cost) AS ad_cost_prev_7d,
    SUM(u.cogs) AS cogs_prev_7d,
    SUM(u.orders) AS orders_prev_7d,
    SUM(u.organic_units) AS organic_units_prev_7d,
    SUM(u.ad_orders) AS ad_orders_prev_7d,
    SUM(u.clicks) AS clicks_prev_7d,
    SUM(u.sessions) AS sessions_prev_7d,
    SUM(u.units) AS units_prev_7d
  FROM `onyga-482313.OI.V_UNIFIED_DAILY` u
  CROSS JOIN date_ranges dr
  WHERE u.date BETWEEN dr.prev_start AND dr.prev_end
  GROUP BY 1
)

SELECT
  c.product_type,
  c.color_hex,

  -- Current 7d
  ROUND(c.sales_7d, 2) AS sales_7d,
  ROUND(c.ad_cost_7d, 2) AS ad_cost_7d,
  ROUND(c.cogs_7d, 2) AS cogs_7d,
  ROUND(`onyga-482313.OI.FN_NET_PROFIT`(c.sales_7d, c.ad_cost_7d, c.cogs_7d), 2) AS net_profit_7d,
  c.orders_7d,
  c.organic_units_7d,
  c.ad_orders_7d,
  c.clicks_7d,
  c.sessions_7d,
  c.units_7d,

  -- Computed ratios (current) — using shared UDFs
  COALESCE(ROUND(`onyga-482313.OI.FN_NET_ROAS`(c.sales_7d, c.cogs_7d, c.ad_cost_7d), 2), 0) AS net_roas,
  COALESCE(ROUND(`onyga-482313.OI.FN_ORGANIC_PCT`(c.organic_units_7d, c.units_7d), 1), 0) AS organic_pct,

  -- Previous 7d
  ROUND(COALESCE(p.sales_prev_7d, 0), 2) AS sales_prev_7d,
  ROUND(COALESCE(p.ad_cost_prev_7d, 0), 2) AS ad_cost_prev_7d,
  ROUND(COALESCE(p.cogs_prev_7d, 0), 2) AS cogs_prev_7d,
  ROUND(`onyga-482313.OI.FN_NET_PROFIT`(
    COALESCE(p.sales_prev_7d, 0),
    COALESCE(p.ad_cost_prev_7d, 0),
    COALESCE(p.cogs_prev_7d, 0)
  ), 2) AS net_profit_prev_7d,
  COALESCE(p.orders_prev_7d, 0) AS orders_prev_7d,
  COALESCE(p.organic_units_prev_7d, 0) AS organic_units_prev_7d,

  -- Computed ratios (previous) — using shared UDFs
  COALESCE(ROUND(`onyga-482313.OI.FN_NET_ROAS`(
    COALESCE(p.sales_prev_7d, 0),
    COALESCE(p.cogs_prev_7d, 0),
    COALESCE(p.ad_cost_prev_7d, 0)
  ), 2), 0) AS net_roas_prev,
  COALESCE(ROUND(`onyga-482313.OI.FN_ORGANIC_PCT`(
    COALESCE(p.organic_units_prev_7d, 0),
    COALESCE(p.units_prev_7d, 0)
  ), 1), 0) AS organic_pct_prev,

  -- Change %
  CASE WHEN COALESCE(p.sales_prev_7d, 0) > 0
    THEN ROUND((c.sales_7d - p.sales_prev_7d) / p.sales_prev_7d * 100, 1)
    ELSE 0
  END AS sales_change_pct,
  CASE WHEN COALESCE(p.ad_cost_prev_7d, 0) > 0
    THEN ROUND((c.ad_cost_7d - p.ad_cost_prev_7d) / p.ad_cost_prev_7d * 100, 1)
    ELSE 0
  END AS cost_change_pct,

  -- Period dates
  CAST(dr.period_start AS STRING) AS period_start,
  CAST(dr.latest_date AS STRING) AS period_end

FROM current_7d c
CROSS JOIN date_ranges dr
LEFT JOIN prev_7d p ON c.product_type = p.product_type
WHERE c.product_type IS NOT NULL;
