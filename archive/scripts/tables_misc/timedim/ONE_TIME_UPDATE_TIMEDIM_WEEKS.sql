-- =============================================
-- ONE-TIME UPDATE: TimeDIM Week Fields
-- =============================================
-- Purpose: Update TimeDIM week_start_date, week_end_date, week_key, and year_week
--          to use Sunday-starting weeks (North America calendar)
-- Project: onyga-482313
-- Dataset: OI
-- =============================================

UPDATE `onyga-482313.OI.TimeDIM` AS td
SET
  week_start_date = DATE_TRUNC(td.full_date, WEEK(SUNDAY)),
  week_end_date = DATE_ADD(DATE_TRUNC(td.full_date, WEEK(SUNDAY)), INTERVAL 6 DAY),
  week_key = FORMAT_DATE('%Y%m%d', DATE_TRUNC(td.full_date, WEEK(SUNDAY))),
  year_week = CONCAT(
    EXTRACT(YEAR FROM td.full_date), 
    '-', 
    LPAD(CAST(EXTRACT(WEEK(SUNDAY) FROM td.full_date) + 1 AS STRING), 2, '0')
  ),
  updated_at = CURRENT_TIMESTAMP()
WHERE TRUE;  -- Update all rows

-- =============================================
-- VERIFICATION QUERY
-- =============================================
-- Run this after the update to verify the changes
SELECT
  COUNT(*) AS total_rows,
  COUNT(DISTINCT week_key) AS distinct_weeks,
  COUNT(DISTINCT year_week) AS distinct_year_weeks,
  MIN(week_start_date) AS earliest_week_start,
  MAX(week_end_date) AS latest_week_end,
  MIN(week_key) AS earliest_week_key,
  MAX(week_key) AS latest_week_key,
  MIN(year_week) AS earliest_year_week,
  MAX(year_week) AS latest_year_week
FROM `onyga-482313.OI.TimeDIM`;

-- Sample check: Compare a few dates (including September 7th, 2025)
SELECT
  full_date,
  FORMAT_DATE('%A', full_date) AS day_of_week,
  week_start_date,
  week_end_date,
  week_key,
  year_week,
  FORMAT_DATE('%A', week_start_date) AS week_start_day,
  FORMAT_DATE('%A', week_end_date) AS week_end_day
FROM `onyga-482313.OI.TimeDIM`
WHERE full_date BETWEEN '2025-09-01' AND '2025-09-14'
ORDER BY full_date;
