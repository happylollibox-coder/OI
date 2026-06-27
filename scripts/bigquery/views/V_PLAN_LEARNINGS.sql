-- V_PLAN_LEARNINGS — what works per cell x purpose across completed weeks. Coacher D.
-- The memory that should calibrate future plans (generator consumption = v1.1).
CREATE OR REPLACE VIEW `onyga-482313.OI.V_PLAN_LEARNINGS` AS
SELECT
  parent_name, season, match_type, intent_class, purpose,
  COUNT(*) AS attempts,
  COUNTIF(status IN ('ON_PLAN','MET')) AS wins,
  ROUND(SAFE_DIVIDE(COUNTIF(status IN ('ON_PLAN','MET')), COUNT(*)), 2) AS win_rate,
  ROUND(AVG(actual_value), 2) AS avg_actual,
  CASE
    WHEN COUNT(*) < 3 THEN 'INCONCLUSIVE'
    WHEN SAFE_DIVIDE(COUNTIF(status IN ('ON_PLAN','MET')), COUNT(*)) >= 0.6 THEN 'WORKS'
    ELSE 'DOESNT' END AS verdict
FROM `onyga-482313.OI.DE_WEEKLY_PLAN`
WHERE horizon = 'CURRENT' AND status IN ('ON_PLAN','OFF_PLAN','MET','MISSED')
GROUP BY 1,2,3,4,5
