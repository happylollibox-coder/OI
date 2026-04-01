-- =============================================
-- Consolidated Ecommerce Time Dimension Usage
-- =============================================
--
-- Examples using the consolidated design with accumulation
--
-- =============================================

-- ==========================================
-- DAILY ANALYSIS WITH CONSOLIDATED FIELDS
-- ==========================================

-- Example 1: All holidays in a year with descriptions
SELECT
  full_date,
  holiday_description,
  holiday_category,
  holiday_importance,
  peak_period_description,
  peak_intensity_level,
  expected_traffic_level
FROM `onyga-482313.OI.TimeDIM`
WHERE is_holiday = TRUE AND year = 2024
ORDER BY full_date;

-- Example 2: Peak selling periods analysis
SELECT
  peak_period_category,
  COUNT(*) as days_in_period,
  AVG(traffic_multiplier) as avg_traffic,
  MAX(traffic_multiplier) as peak_traffic,
  STRING_AGG(DISTINCT peak_period_description, ' | ') as period_examples
FROM `onyga-482313.OI.TimeDIM`
WHERE is_peak_selling_period = TRUE AND year = 2024
GROUP BY peak_period_category
ORDER BY days_in_period DESC;

-- ==========================================
-- WEEKLY ACCUMULATION ANALYSIS
-- ==========================================

-- Example 3: Weekly rollup for operational planning
SELECT
  week_key,
  week_start_date,
  week_end_date,
  month_name,
  CASE
    WHEN has_holiday THEN CONCAT('Holiday Week: ', holiday_descriptions)
    WHEN has_peak_period THEN CONCAT('Peak Week: ', peak_period_descriptions)
    ELSE 'Regular Week'
  END as week_characterization,
  max_peak_intensity,
  avg_traffic_multiplier,
  requires_extra_staffing,
  requires_inventory_boost
FROM `onyga-482313.OI.v_ecommerce_weekly_rollup`
WHERE year = 2024
ORDER BY week_start_date;

-- Example 4: Critical weeks requiring action
SELECT
  week_key,
  week_start_date,
  holiday_descriptions,
  peak_period_descriptions,
  avg_traffic_multiplier,
  CASE
    WHEN requires_extra_staffing AND requires_inventory_boost THEN 'HIGH PRIORITY'
    WHEN requires_extra_staffing OR requires_inventory_boost THEN 'MEDIUM PRIORITY'
    ELSE 'NORMAL'
  END as priority_level
FROM `onyga-482313.OI.v_ecommerce_weekly_rollup`
WHERE (requires_extra_staffing = TRUE OR requires_inventory_boost = TRUE)
  AND year = 2024
ORDER BY avg_traffic_multiplier DESC;

-- ==========================================
-- MONTHLY ACCUMULATION ANALYSIS
-- ==========================================

-- Example 5: Monthly business review
SELECT
  month_key,
  month_name,
  year,
  all_holiday_descriptions,
  all_peak_descriptions,
  critical_shipping_days,
  extra_staffing_days,
  ROUND(avg_monthly_traffic_multiplier, 2) as avg_traffic,
  CASE
    WHEN max_traffic_multiplier > 2.0 THEN 'Exceptional'
    WHEN max_traffic_multiplier > 1.5 THEN 'Strong'
    WHEN max_traffic_multiplier > 1.2 THEN 'Good'
    ELSE 'Normal'
  END as monthly_performance_rating
FROM `onyga-482313.OI.v_ecommerce_monthly_rollup`
WHERE year = 2024
ORDER BY month;

-- Example 6: Holiday impact analysis
SELECT
  month_name,
  holiday_categories,
  number_of_holidays,
  max_holiday_importance,
  total_season_days,
  ROUND(high_activity_ratio * 100, 1) as high_activity_percentage,
  CASE
    WHEN max_holiday_importance >= 4 THEN 'Major Impact'
    WHEN max_holiday_importance >= 3 THEN 'Significant Impact'
    ELSE 'Minor Impact'
  END as business_impact
FROM `onyga-482313.OI.v_ecommerce_monthly_rollup`
WHERE has_holidays = TRUE AND year = 2024
ORDER BY max_holiday_importance DESC;

-- ==========================================
-- QUARTERLY ACCUMULATION ANALYSIS
-- ==========================================

-- Example 7: Quarterly planning and forecasting
SELECT
  quarter_key,
  year,
  quarter,
  unique_holidays,
  unique_peak_periods,
  ROUND(avg_quarterly_traffic, 2) as avg_traffic,
  ROUND(high_activity_ratio * 100, 1) as high_activity_days_pct,
  total_extra_staffing_days,
  CASE
    WHEN high_activity_ratio > 0.3 THEN 'High Season Quarter'
    WHEN high_activity_ratio > 0.15 THEN 'Moderate Season Quarter'
    ELSE 'Low Season Quarter'
  END as seasonality_classification
FROM `onyga-482313.OI.v_ecommerce_quarterly_rollup`
WHERE year >= 2023
ORDER BY quarter_key;

-- ==========================================
-- HOLIDAY SEASON ACCUMULATION
-- ==========================================

-- Example 8: Holiday season comparison
SELECT
  holiday_season_key,
  holidays_in_season,
  number_of_holidays,
  ROUND(avg_season_traffic, 2) as avg_traffic,
  ROUND(peak_season_traffic, 2) as peak_traffic,
  critical_shipping_days,
  staffing_requirement_days,
  ROUND(high_traffic_day_ratio * 100, 1) as high_traffic_pct
FROM `onyga-482313.OI.v_ecommerce_holiday_season_rollup`
WHERE year >= 2023
ORDER BY holiday_season_key;

-- Example 9: Year-over-year holiday season comparison
WITH holiday_comparison AS (
  SELECT
    year,
    SUM(CASE WHEN holiday_season_key LIKE '%Holiday%' THEN avg_season_traffic END) as holiday_avg_traffic,
    SUM(CASE WHEN holiday_season_key LIKE '%Christmas%' THEN avg_season_traffic END) as christmas_avg_traffic,
    SUM(staffing_requirement_days) as total_staffing_days,
    SUM(critical_shipping_days) as total_critical_shipping_days
  FROM `onyga-482313.OI.v_ecommerce_holiday_season_rollup`
  GROUP BY year
)
SELECT
  year,
  ROUND(holiday_avg_traffic, 2) as holiday_traffic,
  ROUND(christmas_avg_traffic, 2) as christmas_traffic,
  total_staffing_days,
  total_critical_shipping_days,
  ROUND(
    SAFE_DIVIDE(holiday_avg_traffic - LAG(holiday_avg_traffic) OVER (ORDER BY year), LAG(holiday_avg_traffic) OVER (ORDER BY year)) * 100,
    2
  ) as yoy_holiday_growth_pct
FROM holiday_comparison
ORDER BY year;

-- ==========================================
-- ROLLING PERIOD ANALYSIS
-- ==========================================

-- Example 10: Rolling trend analysis
SELECT
  period_key,
  period_type,
  period_start,
  period_end,
  ROUND(avg_traffic_multiplier, 2) as avg_traffic,
  max_traffic_multiplier,
  total_holidays
FROM `onyga-482313.OI.v_ecommerce_rolling_periods`
WHERE period_type = '7-Day Rolling'
  AND period_start >= '2024-01-01'
ORDER BY period_start DESC
LIMIT 10;

-- Example 11: Current period vs recent trends
WITH current_metrics AS (
  SELECT
    AVG(traffic_multiplier) as current_7day_avg,
    MAX(traffic_multiplier) as current_7day_max
  FROM `onyga-482313.OI.TimeDIM`
  WHERE full_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 6 DAY)
    AND full_date <= CURRENT_DATE()
),
recent_trend AS (
  SELECT
    AVG(avg_traffic_multiplier) as recent_7day_avg,
    AVG(max_traffic_multiplier) as recent_7day_max
  FROM `onyga-482313.OI.v_ecommerce_rolling_periods`
  WHERE period_type = '7-Day Rolling'
    AND period_end BETWEEN DATE_SUB(CURRENT_DATE(), INTERVAL 14 DAY)
                       AND DATE_SUB(CURRENT_DATE(), INTERVAL 8 DAY)
)
SELECT
  ROUND(c.current_7day_avg, 2) as current_avg_traffic,
  ROUND(r.recent_7day_avg, 2) as recent_avg_traffic,
  ROUND(c.current_7day_max, 2) as current_max_traffic,
  ROUND(r.recent_7day_max, 2) as recent_max_traffic,
  ROUND(
    SAFE_DIVIDE(c.current_7day_avg - r.recent_7day_avg, r.recent_7day_avg) * 100,
    2
  ) as traffic_change_pct
FROM current_metrics c
CROSS JOIN recent_trend r;

-- ==========================================
-- BUSINESS JOIN EXAMPLES
-- ==========================================

-- Example 12: Sales performance by consolidated time periods
SELECT
  t.holiday_description,
  t.peak_period_description,
  t.expected_traffic_level,
  COUNT(f.order_id) as orders,
  SUM(f.revenue) as revenue,
  ROUND(AVG(f.revenue), 2) as avg_order_value,
  ROUND(SUM(f.revenue) / NULLIF(t.traffic_multiplier, 0), 2) as normalized_revenue
FROM `onyga-482313.OI.fact_sales` f
JOIN `onyga-482313.OI.TimeDIM` t
  ON f.date_key = t.date_key
WHERE t.year = 2024
  AND (t.is_holiday = TRUE OR t.is_peak_selling_period = TRUE)
GROUP BY t.holiday_description, t.peak_period_description, t.expected_traffic_level, t.traffic_multiplier
ORDER BY revenue DESC;

-- Example 13: Operational planning dashboard
SELECT
  t.month_name,
  t.business_day_type,
  COUNT(*) as days,
  SUM(CASE WHEN t.requires_extra_staffing THEN 1 ELSE 0 END) as staffing_days,
  SUM(CASE WHEN t.requires_inventory_boost THEN 1 ELSE 0 END) as inventory_days,
  SUM(CASE WHEN t.is_critical_shipping_period THEN 1 ELSE 0 END) as critical_shipping_days,
  ROUND(AVG(t.traffic_multiplier), 2) as avg_traffic_multiplier
FROM `onyga-482313.OI.TimeDIM` t
WHERE t.year = 2024
GROUP BY t.month_name, t.business_day_type
ORDER BY t.month_name, business_day_type;
