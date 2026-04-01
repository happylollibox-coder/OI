-- =============================================
-- OI Database Project - V_SEASONAL_INDEX_WEEKLY View
-- =============================================
--
-- Purpose: Weekly seasonal index per week-of-year, derived from the reference ASIN
--          (B0C1VLXYBP) full 2025 historical data from SQP.
--          Index = 1.0 for an average week. > 1 means above-average demand, < 1 below.
--          Used to seasonally adjust experiment baselines so that holiday-peak baselines
--          don't produce misleading negative lifts in post-holiday periods.
--
-- Source: FACT_AMAZON_SEARCH_PERFORMANCE_WEEKLY (B0C1VLXYBP, 2025), DIM_US_HOLIDAYS
-- Consumers: SP_EXPERIMENT_DAILY_SNAPSHOT, V_EXPERIMENT_RESULTS_ASIN,
--            V_EXPERIMENT_RESULTS_SEARCH_TERM
-- Project: onyga-482313
-- Dataset: OI
--
-- Reference ASIN B0C1VLXYBP chosen because:
--   - Full 52 weeks of 2025 data
--   - Gift product with clear seasonal peaks (Valentine's, Easter, Mother's Day, Christmas)
--   - Representative of the overall product catalog demand pattern
--
-- =============================================

CREATE OR REPLACE VIEW `onyga-482313.OI.V_SEASONAL_INDEX_WEEKLY`
AS
WITH reference_weekly AS (
  -- Sum ORDERS per week across all search queries for the reference ASIN
  SELECT
    Reporting_Date,
    SUM(ORDERS) as weekly_orders
  FROM `onyga-482313.OI.FACT_AMAZON_SEARCH_PERFORMANCE_WEEKLY`
  WHERE ASIN = 'B0C1VLXYBP'
    AND EXTRACT(YEAR FROM Reporting_Date) = 2025
  GROUP BY Reporting_Date
),
annual_avg AS (
  SELECT
    AVG(weekly_orders) as avg_weekly_orders,
    SUM(weekly_orders) as total_year_orders
  FROM reference_weekly
),
-- Nearest holiday for each week (using range join, no correlated subquery)
nearest_holidays AS (
  SELECT
    r.Reporting_Date,
    h.holiday_name,
    h.holiday_date,
    h.pre_season_start,
    h.category as holiday_category,
    ABS(DATE_DIFF(r.Reporting_Date, h.holiday_date, DAY)) as days_from_holiday,
    ROW_NUMBER() OVER (PARTITION BY r.Reporting_Date ORDER BY ABS(DATE_DIFF(r.Reporting_Date, h.holiday_date, DAY))) as rn,
    -- Season phase logic
    CASE
      WHEN r.Reporting_Date BETWEEN h.pre_season_start AND DATE_SUB(h.holiday_date, INTERVAL 7 DAY) THEN 'RAMP_UP'
      WHEN r.Reporting_Date BETWEEN DATE_SUB(h.holiday_date, INTERVAL 6 DAY) AND h.holiday_date THEN 'PEAK'
      WHEN r.Reporting_Date BETWEEN DATE_ADD(h.holiday_date, INTERVAL 1 DAY) AND DATE_ADD(h.holiday_date, INTERVAL 14 DAY) THEN 'POST_HOLIDAY'
      ELSE 'NORMAL'
    END as season_phase
  FROM reference_weekly r
  LEFT JOIN `onyga-482313.OI.DIM_US_HOLIDAYS` h
    ON EXTRACT(YEAR FROM h.holiday_date) = 2025
    AND ABS(DATE_DIFF(r.Reporting_Date, h.holiday_date, DAY)) <= 42
)
SELECT
  r.Reporting_Date as reference_date,
  -- ISO week number for cross-year matching (2026 dates map to same week-of-year)
  EXTRACT(ISOWEEK FROM r.Reporting_Date) as iso_week,
  -- Week boundaries: SQP week ends on Saturday (Reporting_Date), starts 6 days prior (Sunday)
  DATE_SUB(r.Reporting_Date, INTERVAL 6 DAY) as week_start,
  r.Reporting_Date as week_end,

  r.weekly_orders as reference_weekly_orders,
  ROUND(r.weekly_orders / 7.0, 2) as reference_daily_orders,
  ROUND(a.avg_weekly_orders, 2) as annual_avg_weekly_orders,
  ROUND(a.avg_weekly_orders / 7.0, 2) as annual_avg_daily_orders,

  -- THE KEY METRIC: seasonal index (1.0 = average week)
  ROUND(SAFE_DIVIDE(r.weekly_orders, a.avg_weekly_orders), 4) as seasonal_index,

  -- Holiday context
  nh.holiday_name as nearest_holiday,
  nh.days_from_holiday as days_from_nearest_holiday,
  COALESCE(nh.season_phase, 'NORMAL') as season_phase

FROM reference_weekly r
CROSS JOIN annual_avg a
LEFT JOIN nearest_holidays nh
  ON r.Reporting_Date = nh.Reporting_Date AND nh.rn = 1;
