-- =============================================================================================
-- 2026-10-02 — v27.159: FACT_PLAN_NEXT_WEEK carries the seat's tenure and the probe flag
-- (piece-1 plan Task 5; Ori's rulings R2 / R12 / R13 of 2026-10-02 = spec P-16 / P-25 / P-26).
--   seat_since   DATE    P-16: the night this keyword took the seat it holds tonight — as_of for a
--                        seat granted tonight, carried unchanged for an incumbent. NULL on a row
--                        with no seat. SP_BUILD_NEXT_WEEK_PLAN reads it back: only a seat written
--                        with seat_since is an incumbent the next night (the cutover — a seat
--                        written before v27.159 was priced before P-19 / P-25 and asked before P-26).
--   seat_tenure  STRING  P-16: INCUMBENT (kept the seat it held last partition, before its verdict
--                        date, with its price, cost and question), NEW (seated tonight),
--                        LEFT_ALLOWANCE_SHRANK (an incumbent tonight's allowance could not carry
--                        behind the incumbents seated before it), NULL otherwise.
--   is_probe     BOOL    the judge's is_probe (a LIFT nomination, T_LIFT_PROBES), copied so the
--                        acceptance and V_ENGINE_HEALTH read the probe moves (P-25: OPEN_PROBE on a
--                        seat, NONE without one) without re-deriving who is a probe.
-- And the column descriptions of FACT_SEAT_REQUEST.clicks_requested and .request_basis, which
-- described only the arithmetic written before P-26 (two metadata changes; no row of
-- FACT_SEAT_REQUEST is touched).
-- Written by SP_BUILD_NEXT_WEEK_PLAN v27.159; deploy THIS FILE FIRST (the builder's INSERT names
-- the columns). The deployed v27.158 builder keeps working after it: its `final` copies the table's
-- schema and leaves the new columns NULL.
-- NULL on every partition written before the columns existed; no existing row is updated.
-- Three ALTERs on FACT_PLAN_NEXT_WEEK: within BigQuery's five metadata updates per table per ten
-- seconds. Idempotent: ADD COLUMN IF NOT EXISTS / SET OPTIONS.
-- Mirrored in scripts/bigquery/tables/FACT_PLAN_NEXT_WEEK.sql and
-- scripts/bigquery/tables/FACT/FACT_SEAT_REQUEST.sql.
-- =============================================================================================
ALTER TABLE `onyga-482313.OI.FACT_PLAN_NEXT_WEEK` ADD COLUMN IF NOT EXISTS seat_since DATE;
ALTER TABLE `onyga-482313.OI.FACT_PLAN_NEXT_WEEK` ADD COLUMN IF NOT EXISTS seat_tenure STRING;
ALTER TABLE `onyga-482313.OI.FACT_PLAN_NEXT_WEEK` ADD COLUMN IF NOT EXISTS is_probe BOOL;
ALTER TABLE `onyga-482313.OI.FACT_SEAT_REQUEST` ALTER COLUMN clicks_requested SET OPTIONS (description = "How many clicks this seat is buying. Written before v27.159 (2026-10-02): an ordinary seat asked for last window's clicks at a repaired price, a probe click_goal_day x window_days. From v27.159 (spec P-26) the question spans the settle horizon: an ordinary seat asks ROUND(window clicks x settle_days / window_days), a probe click_goal_day x settle_days, due on the verdict date; an incumbent repeats the question it was given on the night it took the seat (P-16).");
ALTER TABLE `onyga-482313.OI.FACT_SEAT_REQUEST` ALTER COLUMN request_basis SET OPTIONS (description = "How clicks_requested was derived, so the row explains its own arithmetic. Written before v27.159 (2026-10-02): WINDOW_CLICKS (an ordinary seat asking for exactly last window's clicks, implied_daily_spend = clicks x expected_cpc / window_days) or PROBE_GOAL (click_goal_day x window_days). From v27.159 (spec P-26): HORIZON_WINDOW_RATE (the window's click rate x the settle horizon, due on the verdict date) or HORIZON_PROBE_GOAL (click_goal_day x the settle horizon); implied_daily_spend = clicks x expected_cpc / the settle horizon (SP 7 days, SB 14).");
