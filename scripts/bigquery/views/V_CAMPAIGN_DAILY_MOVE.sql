-- V_CAMPAIGN_DAILY_MOVE — the daily out-of-budget optimizer.
-- Evaluates each campaign on the last FULL-DATA day (the organic watermark, not half-settled calendar
-- yesterday — the orchestrator runs at midnight when yesterday's orders aren't in yet). For campaigns
-- that were OUT OF BUDGET that day (spent >= util% of their Amazon budget, or serving_status says so):
--   net ROAS < 0.8  -> BID_CUT  (no budget change; V_CAMPAIGN_BID_CUT trims the worst keywords)
--   0.8 .. 2.5      -> BUDGET_UP_10
--   >= 2.5          -> BUDGET_UP_30
-- Small-sample guard: < 10 clicks on the day -> use the trailing-7d net ROAS instead.
-- Within-cap reallocation (Ori 2026-07-05): targets are normalized to the family budget, so winners
-- rise and non-winners give ground while SUM(proposed_daily) per family == the family cap. Weekly re-base.
CREATE OR REPLACE VIEW `onyga-482313.OI.V_CAMPAIGN_DAILY_MOVE` AS
WITH cfg AS (
  SELECT
    MAX(IF(config_key='margin_roas_threshold', config_value, NULL)) AS margin,
    MAX(IF(config_key='boost_roas_threshold',  config_value, NULL)) AS boost,
    MAX(IF(config_key='budget_increase_pct',   config_value, NULL)) AS up1,
    MAX(IF(config_key='boost_increase_pct',    config_value, NULL)) AS up3,
    MAX(IF(config_key='out_of_budget_util',    config_value, NULL)) AS util
  FROM `onyga-482313.OI.DE_BUDGET_CONFIG`
),
wm AS (SELECT MAX(date) AS d FROM `onyga-482313.OI.FACT_AMAZON_PERFORMANCE_DAILY` WHERE Performance_TYPE='Organic'),
camp AS (
  SELECT campaign_id, daily_budget, serving_status
  FROM `onyga-482313.OI.DIM_CAMPAIGN`
  QUALIFY ROW_NUMBER() OVER (PARTITION BY campaign_id ORDER BY last_updated_date DESC) = 1
),
ads_perf AS (   -- watermark-day + trailing-7d ads, pre-aggregated (wm CROSS JOIN avoids a subquery-in-JOIN)
  SELECT a.campaign_id,
    SUM(IF(a.date = w.d, a.Ads_cost, 0))   AS d_spend,
    SUM(IF(a.date = w.d, a.Ads_clicks, 0))  AS d_clicks,
    SAFE_DIVIDE(SUM(IF(a.date=w.d, a.GROSS_PROFIT, 0)), NULLIF(SUM(IF(a.date=w.d, a.Ads_cost, 0)), 0)) AS d_roas,
    SAFE_DIVIDE(SUM(a.GROSS_PROFIT), NULLIF(SUM(a.Ads_cost), 0)) AS w7_roas
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` a
  CROSS JOIN wm w
  WHERE a.date BETWEEN DATE_SUB(w.d, INTERVAL 6 DAY) AND w.d
  GROUP BY a.campaign_id
),
perf AS (
  SELECT b.campaign_id, b.parent_name, b.base_daily,
    COALESCE(ap.d_spend, 0) AS d_spend, COALESCE(ap.d_clicks, 0) AS d_clicks,
    ap.d_roas, ap.w7_roas
  FROM `onyga-482313.OI.V_CAMPAIGN_BUDGET_BASE` b
  LEFT JOIN ads_perf ap USING (campaign_id)
),
scored AS (
  SELECT p.campaign_id, p.parent_name, p.base_daily,
    x.margin, x.boost, x.up1, x.up3,
    ((c.daily_budget IS NOT NULL AND p.d_spend >= x.util * c.daily_budget)
       OR c.serving_status = 'CAMPAIGN_OUT_OF_BUDGET') AS out_of_budget,
    IF(p.d_clicks >= 10, p.d_roas, p.w7_roas) AS net_roas
  FROM perf p JOIN camp c USING (campaign_id) CROSS JOIN cfg x
),
moved AS (
  SELECT campaign_id, parent_name, base_daily, out_of_budget, ROUND(net_roas, 2) AS net_roas,
    CASE WHEN NOT out_of_budget OR net_roas IS NULL THEN 'NONE'
         WHEN net_roas < margin  THEN 'BID_CUT'
         WHEN net_roas >= boost  THEN 'BUDGET_UP_30'
         ELSE 'BUDGET_UP_10' END AS move_type,
    base_daily * CASE WHEN NOT out_of_budget OR net_roas IS NULL OR net_roas < margin THEN 1.0
                      WHEN net_roas >= boost THEN 1 + up3 ELSE 1 + up1 END AS target_daily
  FROM scored
)
SELECT m.campaign_id, m.parent_name, ROUND(m.base_daily, 2) AS base_daily,
  m.out_of_budget, m.net_roas, m.move_type,
  ROUND(m.target_daily * SAFE_DIVIDE(f.allocated_daily,
        SUM(m.target_daily) OVER (PARTITION BY m.parent_name)), 2) AS proposed_daily
FROM moved m
JOIN `onyga-482313.OI.V_FAMILY_BUDGET_ALLOCATION` f USING (parent_name);
