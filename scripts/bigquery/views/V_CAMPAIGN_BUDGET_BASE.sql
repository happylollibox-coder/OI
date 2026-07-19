-- V_CAMPAIGN_BUDGET_BASE — THREE independent pools (PPC toggle: Offense | Brand Defense | Product Defense).
--   role = BRAND_DEFENSE (own the brand SERP) / PRODUCT_DEFENSE (cross-sell learning) / OFFENSE (growth).
--   OFFENSE — tier by 7d net ROAS: LOSING (<margin) → $10 floor; MARGIN (margin..boost) → hold at
--     spend × (1 + margin_budget_headroom) (don't over-fund a steady campaign); WINNING (≥boost) → its
--     hold base PLUS the freed surplus of the family offense budget, split by 4w net profit (scale winners).
--   BRAND_DEFENSE  → defense_total_daily, family split by brand-defense spend, campaign split by spend, $10 floor.
--   PRODUCT_DEFENSE→ product_defense_total_daily, family split by count, each floored at $30 + net-profit surplus.
CREATE OR REPLACE VIEW `onyga-482313.OI.V_CAMPAIGN_BUDGET_BASE` AS
WITH cfg AS (
  SELECT MAX(IF(config_key='campaign_launch_floor_daily', config_value, NULL)) AS c_floor,
         MAX(IF(config_key='product_defense_floor_daily', config_value, NULL)) AS pd_floor,
         MAX(IF(config_key='defense_total_daily', config_value, NULL)) AS bd_total,
         MAX(IF(config_key='product_defense_total_daily', config_value, NULL)) AS pd_total,
         MAX(IF(config_key='margin_budget_headroom', config_value, NULL)) AS margin_hr,
         MAX(IF(config_key='boost_roas_threshold', config_value, NULL)) AS boost,
         MAX(IF(config_key='margin_roas_threshold', config_value, NULL)) AS margin
  FROM `onyga-482313.OI.DE_BUDGET_CONFIG`
),
wm AS (SELECT MAX(date) AS d FROM `onyga-482313.OI.FACT_AMAZON_PERFORMANCE_DAILY` WHERE Performance_TYPE='Organic'),
strat AS (
  SELECT ec.campaign_id,
    LOGICAL_OR(e.strategy_id = 'BRAND_DEFENSE')   AS has_brand_def,
    LOGICAL_OR(e.strategy_id = 'PRODUCT_DEFENSE') AS has_prod_def
  FROM `onyga-482313.OI.DIM_EXPERIMENT_CAMPAIGN` ec
  JOIN `onyga-482313.OI.DIM_EXPERIMENT` e USING(experiment_id)
  GROUP BY ec.campaign_id
),
camp AS (   -- 4w net profit (split weight) + spend (defense need)
  SELECT m.campaign_id, m.parent_name,
    COALESCE(SUM(a.GROSS_PROFIT - a.Ads_cost), 0) AS net_4w,
    COALESCE(SUM(a.Ads_cost), 0) AS spend_4w
  FROM `onyga-482313.OI.V_CAMPAIGN_FAMILY_MAP` m
  LEFT JOIN `onyga-482313.OI.FACT_AMAZON_ADS` a
    ON a.campaign_id = m.campaign_id
   AND a.date >= DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL 28 DAY)
  GROUP BY m.campaign_id, m.parent_name
),
perf7 AS (   -- last 7 full days: daily spend + net ROAS (drives offense tier + margin cap)
  SELECT a.campaign_id,
    SUM(a.Ads_cost) / 7 AS spend_day,
    SAFE_DIVIDE(SUM(a.GROSS_PROFIT), NULLIF(SUM(a.Ads_cost), 0)) AS net_roas_7d
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` a CROSS JOIN wm w
  WHERE a.date BETWEEN DATE_SUB(w.d, INTERVAL 6 DAY) AND w.d
  GROUP BY a.campaign_id
),
campx AS (
  SELECT c.campaign_id, c.parent_name, c.net_4w, c.spend_4w,
    COALESCE(p.spend_day, 0) AS spend_day,
    CASE WHEN COALESCE(s.has_brand_def, FALSE) THEN 'BRAND_DEFENSE'
         WHEN COALESCE(s.has_prod_def, FALSE)  THEN 'PRODUCT_DEFENSE'
         ELSE 'OFFENSE' END AS role,
    -- offense tier by 7d net ROAS
    CASE WHEN p.net_roas_7d >= (SELECT boost FROM cfg)  THEN 'WINNING'
         WHEN p.net_roas_7d >= (SELECT margin FROM cfg) THEN 'MARGIN'
         ELSE 'LOSING' END AS tier
  FROM camp c
  LEFT JOIN strat s ON s.campaign_id = c.campaign_id
  LEFT JOIN perf7 p ON p.campaign_id = c.campaign_id
),
offfam AS (SELECT parent_name, allocated_daily AS budget FROM `onyga-482313.OI.V_FAMILY_BUDGET_ALLOCATION`),
bdw  AS (SELECT parent_name, SUM(IF(role='BRAND_DEFENSE', GREATEST(spend_4w,0), 0)) AS w FROM campx GROUP BY parent_name),
bdt  AS (SELECT SUM(w) AS tot FROM bdw),
bdfam AS (SELECT b.parent_name, CASE WHEN t.tot>0 THEN (SELECT bd_total FROM cfg)*SAFE_DIVIDE(b.w,t.tot) ELSE 0 END AS budget FROM bdw b CROSS JOIN bdt t),
pdw  AS (SELECT parent_name, COUNTIF(role='PRODUCT_DEFENSE') AS n FROM campx GROUP BY parent_name),
pdt  AS (SELECT SUM(n) AS tot FROM pdw),
pdfam AS (SELECT p.parent_name, CASE WHEN t.tot>0 THEN (SELECT pd_total FROM cfg)*SAFE_DIVIDE(p.n,t.tot) ELSE 0 END AS budget FROM pdw p CROSS JOIN pdt t),
-- offense: each campaign has a target (losing→$10 floor; margin/winning→spend×(1+headroom)). If the targets
-- fit the family budget, WINNING campaigns split the surplus (scale). If they exceed it (poor family whose
-- campaigns spend more than its profit-based budget), all targets scale down to fit — the family budget is the cap.
offagg AS (
  SELECT c.parent_name, ANY_VALUE(f.budget) AS budget,
    COUNTIF(c.role='OFFENSE' AND c.tier='WINNING') AS n_win,
    SUM(IF(c.role='OFFENSE' AND c.tier='WINNING', GREATEST(c.net_4w,0), 0)) AS win_pos,
    SUM(IF(c.role='OFFENSE',
        CASE c.tier WHEN 'LOSING' THEN (SELECT c_floor FROM cfg)
                    ELSE c.spend_day * (1 + (SELECT margin_hr FROM cfg)) END, 0)) AS target_sum
  FROM campx c JOIN offfam f USING(parent_name) GROUP BY c.parent_name
),
offagg2 AS (
  SELECT *,
    CASE WHEN target_sum > budget AND target_sum > 0 THEN budget / target_sum ELSE 1.0 END AS scale,
    GREATEST(budget - target_sum, 0) AS surplus
  FROM offagg
),
bdagg AS (
  SELECT c.parent_name, ANY_VALUE(f.budget) AS budget, COUNTIF(c.role='BRAND_DEFENSE') AS n,
    SUM(IF(c.role='BRAND_DEFENSE', GREATEST(c.spend_4w,0), 0)) AS pos,
    LEAST((SELECT c_floor FROM cfg), SAFE_DIVIDE(ANY_VALUE(f.budget), NULLIF(COUNTIF(c.role='BRAND_DEFENSE'),0))) AS flr
  FROM campx c JOIN bdfam f USING(parent_name) GROUP BY c.parent_name),
pdagg AS (
  SELECT c.parent_name, ANY_VALUE(f.budget) AS budget, COUNTIF(c.role='PRODUCT_DEFENSE') AS n,
    SUM(IF(c.role='PRODUCT_DEFENSE', GREATEST(c.net_4w,0), 0)) AS pos
  FROM campx c JOIN pdfam f USING(parent_name) GROUP BY c.parent_name),
scored AS (
  SELECT c.campaign_id, c.parent_name, c.net_4w, c.role, c.tier,
    CASE c.role WHEN 'BRAND_DEFENSE' THEN COALESCE(bd.budget,0)
                WHEN 'PRODUCT_DEFENSE' THEN COALESCE(pd.budget,0)
                ELSE COALESCE(off.budget,0) END AS role_family_budget,
    CASE c.role
      WHEN 'OFFENSE' THEN
        (CASE c.tier WHEN 'LOSING' THEN (SELECT c_floor FROM cfg)
                     ELSE c.spend_day * (1 + (SELECT margin_hr FROM cfg)) END) * COALESCE(off.scale, 1.0)  -- target, scaled to fit
        + IF(c.tier='WINNING', COALESCE(off.surplus,0) * CASE WHEN off.win_pos>0 THEN SAFE_DIVIDE(GREATEST(c.net_4w,0), off.win_pos)
                                                             WHEN off.n_win>0 THEN 1.0/off.n_win ELSE 0 END, 0)  -- winners scale into surplus
      WHEN 'BRAND_DEFENSE' THEN IF(bd.n=0, 0,
        bd.flr + (bd.budget - bd.flr*bd.n) * CASE WHEN bd.pos>0 THEN SAFE_DIVIDE(GREATEST(c.spend_4w,0),bd.pos) ELSE 1.0/bd.n END)
      ELSE IF(pd.n=0, 0,
        (SELECT pd_floor FROM cfg) + GREATEST(pd.budget - (SELECT pd_floor FROM cfg)*pd.n, 0)
          * CASE WHEN pd.pos>0 THEN SAFE_DIVIDE(GREATEST(c.net_4w,0),pd.pos) ELSE 1.0/pd.n END)
    END AS base_daily
  FROM campx c
  LEFT JOIN offagg2 off ON off.parent_name=c.parent_name
  LEFT JOIN bdagg  bd  ON bd.parent_name=c.parent_name
  LEFT JOIN pdagg  pd  ON pd.parent_name=c.parent_name
)
SELECT campaign_id, parent_name,
  ROUND(role_family_budget, 2) AS family_budget,
  ROUND(net_4w, 2) AS ads_net_profit_4w,
  role,
  (role = 'BRAND_DEFENSE') AS is_defense,
  ROUND(base_daily, 2) AS base_daily,
  role = 'OFFENSE' AND tier = 'LOSING' AS is_floor
FROM scored;
