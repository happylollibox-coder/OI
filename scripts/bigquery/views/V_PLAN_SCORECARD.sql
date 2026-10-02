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
-- RULE_HINT (one row: what the guard's grades say about the 1.5x last-day test, or WAIT and why).
-- Function: scripts/bigquery/functions/FN_PLAN_SCORECARD.sql.
-- SOP: architecture/NEXT_WEEK_MONEY.md §6 "Grading".
-- Acceptance: scripts/bigquery/tests/PLAN_SCORECARD_acceptance.sql.
-- =============================================================================================
CREATE OR REPLACE VIEW `onyga-482313.OI.V_PLAN_SCORECARD`
OPTIONS (description = "v27.154 (2026-10-01): the next-week money plan's T+14 grade as of today — FN_PLAN_SCORECARD(CURRENT_DATE('America/Los_Angeles')). GRADE per plan x family x calendar_state and FAMILY_WEEK per family x graded night (one plan night per Sunday-start week, at least 14 days old): allocated dollars, realized net, and net per allocated dollar = each allocated dollar credited with what one ad dollar on that keyword netted in the window_days days that followed. RECOMMENDATION per family x calendar_state: WAIT below 3 graded weeks, SWITCH_TO_<shadow> when the shadow beats the live plan by 10% of the live plan's magnitude, else KEEP_<live>; Ori flips DE_PLAN_CONFIG.live_plan, the code never switches. GUARD per week x outcome class grades every P-14c hold and release once its window has settled (held right/wrong, released right/wrong, with settled spend, net and last-day return quantiles); RULE_HINT says WAIT below 20 graded decisions, with the reason, else what the grades say about the 1.5x last-day threshold. SOP: architecture/NEXT_WEEK_MONEY.md §6.")
AS
SELECT *
FROM `onyga-482313.OI.FN_PLAN_SCORECARD`(CURRENT_DATE('America/Los_Angeles'))
ORDER BY CASE row_type WHEN 'RECOMMENDATION' THEN 1 WHEN 'GRADE' THEN 2 WHEN 'FAMILY_WEEK' THEN 3
                       WHEN 'RULE_HINT' THEN 4 ELSE 5 END,
         family, calendar_state, week_start, plan, outcome_class;
