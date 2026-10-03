-- =============================================================================================
-- FACT_ENGINE_HEALTH_HISTORY — the board's memory. v27.163 (2026-10-03, money-plan piece-1 Task 9).
--
-- WHY IT EXISTS. V_ENGINE_HEALTH is a live view: it says what is RED now and nothing about since
-- when. The piece-0 proof found SP_BUILD_NEXT_WEEK_PLAN refused 3 of 9 passes from 2026-09-29 to
-- 2026-10-01; the board carried the same three REDs on 2026-10-01 and on 2026-10-03, and the brief
-- named each RED with no date, so a new RED would have read like the old ones. With one row per
-- check per pass, V_DAILY_BRIEF's SYSTEM line can say which RED is NEW and since when each
-- standing one has stood (red_since = the earliest snapshot of the current unbroken RED run).
--
-- GRAIN. One row per (snapshot_at, check_name): every row of the board, as it read at the end of
-- one orchestrator pass. snapshot_at is the moment SP_SNAPSHOT_ENGINE_HEALTH started; every row of
-- one snapshot carries the same value. Nothing is ever written twice for one (snapshot_at,
-- check_name): PLAN_HEALTH_acceptance.sql A3 asserts it on the table.
--
-- APPEND-ONLY. Nothing updates or deletes a row. Nothing here decides anything: no engine,
-- generator, book or bulksheet reads this table; V_DAILY_BRIEF's SYSTEM line reads status only.
--
-- PARTITION / CLUSTER. Partitioned by the UTC day of snapshot_at, clustered by check_name: the one
-- read (the brief's red_since) asks "for this check, which snapshots read RED", over the whole
-- history, which is about 35 rows per pass and three passes a day.
--
-- Written by: SP_SNAPSHOT_ENGINE_HEALTH (orchestrator Refresh Task 23, the last step of a pass).
-- Read by:    V_DAILY_BRIEF (SYSTEM line, red_since).
-- Acceptance: scripts/bigquery/tests/PLAN_HEALTH_acceptance.sql (A2, A3).
-- SOP:        architecture/ENGINE_HEALTH.md "The board's memory"; architecture/DAILY_BRIEF.md SYSTEM.
-- CREATE TABLE IF NOT EXISTS — re-running this file can never drop a written snapshot.
-- =============================================================================================
CREATE TABLE IF NOT EXISTS `onyga-482313.OI.FACT_ENGINE_HEALTH_HISTORY` (
  snapshot_at TIMESTAMP NOT NULL OPTIONS(description = 'When SP_SNAPSHOT_ENGINE_HEALTH started reading the board; one value per snapshot (per orchestrator pass)'),
  check_name  STRING    NOT NULL OPTIONS(description = 'V_ENGINE_HEALTH.check_name'),
  status      STRING    NOT NULL OPTIONS(description = 'V_ENGINE_HEALTH.status at the snapshot: GREEN / AMBER / RED / INFO'),
  measured    FLOAT64            OPTIONS(description = 'V_ENGINE_HEALTH.measured at the snapshot'),
  detail      STRING             OPTIONS(description = 'V_ENGINE_HEALTH.detail at the snapshot')
)
PARTITION BY DATE(snapshot_at)
CLUSTER BY check_name
OPTIONS (
  description = 'The board\'s memory (v27.163, money-plan piece-1 Task 9): one row per V_ENGINE_HEALTH check per orchestrator pass, written by SP_SNAPSHOT_ENGINE_HEALTH as the last step of the pass (Refresh Task 23). Append-only; nothing decides from it. V_DAILY_BRIEF reads status to say which RED is NEW and since when each standing RED has stood (red_since = the earliest snapshot of the current unbroken RED run). Acceptance: scripts/bigquery/tests/PLAN_HEALTH_acceptance.sql (A2, A3). SOP: architecture/ENGINE_HEALTH.md.',
  labels = [("layer", "observability"), ("owner", "ori")]
);
