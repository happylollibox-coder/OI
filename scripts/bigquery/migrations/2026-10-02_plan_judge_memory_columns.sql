-- =============================================================================================
-- 2026-10-02 — v27.156: FACT_PLAN_NEXT_WEEK carries the judge's memory (piece-1 plan Task 2;
-- Ori's rulings R3, R4, R16 of 2026-10-02 = spec P-17, P-18, P-29).
--   hold_strong_day        DATE    P-18: the very good last day that started the hold run (the
--                                  window_to of the run's first night).
--   hold_kept_by           STRING  P-18: what keeps a HELD row held — LAST_DAY (its last complete
--                                  day was very good) or STRONG_DAY_IN_WINDOW (the day that started
--                                  the run is still inside the judged window). NULL on every row
--                                  that is not HELD. SP_BUILD_NEXT_WEEK_PLAN, V_ENGINE_HEALTH
--                                  (plan_settle_guard_holds) and the acceptance READ it.
--   grace_since            DATE    P-17: the first night of the grace run (grace lasts that night's
--                                  window_days nightly judgments).
--   memory_cleared_by_gap  STRING  P-29: GRACE | HOLD | GRACE_AND_HOLD when a GOOD window inside an
--                                  unwritten gap cleared that memory on this night. NOT a report:
--                                  V_PLAN_WINDOW_JUDGMENT reads it back as a reset, so the clearing
--                                  survives the next night.
-- Deploy THIS FILE BEFORE V_PLAN_WINDOW_JUDGMENT v27.156, which reads memory_cleared_by_gap.
-- NULL on every partition written before the columns existed; no existing row is updated.
-- Four ALTERs: within BigQuery's five metadata updates per table per ten seconds.
-- Idempotent: ADD COLUMN IF NOT EXISTS. Mirrored in scripts/bigquery/tables/FACT_PLAN_NEXT_WEEK.sql.
-- =============================================================================================
ALTER TABLE `onyga-482313.OI.FACT_PLAN_NEXT_WEEK` ADD COLUMN IF NOT EXISTS hold_strong_day DATE;
ALTER TABLE `onyga-482313.OI.FACT_PLAN_NEXT_WEEK` ADD COLUMN IF NOT EXISTS hold_kept_by STRING;
ALTER TABLE `onyga-482313.OI.FACT_PLAN_NEXT_WEEK` ADD COLUMN IF NOT EXISTS grace_since DATE;
ALTER TABLE `onyga-482313.OI.FACT_PLAN_NEXT_WEEK` ADD COLUMN IF NOT EXISTS memory_cleared_by_gap STRING;
