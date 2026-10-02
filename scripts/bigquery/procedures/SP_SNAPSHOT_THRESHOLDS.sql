-- =============================================================================================
-- SP_SNAPSHOT_THRESHOLDS() — v27.155 (2026-10-01), learning-contract piece 0 Task D.
-- Records the rule tables' values in FACT_THRESHOLD_HISTORY: every row of DE_COACH_THRESHOLDS and
-- DE_PLAN_CONFIG that differs from its last snapshot gets one new row, and a pass with nothing
-- different writes nothing. The first run seeds every current row (SEEDED).
--
-- The logic is SP_SNAPSHOT_THRESHOLDS_INTO, called here with the three live tables; it takes the
-- names so THRESHOLD_HISTORY_acceptance.sql can run the same code on TMP_ copies.
--
-- Schedule: SP_ORCHESTRATE_DAILY_REFRESH Refresh Task 10.1, right after SP_DATA_ENTRY_UPDATES,
-- logged to LOG_PIPELINE_RUNS ('OK' / 'FAIL') like every step. Reads two small tables; does not
-- read FACT_AMAZON_ADS.
-- Table: scripts/bigquery/tables/FACT_THRESHOLD_HISTORY.sql.
-- SOP:   architecture/NEXT_WEEK_MONEY.md §1 "The settings, and who may change them".
-- =============================================================================================
CREATE OR REPLACE PROCEDURE `onyga-482313.OI.SP_SNAPSHOT_THRESHOLDS`()
OPTIONS (description = "v27.155 (2026-10-01), learning-contract piece 0 Task D: appends to FACT_THRESHOLD_HISTORY one row for every row of DE_COACH_THRESHOLDS and DE_PLAN_CONFIG that differs from its last snapshot (SEEDED on the first run, then ADDED / CHANGED / REMOVED); writes nothing when nothing changed. Calls SP_SNAPSHOT_THRESHOLDS_INTO with the three live tables. Orchestrator Refresh Task 10.1, after SP_DATA_ENTRY_UPDATES.")
BEGIN
  CALL `onyga-482313.OI.SP_SNAPSHOT_THRESHOLDS_INTO`(
    'onyga-482313.OI.DE_COACH_THRESHOLDS',
    'onyga-482313.OI.DE_PLAN_CONFIG',
    'onyga-482313.OI.FACT_THRESHOLD_HISTORY');
END;
