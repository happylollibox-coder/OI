-- V_WEEKLY_PLAN_REVIEW — actual vs expected per plan item, for EVERY completed week. Coacher D.
-- Widened 2026-08-05 (was: last completed week only): the single-week anchor silently skipped
-- any planned week the review didn't run for while it was "the" last week — e.g. the Jun 28 –
-- Jul 19 plans, which slid past unreviewed while the coach-loop schedule was broken. Actuals
-- for closed weeks are stable, and SP_REVIEW_WEEKLY_PLAN re-runs idempotently, so verdicts
-- keep converging while a week's ads attribution settles.
CREATE OR REPLACE VIEW `onyga-482313.OI.V_WEEKLY_PLAN_REVIEW` AS
WITH tol AS (
  SELECT COALESCE(MAX(IF(threshold_key='WEEKLY_PLAN_ON_PLAN_TOL', threshold_value, NULL)), 0.90) AS on_plan_tol
  FROM `onyga-482313.OI.DE_COACH_THRESHOLDS`
),
-- Last COMPLETED week (Sun–Sat): the week containing (today − 7) in LA time.
last_wk AS (SELECT DATE_TRUNC(DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL 7 DAY), WEEK(SUNDAY)) AS wk),
plan AS (
  SELECT * FROM `onyga-482313.OI.DE_WEEKLY_PLAN`
  WHERE week_start <= (SELECT wk FROM last_wk)
),
actual AS (
  -- V_WEEKLY_CELL_NET is finer than the plan cell (it also splits by campaign_type +
  -- ad_format) — aggregate to the plan grain or the join fans out and the SP's
  -- UPDATE...FROM hits multi-match errors.
  SELECT week_start, parent_name, season, match_type, intent_class,
         SUM(net_profit) AS actual_net, SUM(spend) AS actual_spend
  FROM `onyga-482313.OI.V_WEEKLY_CELL_NET`
  WHERE week_start <= (SELECT wk FROM last_wk)
  GROUP BY week_start, parent_name, season, match_type, intent_class
)
-- DISTINCT: DE_WEEKLY_PLAN carries some doubly-inserted identical rows (generator bug);
-- collapsing them here keeps SP_REVIEW_WEEKLY_PLAN's UPDATE...FROM single-match.
SELECT DISTINCT
  p.week_start, p.parent_name, p.season, p.match_type, p.intent_class, p.purpose, p.success_metric,
  p.expected_value, p.expected_net_profit, p.plan_net_profit, p.spend_mode, p.planned_spend,
  a.actual_net, a.actual_spend,
  CASE p.success_metric
    WHEN 'NET_PROFIT' THEN
      IF(COALESCE(a.actual_net,0) >= (SELECT on_plan_tol FROM tol) * COALESCE(p.expected_value,0), 'ON_PLAN', 'OFF_PLAN')
    WHEN 'SPEND_DOWN' THEN IF(COALESCE(a.actual_spend,1e9) <= COALESCE(p.planned_spend,0), 'ON_PLAN', 'OFF_PLAN')
    ELSE 'PENDING' END AS status,
  IF(p.spend_mode='CAP' AND COALESCE(a.actual_spend,0) > COALESCE(p.planned_spend,0), TRUE, FALSE) AS overspend,
  IF(p.success_metric='NET_PROFIT' AND p.plan_net_profit IS NOT NULL
     AND COALESCE(a.actual_net,0) < p.plan_net_profit, 'BELOW_TARGET', NULL) AS vs_business_plan
FROM plan p
-- week_start MUST be a join key now that multiple weeks flow through (else cross-week fan-out)
LEFT JOIN actual a USING (week_start, parent_name, season, match_type, intent_class)
