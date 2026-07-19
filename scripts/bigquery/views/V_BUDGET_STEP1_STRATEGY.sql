-- V_BUDGET_STEP1_STRATEGY — one row per Coverage role (strategy) for the Weekly Run Step-1 strategy split,
-- the sibling of V_BUDGET_STEP1_FAMILY. Same columns, grouped by strategy_role instead of parent_name:
-- where the money went (last-7-full-days spend by ROAS tier), the role's actual CPC, its current Amazon
-- budget ceilings, and the waterfall's proposed new budget.
--
-- OFFENSE SUB-ROLES ONLY (AUTO / EXACT / BROAD / PHRASE / COMPETITOR / SB_VIDEO / OTHER). Brand and
-- product defense are separate PPC modes with their own budget panels — including them here would
-- double-count them against the offense split.
--
-- Rolled up from V_BUDGET_STEP1_CAMPAIGN so the strategy split and the campaign table can never
-- disagree: both read the same per-campaign new_budget. Reads V_ directly (small, config-driven).
CREATE OR REPLACE VIEW `onyga-482313.OI.V_BUDGET_STEP1_STRATEGY` AS
WITH cfg AS (
  SELECT MAX(IF(config_key='margin_roas_threshold', config_value, NULL)) AS margin,
         MAX(IF(config_key='boost_roas_threshold',  config_value, NULL)) AS boost
  FROM `onyga-482313.OI.DE_BUDGET_CONFIG`),
wm AS (SELECT MAX(date) AS d FROM `onyga-482313.OI.FACT_AMAZON_PERFORMANCE_DAILY` WHERE Performance_TYPE='Organic'),
camp AS (   -- per campaign over the 7 full days: spend + clicks (net ROAS tier comes from the step-1 view)
  SELECT CAST(a.campaign_id AS STRING) AS campaign_id,
    SUM(a.Ads_cost) AS spend, SUM(a.Ads_clicks) AS clicks
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` a CROSS JOIN wm w
  WHERE a.date BETWEEN DATE_SUB(w.d, INTERVAL 6 DAY) AND w.d
  GROUP BY 1
)
SELECT
  s.strategy_category AS strategy_role,   -- column name kept for cube/frontend compat; now the STRATEGY grain
  COUNT(*)                                AS n_campaigns,
  ROUND(SUM(IF(s.net_roas < (SELECT margin FROM cfg), c.spend, 0)), 0) AS losing_spend_7d,
  ROUND(SUM(IF(s.net_roas >= (SELECT margin FROM cfg) AND s.net_roas < (SELECT boost FROM cfg), c.spend, 0)), 0) AS margin_spend_7d,
  ROUND(SUM(IF(s.net_roas >= (SELECT boost FROM cfg), c.spend, 0)), 0) AS winning_spend_7d,
  ROUND(SUM(c.spend), 0)                  AS total_spend_7d,
  -- Spend-weighted, not an average of per-campaign CPCs: campaigns differ hugely in click volume.
  ROUND(SAFE_DIVIDE(SUM(c.spend), NULLIF(SUM(c.clicks), 0)), 2) AS last_cpc_7d,
  ROUND(SUM(s.net_profit_day), 2)         AS ads_net_profit_avg,
  ROUND(SUM(s.net_incl_halo), 2)          AS net_incl_halo_avg,
  ROUND(SUM(s.current_budget), 0)         AS current_budget,
  ROUND(SUM(s.new_budget), 2)             AS allocated_daily
FROM `onyga-482313.OI.V_BUDGET_STEP1_CAMPAIGN` s
LEFT JOIN camp c ON c.campaign_id = s.campaign_id
-- Cross-pool (Ori 2026-07-18): all six strategies incl brand/product defense. The offense-only filter
-- was dropped so the table is a full strategy overview. NOTE: this means the split total now includes
-- defense budget, so it no longer equals the offense pool.
GROUP BY s.strategy_category;
