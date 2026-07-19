-- V_WEEKLY_PLAN_ACTIONS — current-week coach actions grouped under each cell's plan item. Coacher D.
CREATE OR REPLACE VIEW `onyga-482313.OI.V_WEEKLY_PLAN_ACTIONS` AS
WITH cur AS (SELECT DATE_TRUNC(CURRENT_DATE('America/Los_Angeles'), WEEK(SUNDAY)) AS wk),
plan AS (
  -- DE_WEEKLY_PLAN is now per-format (campaign_type × ad_format); this view groups coach actions at
  -- the coarse cell, so collapse the plan to one row per (parent,season,match,intent) to avoid fan-out.
  SELECT parent_name, season, match_type, intent_class,
         ANY_VALUE(purpose) AS purpose, ANY_VALUE(success_metric) AS success_metric,
         ANY_VALUE(expected_value) AS expected_value, MAX(target_cpc) AS target_cpc
  FROM `onyga-482313.OI.DE_WEEKLY_PLAN`
  WHERE horizon='CURRENT' AND week_start=(SELECT wk FROM cur)
  GROUP BY parent_name, season, match_type, intent_class
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
