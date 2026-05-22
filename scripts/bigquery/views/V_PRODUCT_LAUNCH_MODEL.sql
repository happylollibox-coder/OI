-- V_PRODUCT_LAUNCH_MODEL — First-year sales patterns per product
-- Auto-computed from actual sales data. Shows month 1-12 relative
-- to each product's first sale date.
--
-- Used by: V_FORECAST_DEMAND (Phase 1 cold-start forecasting)
-- Used by: PlanPage (model selection UI — shows available patterns)
--
-- Design decisions:
--   1. month_num is relative to launch (1 = first month with sales)
--   2. daily_rate = units / selling_days
--   3. ramp_index normalizes against month-2 rate (month 1 often partial)
--   4. Only products with ≥180 days of history qualify as models
--
-- Invariant #8: All business logic in SQL.

CREATE OR REPLACE VIEW `onyga-482313.OI.V_PRODUCT_LAUNCH_MODEL` AS

WITH first_sales AS (
  SELECT
    product_short_name AS product,
    family,
    MIN(date) AS first_sale_date
  FROM `onyga-482313.OI.T_UNIFIED_DAILY`
  WHERE units > 0
    AND product_short_name IS NOT NULL
  GROUP BY 1, 2
),
qualified_products AS (
  SELECT *
  FROM first_sales
  WHERE DATE_DIFF(CURRENT_DATE(), first_sale_date, DAY) >= 180
),
monthly_sales AS (
  SELECT
    qp.product,
    qp.family,
    qp.first_sale_date,
    DATE_DIFF(
      DATE_TRUNC(u.date, MONTH),
      DATE_TRUNC(qp.first_sale_date, MONTH),
      MONTH
    ) + 1 AS month_num,
    SUM(u.units) AS total_units,
    COUNT(DISTINCT u.date) AS selling_days
  FROM qualified_products qp
  JOIN `onyga-482313.OI.T_UNIFIED_DAILY` u
    ON qp.product = u.product_short_name
  WHERE u.date >= qp.first_sale_date
    AND u.date < DATE_ADD(qp.first_sale_date, INTERVAL 12 MONTH)
    AND u.units > 0
  GROUP BY 1, 2, 3, 4
),
-- Add period_days after aggregation
monthly_with_days AS (
  SELECT
    ms.*,
    DATE_DIFF(
      LEAST(
        DATE_ADD(DATE_ADD(DATE_TRUNC(ms.first_sale_date, MONTH), INTERVAL ms.month_num - 1 MONTH), INTERVAL 1 MONTH),
        DATE_ADD(ms.first_sale_date, INTERVAL 12 MONTH)
      ),
      GREATEST(
        DATE_ADD(DATE_TRUNC(ms.first_sale_date, MONTH), INTERVAL ms.month_num - 1 MONTH),
        ms.first_sale_date
      ),
      DAY
    ) AS period_days
  FROM monthly_sales ms
),
month2_rate AS (
  SELECT product, SAFE_DIVIDE(total_units, NULLIF(period_days, 0)) AS daily_rate
  FROM monthly_with_days
  WHERE month_num = 2
),
first_year_total AS (
  SELECT product, SUM(total_units) AS year1_units
  FROM monthly_with_days
  WHERE month_num BETWEEN 1 AND 12
  GROUP BY 1
)
SELECT
  mwd.product,
  mwd.family,
  mwd.first_sale_date,
  mwd.month_num,
  mwd.total_units,
  mwd.selling_days,
  mwd.period_days,
  ROUND(SAFE_DIVIDE(mwd.total_units, NULLIF(mwd.period_days, 0)), 2) AS daily_rate,
  ROUND(SAFE_DIVIDE(
    SAFE_DIVIDE(mwd.total_units, NULLIF(mwd.period_days, 0)),
    NULLIF(m2.daily_rate, 0)
  ), 3) AS ramp_index,
  fyt.year1_units
FROM monthly_with_days mwd
LEFT JOIN month2_rate m2 ON mwd.product = m2.product
LEFT JOIN first_year_total fyt ON mwd.product = fyt.product
WHERE mwd.month_num BETWEEN 1 AND 12
  AND mwd.total_units > 0;
