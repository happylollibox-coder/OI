-- =============================================
-- OI Database Project - SP_UPDATE_DIM_TIME_TRAFFIC_MULTIPLIERS
-- =============================================
--
-- Purpose: Update DIM_TIME with traffic multiplier fields from V_TRAFFIC_MULTIPLIER_WEEKLY
--          Uses 2025 view data as template, replicates to all years by week ordinal
-- Project: onyga-482313
-- Dataset: OI
--
-- Run after: ALTER TABLE to add columns (if not exists)
--
-- =============================================

CREATE OR REPLACE PROCEDURE `onyga-482313.OI.SP_UPDATE_DIM_TIME_TRAFFIC_MULTIPLIERS`()
OPTIONS (
  description = "Update DIM_TIME traffic multiplier columns from V_TRAFFIC_MULTIPLIER_WEEKLY for all years"
)
BEGIN
  -- Step 1: Add columns if they don't exist (BigQuery doesn't support IF NOT EXISTS for columns,
  -- so run ALTER TABLE separately first if needed)

  -- Step 2: Update DIM_TIME with multipliers for all years
  -- Uses 2025 view data as template; matches by week ordinal within year
  UPDATE `onyga-482313.OI.DIM_TIME` AS td
  SET
    traffic_multiplier = m.TRAFFIC_MULTIPLIER_END_OF_YEAR,
    TRAFFIC_MULTIPLIER_THIS_WEEK = m.TRAFFIC_MULTIPLIER_THIS_WEEK,
    TRAFFIC_MULTIPLIER_NEXT_WEEK = m.TRAFFIC_MULTIPLIER_NEXT_WEEK,
    TRAFFIC_MULTIPLIER_NEXT_MONTH = m.TRAFFIC_MULTIPLIER_NEXT_MONTH,
    TRAFFIC_MULTIPLIER_NEXT_3_MONTH = m.TRAFFIC_MULTIPLIER_NEXT_3_MONTH,
    TRAFFIC_MULTIPLIER_END_OF_YEAR = m.TRAFFIC_MULTIPLIER_END_OF_YEAR
  FROM (
    WITH view_2025 AS (
      SELECT
        ROW_NUMBER() OVER (ORDER BY Reporting_Date) AS week_ordinal,
        TRAFFIC_MULTIPLIER_THIS_WEEK,
        TRAFFIC_MULTIPLIER_NEXT_WEEK,
        TRAFFIC_MULTIPLIER_NEXT_MONTH,
        TRAFFIC_MULTIPLIER_NEXT_3_MONTH,
        TRAFFIC_MULTIPLIER_END_OF_YEAR
      FROM `onyga-482313.OI.V_TRAFFIC_MULTIPLIER_WEEKLY`
    ),
    dim_weeks AS (
      SELECT year, week_end_date,
        ROW_NUMBER() OVER (PARTITION BY year ORDER BY week_end_date) AS week_ordinal
      FROM (
        SELECT DISTINCT year, week_end_date
        FROM `onyga-482313.OI.DIM_TIME`
        WHERE week_end_date IS NOT NULL
      )
    )
    SELECT
      dw.year,
      dw.week_end_date,
      v.TRAFFIC_MULTIPLIER_THIS_WEEK,
      v.TRAFFIC_MULTIPLIER_NEXT_WEEK,
      v.TRAFFIC_MULTIPLIER_NEXT_MONTH,
      v.TRAFFIC_MULTIPLIER_NEXT_3_MONTH,
      v.TRAFFIC_MULTIPLIER_END_OF_YEAR
    FROM dim_weeks dw
    INNER JOIN view_2025 v ON dw.week_ordinal = v.week_ordinal
  ) AS m
  WHERE td.year = m.year AND td.week_end_date = m.week_end_date;

  SELECT 'SP_UPDATE_DIM_TIME_TRAFFIC_MULTIPLIERS completed successfully' AS status;
END;
