-- =============================================
-- OI Database Project - SP_POPULATE_DIM_TIME
-- =============================================
--
-- Purpose: Populate DIM_TIME with date dimension data (2022-01-01 to 2042-12-31)
-- Method: TRUNCATE + INSERT (full refresh)
-- Source: Generated date series with ecommerce business logic
-- Project: onyga-482313
-- Dataset: OI
--
-- =============================================

CREATE OR REPLACE PROCEDURE `onyga-482313.OI.SP_POPULATE_DIM_TIME`()
OPTIONS (
  description = "Populate DIM_TIME with date dimension data. TRUNCATE + INSERT. Date range: 2022-01-01 to 2042-12-31."
)
BEGIN
  DECLARE record_count INT64 DEFAULT 0;
  DECLARE start_time TIMESTAMP;
  DECLARE end_time TIMESTAMP;

  SET start_time = CURRENT_TIMESTAMP();

  -- Step 1: TRUNCATE the dimension table
  TRUNCATE TABLE `onyga-482313.OI.DIM_TIME`;

  -- Step 2: INSERT date dimension data
  INSERT INTO `onyga-482313.OI.DIM_TIME` (
    date_key, full_date, year, quarter, month, day,
    month_name, day_of_week_name, is_weekend, is_weekday,

    is_holiday, holiday_description, holiday_category, holiday_importance,
    is_peak_selling_period, peak_period_description, peak_period_category, peak_intensity_level,

    is_special_event, event_description, event_category, event_type,
    is_seasonal_period, season_description, season_category,

    expected_traffic_level, traffic_multiplier, expected_conversion_rate, price_sensitivity,
    is_critical_shipping_period, shipping_description, guaranteed_delivery_days,
    business_day_type, operational_intensity,

    week_start_date, week_end_date, week_key, year_week,
    month_start_date, month_end_date, month_key,
    quarter_start_date, quarter_end_date, quarter_key,
    year_start_date, year_end_date, year_key,

    holiday_season_key, holiday_season_start_date, holiday_season_end_date,
    peak_period_key, peak_period_start_date, peak_period_end_date,

    rolling_7_day_key, rolling_30_day_key, rolling_90_day_key,

    days_from_today, is_current_week, is_current_month, is_current_quarter, is_year_to_date,

    requires_extra_staffing, requires_inventory_boost, high_risk_return_period,

    created_at, updated_at, business_rules_version,

    occasion_valentines_phase, occasion_easter_phase,
    occasion_christmas_phase, occasion_back_to_school_phase
  )
  WITH date_series AS (
    SELECT
      date_day,
      CAST(FORMAT_DATE('%Y%m%d', date_day) AS INT64) AS date_key,
      EXTRACT(YEAR FROM date_day) AS year,
      EXTRACT(QUARTER FROM date_day) AS quarter,
      EXTRACT(MONTH FROM date_day) AS month,
      EXTRACT(DAY FROM date_day) AS day,
      FORMAT_DATE('%B', date_day) AS month_name,
      FORMAT_DATE('%A', date_day) AS day_of_week_name,
      EXTRACT(DAYOFWEEK FROM date_day) IN (6, 7) AS is_weekend,
      EXTRACT(DAYOFWEEK FROM date_day) NOT IN (6, 7) AS is_weekday
    FROM UNNEST(GENERATE_DATE_ARRAY('2022-01-01', '2042-12-31', INTERVAL 1 DAY)) AS date_day
  ),

  -- Occasion peak phases: join DIM_US_HOLIDAYS to compute phase per occasion per date
  -- Maps each occasion to the closest year's holiday entry
  -- Phase logic: PRE_PEAK → BOOST → PEAK → POST_PEAK → OFF_SEASON
  occasion_phases AS (
    SELECT
      ds.date_day,
      MAX(CASE WHEN ohm.occasion = 'VALENTINES' THEN
        CASE
          WHEN ds.date_day >= h.pre_season_start AND ds.date_day < h.boost_start THEN 'PRE_PEAK'
          WHEN ds.date_day >= h.boost_start AND ds.date_day < h.peak_start THEN 'BOOST'
          WHEN ds.date_day >= h.peak_start AND ds.date_day < DATE_SUB(h.holiday_date, INTERVAL 2 DAY) THEN 'PEAK'
          WHEN ds.date_day >= DATE_SUB(h.holiday_date, INTERVAL 2 DAY) AND ds.date_day <= DATE_ADD(h.holiday_date, INTERVAL 14 DAY) THEN 'POST_PEAK'
          ELSE 'OFF_SEASON'
        END
      END) as valentines_phase,
      MAX(CASE WHEN ohm.occasion = 'EASTER' THEN
        CASE
          WHEN ds.date_day >= h.pre_season_start AND ds.date_day < h.boost_start THEN 'PRE_PEAK'
          WHEN ds.date_day >= h.boost_start AND ds.date_day < h.peak_start THEN 'BOOST'
          WHEN ds.date_day >= h.peak_start AND ds.date_day < DATE_SUB(h.holiday_date, INTERVAL 2 DAY) THEN 'PEAK'
          WHEN ds.date_day >= DATE_SUB(h.holiday_date, INTERVAL 2 DAY) AND ds.date_day <= DATE_ADD(h.holiday_date, INTERVAL 14 DAY) THEN 'POST_PEAK'
          ELSE 'OFF_SEASON'
        END
      END) as easter_phase,
      MAX(CASE WHEN ohm.occasion = 'CHRISTMAS' THEN
        CASE
          WHEN ds.date_day >= h.pre_season_start AND ds.date_day < h.boost_start THEN 'PRE_PEAK'
          WHEN ds.date_day >= h.boost_start AND ds.date_day < h.peak_start THEN 'BOOST'
          WHEN ds.date_day >= h.peak_start AND ds.date_day < DATE_SUB(h.holiday_date, INTERVAL 2 DAY) THEN 'PEAK'
          WHEN ds.date_day >= DATE_SUB(h.holiday_date, INTERVAL 2 DAY) AND ds.date_day <= DATE_ADD(h.holiday_date, INTERVAL 14 DAY) THEN 'POST_PEAK'
          ELSE 'OFF_SEASON'
        END
      END) as christmas_phase,
      MAX(CASE WHEN ohm.occasion = 'BACK_TO_SCHOOL' THEN
        CASE
          WHEN ds.date_day >= h.pre_season_start AND ds.date_day < h.boost_start THEN 'PRE_PEAK'
          WHEN ds.date_day >= h.boost_start AND ds.date_day < h.peak_start THEN 'BOOST'
          WHEN ds.date_day >= h.peak_start AND ds.date_day < DATE_SUB(h.holiday_date, INTERVAL 2 DAY) THEN 'PEAK'
          WHEN ds.date_day >= DATE_SUB(h.holiday_date, INTERVAL 2 DAY) AND ds.date_day <= DATE_ADD(h.holiday_date, INTERVAL 14 DAY) THEN 'POST_PEAK'
          ELSE 'OFF_SEASON'
        END
      END) as back_to_school_phase
    FROM (SELECT date_day FROM UNNEST(GENERATE_DATE_ARRAY('2022-01-01', '2042-12-31', INTERVAL 1 DAY)) AS date_day) ds
    CROSS JOIN (
      SELECT 'VALENTINES' as occasion, 'Valentines Day' as holiday_name UNION ALL
      SELECT 'EASTER', 'Easter' UNION ALL
      SELECT 'CHRISTMAS', 'Christmas' UNION ALL
      SELECT 'BACK_TO_SCHOOL', 'Back to School'
    ) ohm
    LEFT JOIN `onyga-482313.OI.DIM_US_HOLIDAYS` h
      ON ohm.holiday_name = h.holiday_name
      AND ds.date_day >= DATE_SUB(h.pre_season_start, INTERVAL 30 DAY)
      AND ds.date_day <= DATE_ADD(h.holiday_date, INTERVAL 30 DAY)
    GROUP BY 1
  ),

  processed_dates AS (
    SELECT
      ds.*,
      CASE
        WHEN ds.month = 11 AND ds.day = 23 THEN STRUCT(TRUE AS b, 'Thanksgiving' AS d, 'Major Holiday' AS c, 5 AS i)
        WHEN ds.month = 11 AND ds.day = 24 THEN STRUCT(TRUE AS b, 'Black Friday' AS d, 'Major Holiday' AS c, 5 AS i)
        WHEN ds.month = 12 AND ds.day = 25 THEN STRUCT(TRUE AS b, 'Christmas Day' AS d, 'Major Holiday' AS c, 5 AS i)
        WHEN ds.month = 1 AND ds.day = 1 THEN STRUCT(TRUE AS b, 'New Years Day' AS d, 'Major Holiday' AS c, 4 AS i)
        ELSE STRUCT(FALSE AS b, CAST(NULL AS STRING) AS d, CAST(NULL AS STRING) AS c, CAST(NULL AS INT64) AS i)
      END AS holiday_info,
      CASE
        WHEN ds.month = 12 AND ds.day BETWEEN 1 AND 25 THEN STRUCT(TRUE AS b, 'December Peak' AS d, 'Holiday' AS c, 'Very High' AS l)
        WHEN ds.month = 11 AND ds.day BETWEEN 15 AND 30 THEN STRUCT(TRUE AS b, 'November Pre-Holiday' AS d, 'Holiday' AS c, 'High' AS l)
        WHEN ds.month = 1 AND ds.day BETWEEN 1 AND 15 THEN STRUCT(TRUE AS b, 'January Post-Holiday' AS d, 'Holiday' AS c, 'Medium' AS l)
        ELSE STRUCT(FALSE AS b, CAST(NULL AS STRING) AS d, CAST(NULL AS STRING) AS c, CAST(NULL AS STRING) AS l)
      END AS peak_info,
      DATE_TRUNC(ds.date_day, WEEK(SUNDAY)) AS week_start_date,
      DATE_ADD(DATE_TRUNC(ds.date_day, WEEK(SUNDAY)), INTERVAL 6 DAY) AS week_end_date,
      FORMAT_DATE('%Y%m%d', DATE_TRUNC(ds.date_day, WEEK(SUNDAY))) AS week_key,
      CONCAT(
        EXTRACT(YEAR FROM ds.date_day),
        '-',
        LPAD(CAST(EXTRACT(WEEK(SUNDAY) FROM ds.date_day) + 1 AS STRING), 2, '0')
      ) AS year_week,
      DATE(ds.year, ds.month, 1) AS month_start_date,
      LAST_DAY(ds.date_day, MONTH) AS month_end_date,
      FORMAT_DATE('%Y-%m', ds.date_day) AS month_key,
      DATE(ds.year, (ds.quarter - 1) * 3 + 1, 1) AS quarter_start_date,
      LAST_DAY(DATE(ds.year, ds.quarter * 3, 1), QUARTER) AS quarter_end_date,
      CONCAT(CAST(ds.year AS STRING), '-Q', CAST(ds.quarter AS STRING)) AS quarter_key,
      DATE(ds.year, 1, 1) AS year_start_date,
      DATE(ds.year, 12, 31) AS year_end_date,
      CAST(ds.year AS STRING) AS year_key,
      CASE
        WHEN ds.month = 11 AND ds.day >= 15 THEN 'Holiday'
        WHEN ds.month = 12 THEN 'Christmas'
        WHEN ds.month = 1 AND ds.day <= 7 THEN 'Holiday'
        ELSE NULL
      END AS holiday_season_key,
      CASE
        WHEN ds.month = 12 AND ds.day BETWEEN 1 AND 25 THEN 'December-Peak'
        WHEN ds.month = 11 AND ds.day BETWEEN 15 AND 30 THEN 'November-Pre-Holiday'
        WHEN ds.month = 1 AND ds.day BETWEEN 1 AND 15 THEN 'January-Post-Holiday'
        ELSE NULL
      END AS peak_period_key,
      FORMAT_DATE('%Y-%m-%d', ds.date_day) AS rolling_7_day_key,
      FORMAT_DATE('%Y-%m-%d', ds.date_day) AS rolling_30_day_key,
      FORMAT_DATE('%Y-%m-%d', ds.date_day) AS rolling_90_day_key,
      DATE_DIFF(CURRENT_DATE(), ds.date_day, DAY) AS days_from_today,
      (EXTRACT(WEEK(SUNDAY) FROM ds.date_day) = EXTRACT(WEEK(SUNDAY) FROM CURRENT_DATE())
       AND EXTRACT(YEAR FROM ds.date_day) = EXTRACT(YEAR FROM CURRENT_DATE())) AS is_current_week,
      (EXTRACT(MONTH FROM ds.date_day) = EXTRACT(MONTH FROM CURRENT_DATE())
       AND EXTRACT(YEAR FROM ds.date_day) = EXTRACT(YEAR FROM CURRENT_DATE())) AS is_current_month,
      (EXTRACT(QUARTER FROM ds.date_day) = EXTRACT(QUARTER FROM CURRENT_DATE())
       AND EXTRACT(YEAR FROM ds.date_day) = EXTRACT(YEAR FROM CURRENT_DATE())) AS is_current_quarter,
      (EXTRACT(YEAR FROM ds.date_day) = EXTRACT(YEAR FROM CURRENT_DATE())
       AND ds.date_day <= CURRENT_DATE()) AS is_year_to_date
    FROM date_series ds
  )

  SELECT
    pd.date_key,
    pd.date_day AS full_date,
    pd.year, pd.quarter, pd.month, pd.day,
    pd.month_name, pd.day_of_week_name, pd.is_weekend, pd.is_weekday,

    pd.holiday_info.b AS is_holiday,
    pd.holiday_info.d AS holiday_description,
    pd.holiday_info.c AS holiday_category,
    pd.holiday_info.i AS holiday_importance,

    pd.peak_info.b AS is_peak_selling_period,
    pd.peak_info.d AS peak_period_description,
    pd.peak_info.c AS peak_period_category,
    pd.peak_info.l AS peak_intensity_level,

    FALSE AS is_special_event,
    CAST(NULL AS STRING) AS event_description,
    CAST(NULL AS STRING) AS event_category,
    CAST(NULL AS STRING) AS event_type,

    FALSE AS is_seasonal_period,
    CAST(NULL AS STRING) AS season_description,
    CAST(NULL AS STRING) AS season_category,

    CASE
      WHEN pd.holiday_info.b THEN 'High'
      WHEN pd.peak_info.b THEN 'High'
      WHEN pd.is_weekend THEN 'Normal'
      ELSE 'Low'
    END AS expected_traffic_level,

    CASE
      WHEN pd.holiday_info.b THEN 2.0
      WHEN pd.peak_info.b THEN 1.5
      WHEN pd.is_weekend THEN 1.2
      ELSE 1.0
    END AS traffic_multiplier,

    CASE
      WHEN pd.holiday_info.b THEN 0.035
      WHEN pd.peak_info.b THEN 0.032
      WHEN pd.is_weekend THEN 0.028
      ELSE 0.025
    END AS expected_conversion_rate,

    CASE WHEN pd.month IN (11, 12) THEN 'Low' ELSE 'High' END AS price_sensitivity,

    (pd.month = 12 AND pd.day BETWEEN 15 AND 24) AS is_critical_shipping_period,
    CASE WHEN pd.month = 12 AND pd.day BETWEEN 15 AND 24 THEN 'Pre-Christmas Shipping' ELSE CAST(NULL AS STRING) END AS shipping_description,
    CASE WHEN pd.month = 12 AND pd.day <= 20 THEN 5 ELSE CAST(NULL AS INT64) END AS guaranteed_delivery_days,

    CASE
      WHEN pd.holiday_info.b THEN 'Holiday'
      WHEN pd.peak_info.b THEN 'Peak'
      WHEN pd.is_weekend THEN 'Weekend'
      ELSE 'Regular'
    END AS business_day_type,

    'Standard' AS operational_intensity,

    pd.week_start_date, pd.week_end_date, pd.week_key, pd.year_week,
    pd.month_start_date, pd.month_end_date, pd.month_key,
    pd.quarter_start_date, pd.quarter_end_date, pd.quarter_key,
    pd.year_start_date, pd.year_end_date, pd.year_key,

    pd.holiday_season_key,
    CAST(NULL AS DATE) AS holiday_season_start_date,
    CAST(NULL AS DATE) AS holiday_season_end_date,

    pd.peak_period_key,
    CAST(NULL AS DATE) AS peak_period_start_date,
    CAST(NULL AS DATE) AS peak_period_end_date,

    pd.rolling_7_day_key, pd.rolling_30_day_key, pd.rolling_90_day_key,

    pd.days_from_today, pd.is_current_week, pd.is_current_month, pd.is_current_quarter, pd.is_year_to_date,

    FALSE AS requires_extra_staffing,
    FALSE AS requires_inventory_boost,
    FALSE AS high_risk_return_period,

    CURRENT_TIMESTAMP() AS created_at,
    CURRENT_TIMESTAMP() AS updated_at,
    'v2.0-occasion-phases' AS business_rules_version,

    COALESCE(op.valentines_phase, 'OFF_SEASON') AS occasion_valentines_phase,
    COALESCE(op.easter_phase, 'OFF_SEASON') AS occasion_easter_phase,
    COALESCE(op.christmas_phase, 'OFF_SEASON') AS occasion_christmas_phase,
    COALESCE(op.back_to_school_phase, 'OFF_SEASON') AS occasion_back_to_school_phase

  FROM processed_dates pd
  LEFT JOIN occasion_phases op ON pd.date_day = op.date_day;

  SET record_count = @@row_count;
  SET end_time = CURRENT_TIMESTAMP();

  SELECT FORMAT(
    'SP_POPULATE_DIM_TIME completed:\n' ||
    '  Records inserted: %d\n' ||
    '  Duration: %d seconds\n' ||
    '  Completed at: %s',
    record_count,
    TIMESTAMP_DIFF(end_time, start_time, SECOND),
    CAST(end_time AS STRING)
  ) AS operation_summary;
END;
