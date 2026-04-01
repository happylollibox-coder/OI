-- =============================================
-- Simple Population of TimeDIM Table
-- =============================================
--
-- Basic population with core date fields and simple ecommerce logic
-- Date range: 2022-01-01 to 2042-12-31
--
-- =============================================

INSERT INTO `onyga-482313.OI.TimeDIM` (
  date_key, full_date, year, quarter, month, day,
  month_name, day_of_week_name, is_weekend, is_weekday,

  -- Simple holiday flags (will expand later)
  is_holiday, holiday_description, holiday_category, holiday_importance,
  is_peak_selling_period, peak_period_description, peak_period_category, peak_intensity_level,

  -- Default values for other fields
  is_special_event, event_description, event_category, event_type,
  is_seasonal_period, season_description, season_category,

  expected_traffic_level, traffic_multiplier, expected_conversion_rate, price_sensitivity,
  is_critical_shipping_period, shipping_description, guaranteed_delivery_days,
  business_day_type, operational_intensity,

  -- Accumulation keys
  week_start_date, week_end_date, week_key, year_week,
  month_start_date, month_end_date, month_key,
  quarter_start_date, quarter_end_date, quarter_key,
  year_start_date, year_end_date, year_key,

  -- Simple keys without year
  holiday_season_key, peak_period_key,

  -- Rolling keys
  rolling_7_day_key, rolling_30_day_key, rolling_90_day_key,

  -- Basic analytics
  days_from_today, is_current_week, is_current_month, is_current_quarter, is_year_to_date,

  -- Metadata
  created_at, updated_at, business_rules_version
)

WITH date_series AS (
  -- Generate dates from 2022 to 2042
  SELECT
    date_day,
    CAST(FORMAT_DATE('%Y%m%d', date_day) AS INT64) as date_key,
    EXTRACT(YEAR FROM date_day) as year,
    EXTRACT(QUARTER FROM date_day) as quarter,
    EXTRACT(MONTH FROM date_day) as month,
    EXTRACT(DAY FROM date_day) as day,
    FORMAT_DATE('%B', date_day) as month_name,
    FORMAT_DATE('%A', date_day) as day_of_week_name,
    EXTRACT(DAYOFWEEK FROM date_day) IN (6, 7) as is_weekend,
    EXTRACT(DAYOFWEEK FROM date_day) NOT IN (6, 7) as is_weekday
  FROM UNNEST(GENERATE_DATE_ARRAY('2022-01-01', '2042-12-31', INTERVAL 1 DAY)) as date_day
),

processed_dates AS (
  SELECT
    ds.*,

    -- Simple holiday detection
    CASE
      WHEN ds.month = 11 AND ds.day = 23 THEN STRUCT(TRUE, 'Thanksgiving', 'Major Holiday', 5)
      WHEN ds.month = 11 AND ds.day = 24 THEN STRUCT(TRUE, 'Black Friday', 'Major Holiday', 5)
      WHEN ds.month = 12 AND ds.day = 25 THEN STRUCT(TRUE, 'Christmas Day', 'Major Holiday', 5)
      WHEN ds.month = 1 AND ds.day = 1 THEN STRUCT(TRUE, 'New Year\'s Day', 'Major Holiday', 4)
      ELSE STRUCT(FALSE, NULL, NULL, NULL)
    END as holiday_info,

    -- Simple peak period detection
    CASE
      WHEN ds.month = 12 AND ds.day BETWEEN 1 AND 25 THEN STRUCT(TRUE, 'December Peak', 'Holiday', 'Very High')
      WHEN ds.month = 11 AND ds.day BETWEEN 15 AND 30 THEN STRUCT(TRUE, 'November Pre-Holiday', 'Holiday', 'High')
      WHEN ds.month = 1 AND ds.day BETWEEN 1 AND 15 THEN STRUCT(TRUE, 'January Post-Holiday', 'Holiday', 'Medium')
      ELSE STRUCT(FALSE, NULL, NULL, NULL)
    END as peak_info,

    -- Accumulation keys (Sunday-starting weeks for North America calendar)
    DATE_TRUNC(ds.date_day, WEEK(SUNDAY)) as week_start_date,
    DATE_ADD(DATE_TRUNC(ds.date_day, WEEK(SUNDAY)), INTERVAL 6 DAY) as week_end_date,
    FORMAT_DATE('%Y%m%d', DATE_TRUNC(ds.date_day, WEEK(SUNDAY))) as week_key,
    CONCAT(
      EXTRACT(YEAR FROM ds.date_day), 
      '-', 
      LPAD(CAST(EXTRACT(WEEK(SUNDAY) FROM ds.date_day) + 1 AS STRING), 2, '0')
    ) as year_week,

    DATE(ds.year, ds.month, 1) as month_start_date,
    LAST_DAY(ds.date_day, MONTH) as month_end_date,
    FORMAT_DATE('%Y-%m', ds.date_day) as month_key,

    DATE(ds.year, (ds.quarter - 1) * 3 + 1, 1) as quarter_start_date,
    LAST_DAY(DATE(ds.year, ds.quarter * 3, 1), QUARTER) as quarter_end_date,
    CONCAT(CAST(ds.year AS STRING), '-Q', CAST(ds.quarter AS STRING)) as quarter_key,

    DATE(ds.year, 1, 1) as year_start_date,
    DATE(ds.year, 12, 31) as year_end_date,
    CAST(ds.year AS STRING) as year_key,

    -- Holiday season key (without year)
    CASE
      WHEN ds.month = 11 AND ds.day >= 15 THEN 'Holiday'
      WHEN ds.month = 12 THEN 'Christmas'
      WHEN ds.month = 1 AND ds.day <= 7 THEN 'Holiday'
      ELSE NULL
    END as holiday_season_key,

    -- Peak period key (without year)
    CASE
      WHEN ds.month = 12 AND ds.day BETWEEN 1 AND 25 THEN 'December-Peak'
      WHEN ds.month = 11 AND ds.day BETWEEN 15 AND 30 THEN 'November-Pre-Holiday'
      WHEN ds.month = 1 AND ds.day BETWEEN 1 AND 15 THEN 'January-Post-Holiday'
      ELSE NULL
    END as peak_period_key,

    -- Rolling keys
    FORMAT_DATE('%Y-%m-%d', ds.date_day) as rolling_7_day_key,
    FORMAT_DATE('%Y-%m-%d', ds.date_day) as rolling_30_day_key,
    FORMAT_DATE('%Y-%m-%d', ds.date_day) as rolling_90_day_key,

    -- Days from today calculation
    DATE_DIFF(CURRENT_DATE(), ds.date_day, DAY) as days_from_today,

    -- Current period flags
    EXTRACT(WEEK FROM ds.date_day) = EXTRACT(WEEK FROM CURRENT_DATE())
    AND EXTRACT(YEAR FROM ds.date_day) = EXTRACT(YEAR FROM CURRENT_DATE()) as is_current_week,

    EXTRACT(MONTH FROM ds.date_day) = EXTRACT(MONTH FROM CURRENT_DATE())
    AND EXTRACT(YEAR FROM ds.date_day) = EXTRACT(YEAR FROM CURRENT_DATE()) as is_current_month,

    EXTRACT(QUARTER FROM ds.date_day) = EXTRACT(QUARTER FROM CURRENT_DATE())
    AND EXTRACT(YEAR FROM ds.date_day) = EXTRACT(YEAR FROM CURRENT_DATE()) as is_current_quarter,

    EXTRACT(YEAR FROM ds.date_day) = EXTRACT(YEAR FROM CURRENT_DATE())
    AND ds.date_day <= CURRENT_DATE() as is_year_to_date

  FROM date_series ds
)

SELECT
  pd.date_key,
  pd.date_day as full_date,
  pd.year, pd.quarter, pd.month, pd.day,
  pd.month_name, pd.day_of_week_name, pd.is_weekend, pd.is_weekday,

  -- Holiday fields
  pd.holiday_info._field1 as is_holiday,
  pd.holiday_info._field2 as holiday_description,
  pd.holiday_info._field3 as holiday_category,
  pd.holiday_info._field4 as holiday_importance,

  -- Peak period fields
  pd.peak_info._field1 as is_peak_selling_period,
  pd.peak_info._field2 as peak_period_description,
  pd.peak_info._field3 as peak_period_category,
  pd.peak_info._field4 as peak_intensity_level,

  -- Default values for other fields
  FALSE as is_special_event,
  NULL as event_description,
  NULL as event_category,
  NULL as event_type,

  FALSE as is_seasonal_period,
  NULL as season_description,
  NULL as season_category,

  -- Basic traffic expectations
  CASE
    WHEN pd.holiday_info._field1 THEN 'High'
    WHEN pd.peak_info._field1 THEN 'High'
    WHEN pd.is_weekend THEN 'Normal'
    ELSE 'Low'
  END as expected_traffic_level,

  CASE
    WHEN pd.holiday_info._field1 THEN 2.0
    WHEN pd.peak_info._field1 THEN 1.5
    WHEN pd.is_weekend THEN 1.2
    ELSE 1.0
  END as traffic_multiplier,

  CASE
    WHEN pd.holiday_info._field1 THEN 0.035
    WHEN pd.peak_info._field1 THEN 0.032
    WHEN pd.is_weekend THEN 0.028
    ELSE 0.025
  END as expected_conversion_rate,

  CASE
    WHEN pd.month IN (11,12) THEN 'Low'
    ELSE 'High'
  END as price_sensitivity,

  -- Shipping (simplified)
  CASE WHEN pd.month = 12 AND pd.day BETWEEN 15 AND 24 THEN TRUE ELSE FALSE END as is_critical_shipping_period,
  CASE WHEN pd.month = 12 AND pd.day BETWEEN 15 AND 24 THEN 'Pre-Christmas Shipping' ELSE NULL END as shipping_description,
  CASE WHEN pd.month = 12 AND pd.day <= 20 THEN 5 ELSE NULL END as guaranteed_delivery_days,

  -- Business classification
  CASE
    WHEN pd.holiday_info._field1 THEN 'Holiday'
    WHEN pd.peak_info._field1 THEN 'Peak'
    WHEN pd.is_weekend THEN 'Weekend'
    ELSE 'Regular'
  END as business_day_type,

  'Standard' as operational_intensity,

  -- Accumulation keys
  pd.week_start_date, pd.week_end_date, pd.week_key, pd.year_week,
  pd.month_start_date, pd.month_end_date, pd.month_key,
  pd.quarter_start_date, pd.quarter_end_date, pd.quarter_key,
  pd.year_start_date, pd.year_end_date, pd.year_key,

  pd.holiday_season_key,
  pd.peak_period_key,

  pd.rolling_7_day_key, pd.rolling_30_day_key, pd.rolling_90_day_key,

  -- Analytics
  pd.days_from_today, pd.is_current_week, pd.is_current_month, pd.is_current_quarter, pd.is_year_to_date,

  FALSE as requires_extra_staffing,
  FALSE as requires_inventory_boost,
  FALSE as high_risk_return_period,

  -- Metadata
  CURRENT_TIMESTAMP() as created_at,
  CURRENT_TIMESTAMP() as updated_at,
  'v1.0-simple' as business_rules_version

FROM processed_dates pd;
