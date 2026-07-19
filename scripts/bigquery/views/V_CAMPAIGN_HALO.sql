-- V_CAMPAIGN_HALO — per-campaign forecast of the organic halo (v2, role-weighted by clicks).
-- The family halo (business net profit incl organic − ad-attributed net profit, per day, from
-- V_BUDGET_STEP1_FAMILY) is split across the family's campaigns by their WEIGHTED clicks, where the weight
-- (DE_HALO_WEIGHTS by strategy) reflects how much NEW organic demand a click creates: discovery ~1.0,
-- conquest ~0.7, exact ~0.5, brand-defense ~0.15 (brand searchers mostly recapture existing demand).
-- est_halo_day = family_halo × (campaign weighted clicks ÷ family weighted clicks). Last 7 full days.
CREATE OR REPLACE VIEW `onyga-482313.OI.V_CAMPAIGN_HALO` AS
WITH wm AS (SELECT MAX(date) AS d FROM `onyga-482313.OI.FACT_AMAZON_PERFORMANCE_DAILY` WHERE Performance_TYPE='Organic'),
cw AS (   -- campaign → max halo weight across its strategies (default 0.6 for unmapped)
  SELECT ec.campaign_id, MAX(COALESCE(hw.weight, 0.6)) AS weight
  FROM `onyga-482313.OI.DIM_EXPERIMENT_CAMPAIGN` ec
  JOIN `onyga-482313.OI.DIM_EXPERIMENT` e USING(experiment_id)
  LEFT JOIN `onyga-482313.OI.DE_HALO_WEIGHTS` hw ON hw.strategy_id = e.strategy_id
  GROUP BY ec.campaign_id
),
clk AS (   -- 7d clicks per campaign
  SELECT a.campaign_id, SUM(a.Ads_clicks) AS clicks
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` a CROSS JOIN wm w
  WHERE a.date BETWEEN DATE_SUB(w.d, INTERVAL 6 DAY) AND w.d
  GROUP BY a.campaign_id
),
campw AS (
  SELECT m.campaign_id, m.parent_name,
    COALESCE(clk.clicks, 0) AS clicks,
    COALESCE(clk.clicks, 0) * COALESCE(cw.weight, 0.6) AS wclicks
  FROM `onyga-482313.OI.V_CAMPAIGN_FAMILY_MAP` m
  LEFT JOIN clk ON clk.campaign_id = m.campaign_id
  LEFT JOIN cw  ON cw.campaign_id = m.campaign_id
),
famw AS (SELECT parent_name, SUM(wclicks) AS tot_wclicks FROM campw GROUP BY parent_name),
famhalo AS (SELECT parent_name, business_net_profit_avg - ads_net_profit_avg AS halo_day FROM `onyga-482313.OI.V_BUDGET_STEP1_FAMILY`)
SELECT c.campaign_id, c.parent_name, c.clicks,
  ROUND(GREATEST(COALESCE(fh.halo_day, 0), 0) * SAFE_DIVIDE(c.wclicks, NULLIF(fw.tot_wclicks, 0)), 2) AS est_halo_day
FROM campw c
LEFT JOIN famw fw ON fw.parent_name = c.parent_name
LEFT JOIN famhalo fh ON fh.parent_name = c.parent_name;
