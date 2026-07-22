-- V_STRATEGY_CAMPAIGN_WEEKLY: campaign×week ads perf with resolved strategy (Sunday weeks).
CREATE OR REPLACE VIEW `onyga-482313.OI.V_STRATEGY_CAMPAIGN_WEEKLY` AS
SELECT
  DATE_TRUNC(a.date, WEEK(SUNDAY)) AS week_start,
  a.campaign_id,
  r.campaign_name,
  r.parent_name,
  r.strategy_id,
  ROUND(SUM(a.Ads_cost), 2) AS spend,
  SUM(a.Ads_orders) AS orders,
  SUM(a.Ads_clicks) AS clicks,
  SUM(a.Ads_impressions) AS impressions,
  ROUND(SUM(a.Ads_sales), 2) AS sales,
  ROUND(`onyga-482313.OI.FN_NET_ROAS`(SUM(a.Ads_sales), 0, SUM(a.Ads_cost)), 2) AS net_roas
FROM `onyga-482313.OI.FACT_AMAZON_ADS` a
JOIN `onyga-482313.OI.V_CAMPAIGN_STRATEGY_RESOLVED` r USING (campaign_id)
WHERE a.Ads_cost > 0 OR a.Ads_impressions > 0
GROUP BY 1,2,3,4,5;
