-- V_PRODUCT_SEASONALITY_INDEX — Calendar-month seasonality per product
-- Computes how each calendar month compares to the annual average.
-- Index = 1.0 means average, 2.5 means 2.5x the average (e.g. December peak).
--
-- Used by: V_FORECAST_DEMAND (Phase 1 & Phase 2 — seasonal multiplication)
--
-- Design decisions:
--   1. Uses all available history (not just year 1) for best seasonal signal
--   2. Excludes first 60 days of each product's life (launch ramp noise)
--   3. Only products with ≥365 days of history qualify (need a full annual cycle)
--   4. Index = month_daily_rate / avg_daily_rate (avoids month-length bias)
--
-- Invariant #8: All business logic in SQL.

CREATE OR REPLACE VIEW `onyga-482313.OI.V_PRODUCT_SEASONALITY_INDEX` AS

WITH first_sales AS (
  SELECT
    product_short_name AS product,
    family,
    MIN(date) AS first_sale_date
  FROM `onyga-482313.OI.T_UNIFIED_DAILY`
  WHERE units > 0
    AND product_short_name IS NOT NULL
  GROUP BY 1, 2
  HAVING DATE_DIFF(CURRENT_DATE(), MIN(date), DAY) >= 365
),

-- Daily sales excluding first 60 days (launch noise)
daily_sales AS (
  SELECT
    fs.product,
    fs.family,
    u.date,
    EXTRACT(MONTH FROM u.date) AS calendar_month,
    SUM(u.units) AS units
  FROM first_sales fs
  JOIN `onyga-482313.OI.T_UNIFIED_DAILY` u
    ON fs.product = u.product_short_name
  WHERE u.date >= DATE_ADD(fs.first_sale_date, INTERVAL 60 DAY)
    AND u.units > 0
  GROUP BY 1, 2, 3, 4
),

-- Monthly aggregates: daily rate per calendar month
monthly_rates AS (
  SELECT
    product, family, calendar_month,
    SUM(units) AS total_units,
    COUNT(DISTINCT date) AS num_days,
    SAFE_DIVIDE(SUM(units), COUNT(DISTINCT date)) AS daily_rate
  FROM daily_sales
  GROUP BY 1, 2, 3
),

-- Annual average daily rate per product
annual_avg AS (
  SELECT
    product,
    SAFE_DIVIDE(SUM(total_units), SUM(num_days)) AS avg_daily_rate
  FROM monthly_rates
  GROUP BY 1
)

SELECT
  mr.product,
  mr.family,
  mr.calendar_month,
  mr.total_units,
  mr.num_days,
  ROUND(mr.daily_rate, 2) AS daily_rate,
  ROUND(aa.avg_daily_rate, 2) AS avg_daily_rate,
  -- Seasonality index: this month vs annual average
  ROUND(SAFE_DIVIDE(mr.daily_rate, NULLIF(aa.avg_daily_rate, 0)), 3) AS seasonality_index
FROM monthly_rates mr
JOIN annual_avg aa ON mr.product = aa.product;
