-- V_BUDGET_TOTAL_SUGGESTION — profit-shaped suggested total + the 7-day spend-tier breakdown for Step 1.
-- Ori 2026-07-05: size the total so margin-or-winning campaigns (net ROAS >= margin) take ~proven% of it,
-- leaving the rest for new/experimental. suggested_total = margin-or-better daily spend / (proven%/100).
-- Also exposes the last-7-full-days spend split by tier (losing < margin_roas; margin between; winning >= boost)
-- so the panel can show 7d losing/margin/winning/total spend + current vs new daily budget.
CREATE OR REPLACE VIEW `onyga-482313.OI.V_BUDGET_TOTAL_SUGGESTION` AS
WITH cfg AS (
  SELECT MAX(IF(config_key='margin_roas_threshold', config_value, NULL)) AS margin,
         MAX(IF(config_key='boost_roas_threshold',  config_value, NULL)) AS boost
  FROM `onyga-482313.OI.DE_BUDGET_CONFIG`),
wm AS (SELECT MAX(date) AS d FROM `onyga-482313.OI.FACT_AMAZON_PERFORMANCE_DAILY` WHERE Performance_TYPE='Organic'),
camp AS (   -- per enabled campaign over the 7 full days: spend + net ROAS
  SELECT a.campaign_id,
    SUM(a.Ads_cost) AS spend,
    SAFE_DIVIDE(SUM(a.GROSS_PROFIT), NULLIF(SUM(a.Ads_cost), 0)) AS net_roas
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` a
  CROSS JOIN wm w
  WHERE a.date BETWEEN DATE_SUB(w.d, INTERVAL 6 DAY) AND w.d
  GROUP BY a.campaign_id
),
agg AS (
  SELECT
    SUM(IF(net_roas < (SELECT margin FROM cfg), spend, 0)) AS losing_spend_7d,
    SUM(IF(net_roas >= (SELECT margin FROM cfg) AND net_roas < (SELECT boost FROM cfg), spend, 0)) AS margin_spend_7d,
    SUM(IF(net_roas >= (SELECT boost FROM cfg), spend, 0)) AS winning_spend_7d,
    SUM(spend) AS total_spend_7d,
    SUM(IF(net_roas >= (SELECT margin FROM cfg), spend, 0)) / 7 AS margin_daily_spend,   -- >= margin, daily → the dial numerator
    SUM(spend) / 7 AS total_daily_spend
  FROM camp
),
np AS (
  SELECT ROUND(SUM(u.gross_margin - u.ad_cost) / 7, 0) AS avg_daily_net_profit_7d
  FROM `onyga-482313.OI.V_UNIFIED_DAILY` u CROSS JOIN wm w
  WHERE u.date BETWEEN DATE_SUB(w.d, INTERVAL 6 DAY) AND w.d
),
ceilings AS (
  SELECT ROUND(SUM(daily_budget), 0) AS current_budget_ceilings FROM (
    SELECT campaign_id, daily_budget FROM `onyga-482313.OI.DIM_CAMPAIGN`
    QUALIFY ROW_NUMBER() OVER (PARTITION BY campaign_id ORDER BY last_updated_date DESC)=1 AND state='ENABLED'
  )
),
cur AS (SELECT config_value AS current_setting FROM `onyga-482313.OI.DE_BUDGET_CONFIG` WHERE config_key='total_daily_budget')
SELECT
  ROUND(agg.margin_daily_spend, 0)        AS margin_campaign_daily_spend,   -- the dial numerator (>= margin, /day)
  ROUND(agg.losing_spend_7d, 0)           AS losing_spend_7d,
  ROUND(agg.margin_spend_7d, 0)           AS margin_spend_7d,
  ROUND(agg.winning_spend_7d, 0)          AS winning_spend_7d,
  ROUND(agg.total_spend_7d, 0)            AS total_spend_7d,
  ROUND(SAFE_DIVIDE(agg.margin_daily_spend, agg.total_daily_spend) * 100, 0)                        AS current_margin_pct,
  ROUND(SAFE_DIVIDE(agg.total_daily_spend - agg.margin_daily_spend, agg.total_daily_spend) * 100, 0) AS current_losing_new_pct,
  ROUND(agg.total_daily_spend, 0)         AS recent_avg_daily_spend,
  np.avg_daily_net_profit_7d              AS recent_avg_daily_net_profit,
  c.current_budget_ceilings,
  t.current_setting                       AS current_total_setting
FROM agg CROSS JOIN np CROSS JOIN ceilings c CROSS JOIN cur t;
