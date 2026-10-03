-- =============================================================================================
-- SP_SNAPSHOT_ENGINE_HEALTH — writes the board into its memory. v27.163 (2026-10-03, money-plan
-- piece-1 Task 9, Step 2).
--
-- One call = one snapshot: every row of V_ENGINE_HEALTH, stamped with the call's start time, appended
-- to FACT_ENGINE_HEALTH_HISTORY. The orchestrator calls it once per pass, as its LAST step (Refresh
-- Task 23, after SP_REFRESH_CUBE_TABLES), so the snapshot reads the board the pass just rebuilt
-- (T_ENGINE_PREFLIGHT, T_FAMILY_SEAT_REGISTER, FACT_PLAN_NEXT_WEEK, LOG_PIPELINE_RUNS).
--
-- ONE READ OF THE BOARD PER CALL. The board carries one V_CHANGE_SCORECARD arm (a ceiling view), so it
-- is read once into a temp table and the guards and the insert read the copy.
--
-- GUARDS, each refusing the whole snapshot (the step then logs FAIL in LOG_PIPELINE_RUNS, which
-- pipeline_step_failing reads):
--   * an empty board — a snapshot with no rows would read, to V_DAILY_BRIEF, as every check not RED
--     on that pass, and would break every RED run in the memory;
--   * a check name twice, or a row with no name or no status — the memory is keyed on
--     (snapshot_at, check_name), and a doubled name would be written twice under one key.
--
-- It decides nothing and moves no bid, budget or pause. A hand CALL writes a snapshot too (and leaves
-- no LOG_PIPELINE_RUNS row); the brief reads it like any other.
-- Acceptance: scripts/bigquery/tests/PLAN_HEALTH_acceptance.sql (A3). SOP: architecture/ENGINE_HEALTH.md.
-- =============================================================================================
CREATE OR REPLACE PROCEDURE `onyga-482313.OI.SP_SNAPSHOT_ENGINE_HEALTH`()
OPTIONS (description = "v27.163 (money-plan piece-1 Task 9): appends every row of V_ENGINE_HEALTH, stamped with the call's start time, to FACT_ENGINE_HEALTH_HISTORY — the board's memory, from which V_DAILY_BRIEF's SYSTEM line tells a NEW RED from a standing one. Orchestrator Refresh Task 23, the last step of a pass. Reads the board once (it carries one V_CHANGE_SCORECARD arm) into a temp table; refuses the snapshot on an empty board, a check name twice, or a row with no name or status. Append-only; decides nothing. Acceptance: scripts/bigquery/tests/PLAN_HEALTH_acceptance.sql (A3). SOP: architecture/ENGINE_HEALTH.md.")
BEGIN
  DECLARE snap_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP();

  CREATE OR REPLACE TEMP TABLE engine_health_board AS
    SELECT check_name, status, measured, detail FROM `onyga-482313.OI.V_ENGINE_HEALTH`;

  ASSERT (SELECT COUNT(*) FROM engine_health_board) > 0
    AS 'SP_SNAPSHOT_ENGINE_HEALTH: V_ENGINE_HEALTH returned no rows; an empty snapshot would read as every check not RED on this pass, so none is written';
  ASSERT (SELECT COUNTIF(check_name IS NULL OR status IS NULL) FROM engine_health_board) = 0
    AS 'SP_SNAPSHOT_ENGINE_HEALTH: a board row with no check_name or no status; the memory is keyed on (snapshot_at, check_name), so none is written';
  ASSERT (SELECT COUNT(*) - COUNT(DISTINCT check_name) FROM engine_health_board) = 0
    AS 'SP_SNAPSHOT_ENGINE_HEALTH: a check name appears twice on the board; it would be written twice under one (snapshot_at, check_name), so none is written';

  INSERT INTO `onyga-482313.OI.FACT_ENGINE_HEALTH_HISTORY` (snapshot_at, check_name, status, measured, detail)
  SELECT snap_at, check_name, status, measured, detail FROM engine_health_board;
END;
