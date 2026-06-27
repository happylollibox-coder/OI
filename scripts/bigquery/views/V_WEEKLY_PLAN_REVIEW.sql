-- V_WEEKLY_PLAN_REVIEW — actual vs expected per plan item for the last completed week. Coacher D.
CREATE OR REPLACE VIEW `onyga-482313.OI.V_WEEKLY_PLAN_REVIEW` AS
WITH tol AS (
  SELECT COALESCE(MAX(IF(threshold_key='WEEKLY_PLAN_ON_PLAN_TOL', threshold_value, NULL)), 0.90) AS on_plan_tol
  FROM `onyga-482313.OI.DE_COACH_THRESHOLDS`
),
last_wk AS (SELECT DATE_TRUNC(DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL 7 DAY), WEEK(MONDAY)) AS wk),
plan AS (
  SELECT * FROM `onyga-482313.OI.DE_WEEKLY_PLAN`
  WHERE week_start = (SELECT wk FROM last_wk)
),
actual AS (
  SELECT parent_name, season, match_type, intent_class, net_profit AS actual_net, spend AS actual_spend
  FROM `onyga-482313.OI.V_WEEKLY_CELL_NET`
  WHERE week_start = (SELECT wk FROM last_wk)
)
SELECT
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
LEFT JOIN actual a USING (parent_name, season, match_type, intent_class)
