-- V_BUDGET_STEP1_AGE — one row per age bucket for the Weekly Run "Budget by age" split, the sibling of
-- V_BUDGET_STEP1_STRATEGY. Same columns, grouped by age_bucket (NEW <=20d / 1-3MO / 4-9MO / 10MO+)
-- instead of strategy_role: last-7-full-days spend by ROAS tier, actual CPC, current Amazon budget,
-- and the waterfall's proposed new budget. Lets the age table match the strategy table exactly and act
-- as a filter over the same per-campaign rows.
--
-- Rolled up from V_BUDGET_STEP1_CAMPAIGN so the age split and the campaign table can never disagree —
-- both read the same per-campaign new_budget and tier. Reads V_ directly (small, config-driven).
CREATE OR REPLACE VIEW `onyga-482313.OI.V_BUDGET_STEP1_AGE` AS
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
  s.age_bucket,
  COUNT(*)                                AS n_campaigns,
  ROUND(SUM(IF(s.net_roas < (SELECT margin FROM cfg), c.spend, 0)), 0) AS losing_spend_7d,
  ROUND(SUM(IF(s.net_roas >= (SELECT margin FROM cfg) AND s.net_roas < (SELECT boost FROM cfg), c.spend, 0)), 0) AS margin_spend_7d,
  ROUND(SUM(IF(s.net_roas >= (SELECT boost FROM cfg), c.spend, 0)), 0) AS winning_spend_7d,
  ROUND(SUM(c.spend), 0)                  AS total_spend_7d,
  ROUND(SAFE_DIVIDE(SUM(c.spend), NULLIF(SUM(c.clicks), 0)), 2) AS last_cpc_7d,   -- spend-weighted, like strategy
  ROUND(SUM(s.net_profit_day), 2)         AS ads_net_profit_avg,
  ROUND(SUM(s.current_budget), 0)         AS current_budget,
  ROUND(SUM(s.new_budget), 2)             AS allocated_daily
FROM `onyga-482313.OI.V_BUDGET_STEP1_CAMPAIGN` s
LEFT JOIN camp c ON c.campaign_id = s.campaign_id
WHERE s.age_bucket IS NOT NULL
GROUP BY s.age_bucket;
