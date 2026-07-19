-- V_FAMILY_WEEK_ADS_NET — ads-attributed net + spend per family x Sun–Sat week, straight from
-- V_WEEKLY_CELL_NET (the coacher source). Home's "Ads Net Profit" column reads THIS so it is
-- byte-identical to This Week / Weekly Run (same camp_parent attribution, same GROSS_PROFIT−Ads_cost),
-- instead of re-rolling ads by product/campaign-name in the frontend (which drifted ~$8).
CREATE OR REPLACE VIEW `onyga-482313.OI.V_FAMILY_WEEK_ADS_NET` AS
SELECT
  parent_name,
  CAST(week_start AS STRING) AS week_start,
  ROUND(SUM(net_profit), 2) AS ads_net,
  ROUND(SUM(spend), 2)      AS ads_spend
FROM `onyga-482313.OI.V_WEEKLY_CELL_NET`
GROUP BY parent_name, week_start
