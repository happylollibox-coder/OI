-- V_BUDGET_ROLE_FAMILY — one row per (family, role) for the Weekly Run Step-1 defense-type panels
-- (BRAND_DEFENSE + PRODUCT_DEFENSE). weight = backend allocation → the panel splits the live dial across
-- families proportionally to it. Carries spend / current / allocated budgets, ads net ROAS & net profit/day,
-- and n_underbid (BRAND_DEFENSE only: keywords bidding below 1.5x CPC — the dominance floor).
CREATE OR REPLACE VIEW `onyga-482313.OI.V_BUDGET_ROLE_FAMILY` AS
WITH fam AS (
  SELECT parent_name, role,
    ROUND(SUM(new_budget), 2)      AS weight,
    ROUND(SUM(new_budget), 2)      AS allocated,
    ROUND(SUM(spend_day), 2)       AS spend_7d,
    ROUND(SUM(current_budget), 2)  AS current_budget,
    ROUND(SUM(net_profit_day), 2)  AS ads_net_profit_day,
    ROUND(SAFE_DIVIDE(SUM(net_profit_day) + SUM(spend_day), NULLIF(SUM(spend_day), 0)), 2) AS ads_net_roas,
    COUNT(*)                       AS n
  FROM `onyga-482313.OI.V_BUDGET_STEP1_CAMPAIGN`
  WHERE role IN ('BRAND_DEFENSE', 'PRODUCT_DEFENSE')
  GROUP BY parent_name, role
),
bd_camps AS (SELECT campaign_id FROM `onyga-482313.OI.V_CAMPAIGN_BUDGET_BASE` WHERE role = 'BRAND_DEFENSE'),
kw AS (
  SELECT k.parent_name, k.keyword_id,
    ARRAY_AGG(k.keyword_bid ORDER BY k.date DESC LIMIT 1)[OFFSET(0)] AS bid,
    SAFE_DIVIDE(SUM(k.cost), NULLIF(SUM(k.clicks), 0)) AS cpc
  FROM `onyga-482313.OI.V_KEYWORD_DAILY` k
  JOIN bd_camps d ON d.campaign_id = k.campaign_id
  WHERE k.date >= DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL 28 DAY)
  GROUP BY k.parent_name, k.keyword_id
),
ub AS (SELECT parent_name, COUNTIF(cpc > 0 AND bid < 1.5 * cpc) AS n_underbid FROM kw GROUP BY parent_name)
SELECT f.parent_name, f.role, f.weight, f.allocated, f.spend_7d, f.current_budget,
  f.ads_net_profit_day, f.ads_net_roas, f.n,
  IF(f.role = 'BRAND_DEFENSE', COALESCE(ub.n_underbid, 0), 0) AS n_underbid
FROM fam f LEFT JOIN ub ON ub.parent_name = f.parent_name;
