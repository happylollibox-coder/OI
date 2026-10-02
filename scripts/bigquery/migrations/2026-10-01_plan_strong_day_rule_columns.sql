-- 2026-10-01 — v27.154 follow-up: every plan row records the P-14c rule it was judged under.
-- WHY. FN_PLAN_SCORECARD grades each hold and release the live plan wrote under the last-day test
-- (P-14c), and its RULE_HINT exists to propose moving the test's multiplier. Until now the
-- multiplier lived only as a literal in V_PLAN_WINDOW_JUDGMENT's k CTE, so the scorecard kept a
-- mirrored copy and graded every decision in history against TODAY'S value: after a change, old
-- decisions would be graded against a rule that was not in force when they were made. The judge now
-- publishes strong_day_mult and strong_day_min_orders on every row and SP_BUILD_NEXT_WEEK_PLAN
-- copies them here (a column copy; none of the builder's assertions changed).
-- Rows written before these columns existed (the 2026-09-28 .. 10-01 partitions) are NOT updated
-- and keep NULL. FN_PLAN_SCORECARD reads them as 1.5 and 1: `git log -S` on either k line of
-- V_PLAN_WINDOW_JUDGMENT.sql lists commit 41d2318 (v27.147) alone, and the deployed view's
-- definition read 1.5 / 1 on 2026-10-01.
-- Idempotent: ADD COLUMN IF NOT EXISTS, one ALTER per statement. Mirrored in
-- scripts/bigquery/tables/FACT_PLAN_NEXT_WEEK.sql.
ALTER TABLE `onyga-482313.OI.FACT_PLAN_NEXT_WEEK` ADD COLUMN IF NOT EXISTS strong_day_mult FLOAT64;
ALTER TABLE `onyga-482313.OI.FACT_PLAN_NEXT_WEEK` ADD COLUMN IF NOT EXISTS strong_day_min_orders INT64;
