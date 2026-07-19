-- V_WEEKLY_RUN — one row per current-week family: plan summary + escalation + run status +
-- opportunity_score (orders the Weekly Run). Coacher D surface. Served fresh by Flask.
CREATE OR REPLACE VIEW `onyga-482313.OI.V_WEEKLY_RUN` AS
WITH plan AS (   -- current-week per-family plan rollup
  SELECT parent_name, week_start, cells, scale_cells, planned_spend, forward_ads_net, purposes
  FROM `onyga-482313.OI.V_WEEKLY_PLAN_PRODUCT`
  WHERE horizon = 'CURRENT'
),
esc AS (    -- escalation per family (worst severity + its net)
  SELECT parent_name,
         MAX(CASE UPPER(severity) WHEN 'ESCALATE' THEN 2 WHEN 'WATCH' THEN 1 ELSE 0 END) AS sev_rank,
         MIN(actual_net) AS escalation_net
  FROM `onyga-482313.OI.V_PLAN_ESCALATION`
  GROUP BY parent_name
),
run AS (    -- latest run status per (family, week)
  SELECT parent_name, week_start, status, approved_at, done_at, note
  FROM `onyga-482313.OI.DE_WEEKLY_RUN`
  QUALIFY ROW_NUMBER() OVER (PARTITION BY parent_name, week_start ORDER BY updated_at DESC) = 1
)
SELECT
  p.parent_name,
  p.week_start AS week_start,
  COALESCE(r.status, 'PENDING') AS status,
  CAST(r.approved_at AS STRING) AS approved_at,
  CAST(r.done_at AS STRING)     AS done_at,
  r.note,
  p.cells, p.scale_cells, p.planned_spend, p.forward_ads_net, p.purposes,
  (e.sev_rank IS NOT NULL) AS has_escalation,
  CASE e.sev_rank WHEN 2 THEN 'ESCALATE' WHEN 1 THEN 'WATCH' ELSE NULL END AS escalation_severity,
  e.escalation_net,
  ROUND(COALESCE(p.forward_ads_net, 0) + GREATEST(-COALESCE(e.escalation_net, 0), 0), 2) AS opportunity_score
FROM plan p
LEFT JOIN esc e ON e.parent_name = p.parent_name
LEFT JOIN run r ON r.parent_name = p.parent_name AND CAST(r.week_start AS STRING) = p.week_start
ORDER BY opportunity_score DESC
