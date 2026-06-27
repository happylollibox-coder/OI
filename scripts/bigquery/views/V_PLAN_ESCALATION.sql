-- V_PLAN_ESCALATION — net-profit guardrail: raise persistent/acute plan failures to Ori. Coacher E.
-- Backend, advisory (recommends an intervention; execution = F). Reads D's plan/review + net trend + probe log.
CREATE OR REPLACE VIEW `onyga-482313.OI.V_PLAN_ESCALATION` AS
WITH thr AS (
  SELECT
    COALESCE(MAX(IF(threshold_key='ESCALATE_OFF_PLAN_WEEKS', threshold_value, NULL)), 2)   AS off_plan_weeks,
    COALESCE(MAX(IF(threshold_key='NET_COLLAPSE_FRAC',       threshold_value, NULL)), 0.5) AS collapse_frac,
    COALESCE(MAX(IF(threshold_key='ACUTE_LOSS_NET',          threshold_value, NULL)), 0)   AS acute_loss_net,
    COALESCE(MAX(IF(threshold_key='ESCALATION_TREND_WEEKS',  threshold_value, NULL)), 8)   AS trend_weeks
  FROM `onyga-482313.OI.DE_COACH_THRESHOLDS`
),
last_wk AS (SELECT DATE_TRUNC(DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL 7 DAY), WEEK(MONDAY)) AS wk),
prod_net AS (
  SELECT parent_name, week_start, SUM(net_profit) AS net
  FROM `onyga-482313.OI.V_WEEKLY_CELL_NET` GROUP BY 1, 2
),
prod_last AS (
  SELECT parent_name, net AS last_net FROM prod_net WHERE week_start = (SELECT wk FROM last_wk)
),
prod_trend AS (
  SELECT p.parent_name, AVG(p.net) AS trend_net
  FROM prod_net p CROSS JOIN thr t, last_wk l
  WHERE p.week_start >= DATE_SUB(l.wk, INTERVAL CAST(t.trend_weeks AS INT64) WEEK)
    AND p.week_start < l.wk
  GROUP BY 1
)
-- 2. ACUTE_NET_LOSS (product losing money last week)
SELECT pl.parent_name, 'PRODUCT' AS scope,
  CAST(NULL AS STRING) AS season, CAST(NULL AS STRING) AS match_type, CAST(NULL AS STRING) AS intent_class,
  'ACUTE_NET_LOSS' AS trigger, 'ESCALATE' AS severity, (SELECT wk FROM last_wk) AS since_week,
  CAST(NULL AS INT64) AS weeks_off, ROUND(pl.last_net, 2) AS actual_net,
  CAST(NULL AS FLOAT64) AS expected_net, CAST(NULL AS FLOAT64) AS trend_net, CAST(NULL AS FLOAT64) AS spend_vs_cap,
  'pause / cut the loss-making cells' AS recommended_action,
  CONCAT('last week net $', CAST(ROUND(pl.last_net, 0) AS STRING), ' < 0') AS evidence
FROM prod_last pl CROSS JOIN thr WHERE pl.last_net < thr.acute_loss_net
UNION ALL
-- 3. NET_COLLAPSE (profitable product whose net fell to <= frac x trend)
SELECT pl.parent_name, 'PRODUCT', NULL, NULL, NULL,
  'NET_COLLAPSE', 'WATCH', (SELECT wk FROM last_wk), NULL,
  ROUND(pl.last_net, 2), NULL, ROUND(pt.trend_net, 2), NULL,
  'investigate; hold bids (no chase)',
  CONCAT('net $', CAST(ROUND(pl.last_net, 0) AS STRING), ' <= ',
         CAST(thr.collapse_frac AS STRING), 'x trend $', CAST(ROUND(pt.trend_net, 0) AS STRING))
FROM prod_last pl JOIN prod_trend pt USING (parent_name) CROSS JOIN thr
WHERE pt.trend_net > 0 AND pl.last_net >= thr.acute_loss_net
  AND pl.last_net <= thr.collapse_frac * pt.trend_net
UNION ALL
-- 1. PERSISTENT_OFF_PLAN (SCALE product off-plan for >= N recent weeks)
SELECT o.parent_name, 'PRODUCT', NULL, NULL, NULL,
  'PERSISTENT_OFF_PLAN', 'ESCALATE', (SELECT wk FROM last_wk), o.weeks_off,
  NULL, NULL, NULL, NULL,
  're-derive cpc_target / cut SCALE budget / review strategy',
  CONCAT(CAST(o.weeks_off AS STRING), ' off-plan weeks (last ', CAST(o.win AS STRING), 'w)')
FROM (
  SELECT p.parent_name, COUNT(DISTINCT p.week_start) AS weeks_off, CAST(t.trend_weeks AS INT64) AS win
  FROM `onyga-482313.OI.DE_WEEKLY_PLAN` p CROSS JOIN thr t, last_wk l
  WHERE p.status = 'OFF_PLAN' AND p.purpose = 'SCALE'
    AND p.week_start >= DATE_SUB(l.wk, INTERVAL CAST(t.trend_weeks AS INT64) WEEK)
  GROUP BY p.parent_name, t.trend_weeks
) o CROSS JOIN thr WHERE o.weeks_off >= thr.off_plan_weeks
UNION ALL
-- 4. CAP_OVERSPEND (a capped cell breached its cap last week)
SELECT r.parent_name, 'CELL', r.season, r.match_type, r.intent_class,
  'CAP_OVERSPEND', 'WATCH', r.week_start, NULL,
  NULL, NULL, NULL, ROUND(SAFE_DIVIDE(r.actual_spend, NULLIF(r.planned_spend, 0)), 2),
  'lower the configured Amazon daily budget',
  CONCAT('CAP spend $', CAST(ROUND(r.actual_spend, 0) AS STRING), ' > cap $', CAST(ROUND(r.planned_spend, 0) AS STRING))
FROM `onyga-482313.OI.V_WEEKLY_PLAN_REVIEW` r WHERE r.overspend
UNION ALL
-- 5. PROBE_WASTE (probe exhausted without converting)
SELECT l.parent_name, 'CELL', l.season, l.match_type, l.intent_class,
  'PROBE_WASTE', 'WATCH', l.probe_started_at, NULL,
  NULL, NULL, NULL, NULL,
  'kill the probe; mark the cell un-winnable',
  CONCAT('probe exhausted at ', CAST(l.clicks_accumulated AS STRING), ' clicks')
FROM `onyga-482313.OI.DE_PROBE_LOG` l WHERE l.status = 'EXHAUSTED'
