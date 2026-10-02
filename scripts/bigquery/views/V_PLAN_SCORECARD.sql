-- =============================================================================================
-- V_PLAN_SCORECARD — v27.154 (2026-10-01): the next-week money plan's T+14 grade, as of today
-- (plan Task 5, first half; spec §5, P-9, P-14b/c). A thin wrapper: FN_PLAN_SCORECARD at
-- CURRENT_DATE('America/Los_Angeles'). Every rule, constant and sentence lives in the function's
-- file — read its header, not this one. The acceptance calls the function with the clock moved
-- forward, so what it proves is the arithmetic this view runs.
--
-- Row types: GRADE (plan x family x calendar_state), RECOMMENDATION (family x calendar_state:
-- WAIT / KEEP_<live> / SWITCH_TO_<shadow>), FAMILY_WEEK (family x graded night, A and B side by
-- side), GUARD (week x outcome class: held right / held wrong / released right / released wrong),
-- RULE_HINT (one row: what the guard's grades say about the last-day test in force, or WAIT and
-- why; v27.154 follow-up: it reads each decision against the rule stored on its plan row and waits
-- until each group it compares has 10 graded rows — the function's header has both).
-- Function: scripts/bigquery/functions/FN_PLAN_SCORECARD.sql.
-- SOP: architecture/NEXT_WEEK_MONEY.md §6 "Grading".
-- Acceptance: scripts/bigquery/tests/PLAN_SCORECARD_acceptance.sql.
-- =============================================================================================
CREATE OR REPLACE VIEW `onyga-482313.OI.V_PLAN_SCORECARD`
OPTIONS (description = "v27.154 (2026-10-01): the next-week money plan's T+14 grade as of today — FN_PLAN_SCORECARD(CURRENT_DATE('America/Los_Angeles')). GRADE per plan x family x calendar_state and FAMILY_WEEK per family x graded night (one plan night per Sunday-start week, at least 14 days old): allocated dollars, realized net, and net per allocated dollar = each allocated dollar credited with what one ad dollar on that keyword netted in the window_days days that followed. RECOMMENDATION per family x calendar_state: WAIT below 3 graded weeks, SWITCH_TO_<shadow> when the shadow beats the live plan by 10% of the live plan's magnitude, else KEEP_<live>; Ori flips DE_PLAN_CONFIG.live_plan, the code never switches. GUARD per week x outcome class grades every P-14c hold and release once its window has settled (held right/wrong, released right/wrong, with settled spend, net and last-day return quantiles); RULE_HINT (v27.154 follow-up) judges the last-day rule in force, stored on the live plan's latest night, from the decisions made under it: WAIT below 20 graded decisions in all, or below 10 in either group it compares (held; let through with a last day between 1.0x and the row's own multiplier), naming the group and its count; else LOWER / RAISE / KEEP_STRONG_DAY_MULT or NO_CLEAN_SIGNAL, leading with the group size it argued from. SOP: architecture/NEXT_WEEK_MONEY.md §6.")
AS
SELECT *
FROM `onyga-482313.OI.FN_PLAN_SCORECARD`(CURRENT_DATE('America/Los_Angeles'))
ORDER BY CASE row_type WHEN 'RECOMMENDATION' THEN 1 WHEN 'GRADE' THEN 2 WHEN 'FAMILY_WEEK' THEN 3
                       WHEN 'RULE_HINT' THEN 4 ELSE 5 END,
         family, calendar_state, week_start, plan, outcome_class;
