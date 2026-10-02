-- =============================================================================================
-- 2026-10-02 — v27.158: FACT_PLAN_NEXT_WEEK carries the family's realised cut and the uploads that
-- landed (piece-1 plan Task 4; Ori's ruling R8 of 2026-10-02 = spec P-22, audit fix #15).
--   expected_after_upload_per_day  FLOAT64  P-22: per (plan, family), the not-good spend the family
--                                           is expected to make after the upload — the seats' cost
--                                           plus each queued candidate's window spend per day at
--                                           the price the plan leaves it at (park price on PARK,
--                                           current bid on HOLD_AT_PARK, zero on PAUSE). Repeated
--                                           on every row of the family, like pot_per_day.
--   share_closed                   FLOAT64  P-22: (not-good today - expected after upload) /
--                                           (not-good today - allowance target); NULL when the
--                                           family is at or under its target (no gap to close).
--   plan_uploads_landed            INT64    fix #15: plan batches (BRAIN / PACING / CATALOG) that
--                                           landed for the family since its first plan night;
--                                           ramp_step = LEAST(ramp_steps, this).
-- Written by SP_BUILD_NEXT_WEEK_PLAN v27.158; deploy THIS FILE FIRST (the builder's INSERT names
-- the columns). The deployed v27.157 builder keeps working after it: its `final` copies the table's
-- schema and leaves the new columns NULL.
-- NULL on every partition written before the columns existed; no existing row is updated.
-- Three ALTERs: within BigQuery's five metadata updates per table per ten seconds.
-- Idempotent: ADD COLUMN IF NOT EXISTS. Mirrored in scripts/bigquery/tables/FACT_PLAN_NEXT_WEEK.sql.
-- =============================================================================================
ALTER TABLE `onyga-482313.OI.FACT_PLAN_NEXT_WEEK` ADD COLUMN IF NOT EXISTS expected_after_upload_per_day FLOAT64;
ALTER TABLE `onyga-482313.OI.FACT_PLAN_NEXT_WEEK` ADD COLUMN IF NOT EXISTS share_closed FLOAT64;
ALTER TABLE `onyga-482313.OI.FACT_PLAN_NEXT_WEEK` ADD COLUMN IF NOT EXISTS plan_uploads_landed INT64;
