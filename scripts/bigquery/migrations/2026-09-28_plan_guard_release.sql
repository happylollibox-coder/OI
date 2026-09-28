-- 2026-09-28 — v27.147: the plan table carries the guard's clock, P-14c's last-day test and the
-- judge's release reason. WHY. SP_BUILD_NEXT_WEEK_PLAN failed every night from 2026-08-29 to
-- 2026-09-28 on its own P-14b assertion: the builder copied the guard's PRECONDITIONS and read
-- them as a veto, while V_PLAN_WINDOW_JUDGMENT (v27.138) reads P-14b as a clock anchored to the
-- window that triggered the hold. They agreed until the first clock expired; from that night the
-- judge demoted a keyword its rule allowed and the builder refused the partition. Nothing
-- downstream saw a plan newer than 08-28, and because nothing was written the judge's memory
-- froze, so the same rows failed forever. With Ori's 2026-09-17 ruling (P-14c: postpone only if
-- the last day was very good) the judge now publishes WHY it released each such row, and the
-- builder asserts the reason is there instead of re-deriving the guard (P-11: one engine judges).
-- Idempotent: ADD COLUMN IF NOT EXISTS. Mirrored in scripts/bigquery/tables/FACT_PLAN_NEXT_WEEK.sql.
ALTER TABLE `onyga-482313.OI.FACT_PLAN_NEXT_WEEK` ADD COLUMN IF NOT EXISTS hold_since DATE;
ALTER TABLE `onyga-482313.OI.FACT_PLAN_NEXT_WEEK` ADD COLUMN IF NOT EXISTS hold_settles_on DATE;
ALTER TABLE `onyga-482313.OI.FACT_PLAN_NEXT_WEEK` ADD COLUMN IF NOT EXISTS hold_expired BOOL;
ALTER TABLE `onyga-482313.OI.FACT_PLAN_NEXT_WEEK` ADD COLUMN IF NOT EXISTS last_day_sp FLOAT64;
ALTER TABLE `onyga-482313.OI.FACT_PLAN_NEXT_WEEK` ADD COLUMN IF NOT EXISTS last_day_clk INT64;
ALTER TABLE `onyga-482313.OI.FACT_PLAN_NEXT_WEEK` ADD COLUMN IF NOT EXISTS last_day_ord INT64;
ALTER TABLE `onyga-482313.OI.FACT_PLAN_NEXT_WEEK` ADD COLUMN IF NOT EXISTS last_day_gp FLOAT64;
ALTER TABLE `onyga-482313.OI.FACT_PLAN_NEXT_WEEK` ADD COLUMN IF NOT EXISTS last_day_gp_corrected FLOAT64;
ALTER TABLE `onyga-482313.OI.FACT_PLAN_NEXT_WEEK` ADD COLUMN IF NOT EXISTS last_day_ret FLOAT64;
ALTER TABLE `onyga-482313.OI.FACT_PLAN_NEXT_WEEK` ADD COLUMN IF NOT EXISTS last_day_strong BOOL;
ALTER TABLE `onyga-482313.OI.FACT_PLAN_NEXT_WEEK` ADD COLUMN IF NOT EXISTS guard_released_by STRING;
