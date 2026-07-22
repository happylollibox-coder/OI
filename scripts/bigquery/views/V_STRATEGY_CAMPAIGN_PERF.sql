-- V_STRATEGY_CAMPAIGN_PERF: per current campaign, resolved strategy + lifetime ads perf.
-- Grain: one row per campaign_id. active = had spend in the last 30 days.
CREATE OR REPLACE VIEW `onyga-482313.OI.V_STRATEGY_CAMPAIGN_PERF` AS
WITH perf AS (
  SELECT
    campaign_id,
    ROUND(SUM(Ads_cost), 2) AS spend,
    SUM(Ads_orders) AS orders,
    SUM(Ads_clicks) AS clicks,
    SUM(Ads_impressions) AS impressions,
    ROUND(SUM(Ads_sales), 2) AS sales,
    ROUND(`onyga-482313.OI.FN_NET_ROAS`(SUM(Ads_sales), 0, SUM(Ads_cost)), 2) AS net_roas,
    ROUND(SAFE_DIVIDE(SUM(Ads_orders) * 100.0, NULLIF(SUM(Ads_clicks), 0)), 2) AS conv_rate,
    ROUND(SAFE_DIVIDE(SUM(Ads_cost), NULLIF(SUM(Ads_clicks), 0)), 2) AS cpc,
    MAX(date) AS last_date,
    COUNTIF(date >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY) AND Ads_cost > 0) > 0 AS is_active
  FROM `onyga-482313.OI.FACT_AMAZON_ADS`
  GROUP BY campaign_id
)
SELECT
  r.campaign_id, r.campaign_name, r.campaign_type, r.parent_name,
  r.strategy_id, r.strategy_source,
  COALESCE(p.spend, 0) AS spend,
  COALESCE(p.orders, 0) AS orders,
  COALESCE(p.clicks, 0) AS clicks,
  COALESCE(p.impressions, 0) AS impressions,
  COALESCE(p.sales, 0) AS sales,
  p.net_roas, p.conv_rate, p.cpc, p.last_date,
  COALESCE(p.is_active, FALSE) AS is_active
FROM `onyga-482313.OI.V_CAMPAIGN_STRATEGY_RESOLVED` r
LEFT JOIN perf p USING (campaign_id);
