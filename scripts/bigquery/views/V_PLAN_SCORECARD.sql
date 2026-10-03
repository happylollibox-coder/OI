-- =============================================================================================
-- V_PLAN_SCORECARD — v27.166 (2026-10-03, piece-1 follow-up F4); v27.154 (2026-10-01): the
-- next-week money plan's T+14 grade, as of today (plan Task 5, first half; spec §5, P-9, P-14b/c).
-- A thin wrapper: FN_PLAN_SCORECARD at CURRENT_DATE('America/New_York'), the date nights are keyed
-- on (FACT_PLAN_NEXT_WEEK.as_of since v27.160), and CURRENT_DATE('America/Los_Angeles'), the date
-- ads days and settle dates are on — the judge's two clocks (spec P-24). Until F4 it passed the Los
-- Angeles date alone, so from the 01:35 New York pass until Los Angeles midnight it read neither the
-- night that pass wrote nor its rule. Every rule, constant and sentence lives in the function's
-- file — read its header, not this one. The acceptance calls the function with the clock moved
-- forward, so what it proves is the arithmetic this view runs.
--
-- Row types: GRADE (plan x family x calendar_state), RECOMMENDATION (family x calendar_state:
-- WAIT / KEEP_<live> / SWITCH_TO_<shadow>), FAMILY_WEEK (family x graded night, A and B side by
-- side), GUARD (week x outcome class: held right / held wrong / released right / released wrong),
-- RULE_HINT (one row: what the guard's grades say about the last-day test in force, or WAIT and
-- why; v27.154 follow-up: it reads each decision against the rule stored on its plan row and waits
-- until each group it compares has min_group_rows graded rows, 16 since Ori's ruling of 2026-10-02
-- (10 before it); second follow-up, after commit 46ae335: the
-- band it compares leaves out releases whose hold clock had run out — the function's header has all
-- three).
-- Function: scripts/bigquery/functions/FN_PLAN_SCORECARD.sql.
-- SOP: architecture/NEXT_WEEK_MONEY.md §6 "Grading".
-- Acceptance: scripts/bigquery/tests/PLAN_SCORECARD_acceptance.sql.
-- =============================================================================================
CREATE OR REPLACE VIEW `onyga-482313.OI.V_PLAN_SCORECARD`
OPTIONS (description = "v27.166 (2026-10-03, piece-1 follow-up F4, spec P-24): FN_PLAN_SCORECARD(CURRENT_DATE('America/New_York'), CURRENT_DATE('America/Los_Angeles')) -- nights are dated on the New York date FACT_PLAN_NEXT_WEEK.as_of is keyed on, settle dates and ads days on the Los Angeles date, the judge's two clocks; until F4 the Los Angeles date was passed alone, and from the 01:35 New York pass until Los Angeles midnight the night that pass wrote and its rule were not read. v27.154 (2026-10-01): the next-week money plan's T+14 grade as of today. GRADE per plan x family x calendar_state and FAMILY_WEEK per family x graded night (one plan night per Sunday-start week, at least 14 days old): allocated dollars, realized net, and net per allocated dollar = each allocated dollar credited with what one ad dollar on that keyword netted in the window_days days that followed. RECOMMENDATION per family x calendar_state: WAIT below 3 graded weeks, SWITCH_TO_<shadow> when the shadow beats the live plan by 10% of the live plan's magnitude, else KEEP_<live>; Ori flips DE_PLAN_CONFIG.live_plan, the code never switches. GUARD per week x outcome class grades every P-14c hold and release once its window has settled (held right/wrong, released right/wrong, with settled spend, net and last-day return quantiles); RULE_HINT (v27.154 follow-up) judges the last-day rule in force, stored on the live plan's latest night, from the decisions made under it: WAIT below 20 graded decisions in all, or below min_group_rows (16, Ori's ruling of 2026-10-02) in either group it compares (held; let through by the last-day test with a last day between 1.0x and the row's own multiplier, at least its order minimum, and the hold clock still running: since the v27.154 second follow-up a release whose hold clock had run out is left out of the band), naming the group and its count; else LOWER / RAISE / KEEP_STRONG_DAY_MULT or NO_CLEAN_SIGNAL, leading with the group size it argued from. SOP: architecture/NEXT_WEEK_MONEY.md §6.")
AS
SELECT *
FROM `onyga-482313.OI.FN_PLAN_SCORECARD`(CURRENT_DATE('America/New_York'), CURRENT_DATE('America/Los_Angeles'))
ORDER BY CASE row_type WHEN 'RECOMMENDATION' THEN 1 WHEN 'GRADE' THEN 2 WHEN 'FAMILY_WEEK' THEN 3
                       WHEN 'RULE_HINT' THEN 4 ELSE 5 END,
         family, calendar_state, week_start, plan, outcome_class;
