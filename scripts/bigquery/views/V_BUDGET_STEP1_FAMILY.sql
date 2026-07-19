-- V_BUDGET_STEP1_FAMILY — one row per family for the Weekly Run Step-1 table.
-- Current allocation + weight inputs, PLUS the last-7-full-days spend split by tier (losing/margin/
-- winning/total), the family's actual last-7d CPC, and its current Amazon budget ceilings — so the
-- table shows the per-family "where the money went" beside the new budget. Reads V_ directly (small).
CREATE OR REPLACE VIEW `onyga-482313.OI.V_BUDGET_STEP1_FAMILY` AS
WITH cfg AS (
  SELECT MAX(IF(config_key='margin_roas_threshold', config_value, NULL)) AS margin,
         MAX(IF(config_key='boost_roas_threshold',  config_value, NULL)) AS boost
  FROM `onyga-482313.OI.DE_BUDGET_CONFIG`),
wm AS (SELECT MAX(date) AS d FROM `onyga-482313.OI.FACT_AMAZON_PERFORMANCE_DAILY` WHERE Performance_TYPE='Organic'),
camp AS (   -- per campaign over the 7 full days: spend + clicks + net ROAS
  SELECT a.campaign_id, SUM(a.Ads_cost) AS spend, SUM(a.Ads_clicks) AS clicks,
    SAFE_DIVIDE(SUM(a.GROSS_PROFIT), NULLIF(SUM(a.Ads_cost), 0)) AS net_roas
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` a CROSS JOIN wm w
  WHERE a.date BETWEEN DATE_SUB(w.d, INTERVAL 6 DAY) AND w.d
  GROUP BY a.campaign_id
),
tiers AS (   -- roll the campaign spend up to the family, split by ROAS tier
  SELECT m.parent_name,
    ROUND(SUM(IF(c.net_roas < (SELECT margin FROM cfg), c.spend, 0)), 0) AS losing_spend_7d,
    ROUND(SUM(IF(c.net_roas >= (SELECT margin FROM cfg) AND c.net_roas < (SELECT boost FROM cfg), c.spend, 0)), 0) AS margin_spend_7d,
    ROUND(SUM(IF(c.net_roas >= (SELECT boost FROM cfg), c.spend, 0)), 0) AS winning_spend_7d,
    ROUND(SUM(c.spend), 0) AS total_spend_7d,
    ROUND(SAFE_DIVIDE(SUM(c.spend), NULLIF(SUM(c.clicks), 0)), 2) AS last_cpc_7d
  FROM camp c JOIN `onyga-482313.OI.V_CAMPAIGN_FAMILY_MAP` m ON m.campaign_id = c.campaign_id
  GROUP BY m.parent_name
),
cur_budget AS (   -- family's current Amazon daily budget (sum of enabled campaigns' ceilings)
  SELECT m.parent_name, ROUND(SUM(dc.daily_budget), 0) AS current_budget
  FROM `onyga-482313.OI.V_CAMPAIGN_FAMILY_MAP` m
  JOIN (SELECT campaign_id, daily_budget FROM `onyga-482313.OI.DIM_CAMPAIGN`
        QUALIFY ROW_NUMBER() OVER (PARTITION BY campaign_id ORDER BY last_updated_date DESC)=1) dc
    USING (campaign_id)
  GROUP BY m.parent_name
)
SELECT a.parent_name, a.floor, a.allocated_daily, a.source,
  np.business_net_profit_avg, np.ads_net_profit_avg, np.weight,
  t.losing_spend_7d, t.margin_spend_7d, t.winning_spend_7d, t.total_spend_7d, t.last_cpc_7d,
  cb.current_budget
FROM `onyga-482313.OI.V_FAMILY_BUDGET_ALLOCATION` a
LEFT JOIN `onyga-482313.OI.V_FAMILY_NET_PROFIT_7D` np USING (parent_name)
LEFT JOIN tiers t USING (parent_name)
LEFT JOIN cur_budget cb USING (parent_name);
