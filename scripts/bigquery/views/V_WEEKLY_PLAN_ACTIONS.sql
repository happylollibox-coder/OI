-- V_WEEKLY_PLAN_ACTIONS — current-week coach actions grouped under each cell's plan item. Coacher D.
CREATE OR REPLACE VIEW `onyga-482313.OI.V_WEEKLY_PLAN_ACTIONS` AS
WITH cur AS (SELECT DATE_TRUNC(CURRENT_DATE('America/Los_Angeles'), WEEK(MONDAY)) AS wk),
plan AS (
  SELECT parent_name, season, match_type, intent_class, purpose, success_metric, expected_value, target_cpc
  FROM `onyga-482313.OI.DE_WEEKLY_PLAN`
  WHERE horizon='CURRENT' AND week_start=(SELECT wk FROM cur)
)
SELECT
  c.parent_name, c.season, c.match_type, c.intent_class,
  pl.purpose, c.keyword_id, c.target_action, c.current_bid, c.recommended_bid, c.bid_change_pct,
  pl.target_cpc,
  CASE pl.purpose
    WHEN 'SCALE'  THEN 'grow at target CPC — more volume at held ROAS'
    WHEN 'MAP'    THEN 'reach 15 clicks to decide'
    WHEN 'PROBE'  THEN 'reach 15 clicks to decide'
    WHEN 'DEFEND' THEN 'hold top-of-search position'
    WHEN 'CUT'    THEN 'cut wasted spend'
    WHEN 'HOLD'   THEN 'maintain — no churn'
    ELSE 'monitor' END AS expected_result
FROM `onyga-482313.OI.V_ADS_COACH` c
JOIN plan pl USING (parent_name, season, match_type, intent_class)
WHERE c.target_action IS NOT NULL AND c.target_action NOT IN ('MONITOR_TARGET','KEEP_TARGET')
