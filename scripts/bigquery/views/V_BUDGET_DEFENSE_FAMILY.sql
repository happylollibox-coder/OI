-- V_BUDGET_DEFENSE_FAMILY — one row per family that has DEFENSE campaigns, for the Weekly Run Step-1
-- DEFENSE panel. weight = the backend defense allocation (from V_CAMPAIGN_BUDGET_BASE, i.e. defense_total
-- split by defense spend-need); the UI splits the live defense dial across families proportionally to it.
-- Carries defense spend / current / allocated budgets + ads net ROAS & net profit per day (last 7 full days),
-- and a dominance flag: n_underbid = defense keywords whose latest bid is below 1.5× their CPC (not owning
-- page 1 / not making it expensive for competitors), so the panel can flag families that need bid raises.
CREATE OR REPLACE VIEW `onyga-482313.OI.V_BUDGET_DEFENSE_FAMILY` AS
WITH fam AS (
  SELECT
    parent_name,
    ROUND(SUM(new_budget), 2)      AS weight,
    ROUND(SUM(new_budget), 2)      AS defense_allocated,
    ROUND(SUM(spend_day), 2)       AS defense_spend_7d,
    ROUND(SUM(current_budget), 2)  AS defense_current_budget,
    ROUND(SUM(net_profit_day), 2)  AS ads_net_profit_day,
    ROUND(SAFE_DIVIDE(SUM(net_profit_day) + SUM(spend_day), NULLIF(SUM(spend_day), 0)), 2) AS ads_net_roas,
    COUNT(*)                       AS n_defense
  FROM `onyga-482313.OI.V_BUDGET_STEP1_CAMPAIGN`
  WHERE is_defense
  GROUP BY parent_name
),
def_camps AS (SELECT campaign_id FROM `onyga-482313.OI.V_CAMPAIGN_BUDGET_BASE` WHERE is_defense),
kw AS (   -- per defense keyword (28d): latest bid + realized CPC
  SELECT k.parent_name, k.keyword_id,
    ARRAY_AGG(k.keyword_bid ORDER BY k.date DESC LIMIT 1)[OFFSET(0)] AS bid,
    SAFE_DIVIDE(SUM(k.cost), NULLIF(SUM(k.clicks), 0)) AS cpc
  FROM `onyga-482313.OI.V_KEYWORD_DAILY` k
  JOIN def_camps d ON d.campaign_id = k.campaign_id
  WHERE k.date >= DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL 28 DAY)
  GROUP BY k.parent_name, k.keyword_id
),
ub AS (   -- defense keywords under the 1.5× CPC dominance floor, per family
  SELECT parent_name, COUNTIF(cpc > 0 AND bid < 1.5 * cpc) AS n_underbid
  FROM kw GROUP BY parent_name
)
SELECT f.parent_name, f.weight, f.defense_allocated, f.defense_spend_7d, f.defense_current_budget,
  f.ads_net_profit_day, f.ads_net_roas, f.n_defense,
  COALESCE(ub.n_underbid, 0) AS n_underbid
FROM fam f LEFT JOIN ub ON ub.parent_name = f.parent_name;
