-- =============================================================================================
-- 2026-10-03 — v27.170: FACT_PLAN_NEXT_WEEK carries the version of the builder that wrote each row
-- (learning-contract piece 2, Task 3; Ori's ruling D2 (c) of 2026-10-03).
--   builder_version  STRING  the vNN.NNN that opens SP_BUILD_NEXT_WEEK_PLAN's header and its OPTIONS
--                            description, written by the builder on every row from v27.170 on. The
--                            prediction ledger (V_PREDICTION_LEDGER, piece-2 Task 4) joins it into
--                            rule_version, so a grade can name the code a forecast was made under
--                            when no setting changed ('pre-v27.170' where it is NULL).
-- Written by SP_BUILD_NEXT_WEEK_PLAN v27.170; deploy THIS FILE FIRST (the builder's INSERT names the
-- column). The deployed v27.169 builder keeps working after it: its `final` copies the table's
-- schema and leaves the new column NULL.
-- NULL on every partition written before the column existed; no existing row is updated.
-- One ALTER on FACT_PLAN_NEXT_WEEK. Idempotent: ADD COLUMN IF NOT EXISTS.
-- Mirrored in scripts/bigquery/tables/FACT_PLAN_NEXT_WEEK.sql.
-- SOP: architecture/LEARNING.md §1 ("The freeze") and §10 "Task 3".
-- =============================================================================================
ALTER TABLE `onyga-482313.OI.FACT_PLAN_NEXT_WEEK`
  ADD COLUMN IF NOT EXISTS builder_version STRING
  OPTIONS (description = "v27.170 (2026-10-03, learning piece 2 Task 3, ruling D2 (c)): the version of SP_BUILD_NEXT_WEEK_PLAN that wrote the row -- the vNN.NNN opening the procedure's header and description. NULL on rows written before v27.170.");
