CREATE OR REPLACE VIEW `onyga-482313.OI.V_HOUSE_SEASONALITY` AS
-- House seasonality: volume-weighted calendar-month index blended across
-- "mature" products (>=540 days of history, i.e. two-ish annual cycles so each
-- calendar month is sampled at a settled age, not mid-launch). Serves as the
-- fallback "real calendar" for new-product forecasting whose donor is too young
-- to define its own seasonality. num_days>=15 drops launch-exclusion remnant months.
-- Index = month_daily_rate / annual_daily_rate (1.0 = average month).
-- Consumed by V_LAUNCH_RAMP and V_FORECAST_DEMAND (Phase 1 & 2).
WITH mature_family AS (
  SELECT family
  FROM `onyga-482313.OI.T_UNIFIED_DAILY`
  WHERE units > 0 AND family IS NOT NULL
  GROUP BY 1
  HAVING DATE_DIFF(CURRENT_DATE(), MIN(date), DAY) >= 540
),
mature_months AS (
  SELECT si.calendar_month, si.total_units, si.num_days
  FROM `onyga-482313.OI.V_PRODUCT_SEASONALITY_INDEX` si
  JOIN mature_family mf ON si.family = mf.family
  WHERE si.num_days >= 15
),
blend AS (
  SELECT calendar_month,
    SAFE_DIVIDE(SUM(total_units), SUM(num_days)) AS daily_rate
  FROM mature_months
  GROUP BY 1
),
annual AS (
  SELECT SAFE_DIVIDE(SUM(total_units), SUM(num_days)) AS annual_daily_rate
  FROM mature_months
)
SELECT b.calendar_month,
  ROUND(SAFE_DIVIDE(b.daily_rate, a.annual_daily_rate), 4) AS house_season_index
FROM blend b, annual a
ORDER BY b.calendar_month;
