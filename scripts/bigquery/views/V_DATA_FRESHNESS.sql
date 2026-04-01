-- =============================================
-- OI Database Project - V_DATA_FRESHNESS
-- =============================================
-- Purpose: Single view showing the latest data date for every key table.
--          Used by the dashboard header to show "Data as of..." 
--          and for monitoring/alerting on stale data.
--
-- Grain: One row per data source
-- =============================================

CREATE OR REPLACE VIEW `onyga-482313.OI.V_DATA_FRESHNESS` AS

WITH sources AS (
  -- Ads data freshness
  SELECT 'FACT_AMAZON_ADS' AS source_name,
         'Ads Performance' AS display_name,
         MAX(date) AS latest_date,
         COUNT(*) AS total_rows
  FROM `onyga-482313.OI.FACT_AMAZON_ADS`

  UNION ALL

  -- SQP data freshness
  SELECT 'SRC_ACC_SQP_WEEKLY',
         'Search Query Performance',
         MAX(reporting_date),
         COUNT(*)
  FROM `onyga-482313.OI.SRC_ACC_SQP_WEEKLY`

  UNION ALL

  -- Performance daily
  SELECT 'FACT_AMAZON_PERFORMANCE_DAILY',
         'Amazon Performance',
         MAX(date),
         COUNT(*)
  FROM `onyga-482313.OI.FACT_AMAZON_PERFORMANCE_DAILY`

  UNION ALL

  -- Experiment snapshots
  SELECT 'FACT_EXPERIMENT_DAILY',
         'Experiment Snapshots',
         MAX(snapshot_date),
         COUNT(*)
  FROM `onyga-482313.OI.FACT_EXPERIMENT_DAILY`

  UNION ALL

  -- Search performance weekly
  SELECT 'FACT_AMAZON_SEARCH_PERFORMANCE_WEEKLY',
         'Search Performance',
         MAX(Reporting_Date),
         COUNT(*)
  FROM `onyga-482313.OI.FACT_AMAZON_SEARCH_PERFORMANCE_WEEKLY`

  UNION ALL

  -- Currency rates
  SELECT 'DIM_CURRENCY_RATES',
         'Currency Rates',
         MAX(exchange_date),
         COUNT(*)
  FROM `onyga-482313.OI.DIM_CURRENCY_RATES`

  UNION ALL

  -- Pipeline run log
  SELECT 'LOG_PIPELINE_RUNS',
         'Pipeline Last Run',
         MAX(run_date),
         COUNT(*)
  FROM `onyga-482313.OI.LOG_PIPELINE_RUNS`
),

pipeline_health AS (
  SELECT
    MAX(run_date) AS last_run_date,
    COUNTIF(status = 'FAIL') AS failures_last_run
  FROM `onyga-482313.OI.LOG_PIPELINE_RUNS`
  WHERE run_date = (SELECT MAX(run_date) FROM `onyga-482313.OI.LOG_PIPELINE_RUNS`)
)

SELECT
  s.source_name,
  s.display_name,
  s.latest_date,
  s.total_rows,
  DATE_DIFF(CURRENT_DATE(), s.latest_date, DAY) AS days_stale,
  CASE
    WHEN DATE_DIFF(CURRENT_DATE(), s.latest_date, DAY) <= 1 THEN 'FRESH'
    WHEN DATE_DIFF(CURRENT_DATE(), s.latest_date, DAY) <= 3 THEN 'WARNING'
    ELSE 'STALE'
  END AS freshness_status,
  p.last_run_date AS pipeline_last_run,
  p.failures_last_run AS pipeline_failures
FROM sources s
CROSS JOIN pipeline_health p
ORDER BY s.source_name;
