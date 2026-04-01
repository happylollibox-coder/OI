-- =============================================
-- OI Database Project - LOG_PIPELINE_RUNS
-- =============================================
-- Purpose: Persistent log table for SP_ORCHESTRATE_DAILY_REFRESH.
--          Each row = one procedure execution within a pipeline run.
--          Enables: alerting on failures, freshness monitoring, duration tracking.
--
-- Grain: (run_id × procedure_name) — one row per procedure per pipeline run
-- =============================================

CREATE TABLE IF NOT EXISTS `onyga-482313.OI.LOG_PIPELINE_RUNS` (
  run_id          STRING      NOT NULL OPTIONS(description = 'UUID for the pipeline run'),
  run_date        DATE        NOT NULL OPTIONS(description = 'Date the pipeline ran'),
  procedure_name  STRING      NOT NULL OPTIONS(description = 'Name of the procedure executed'),
  status          STRING      NOT NULL OPTIONS(description = 'OK or FAIL'),
  error_message   STRING               OPTIONS(description = 'Error message if status = FAIL'),
  started_at      TIMESTAMP   NOT NULL OPTIONS(description = 'When the procedure started'),
  finished_at     TIMESTAMP   NOT NULL OPTIONS(description = 'When the procedure finished'),
  duration_seconds INT64      NOT NULL OPTIONS(description = 'Elapsed seconds'),
  inserted_at     TIMESTAMP   NOT NULL OPTIONS(description = 'Row insert time')
)
PARTITION BY run_date
OPTIONS(
  description = 'Pipeline execution log for SP_ORCHESTRATE_DAILY_REFRESH. Partitioned by run_date for efficient querying.',
  labels = [("layer", "observability"), ("owner", "ori")]
);
