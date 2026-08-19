-- SP_SNAPSHOT_ADS_RESTATEMENT — append the current spend/sales for the last 16 report dates.
-- Called by SP_ORCHESTRATE_DAILY_REFRESH (3x/day), so each date is sampled ~3 times a day for
-- 16 days and the settle curve builds itself. Append-only and idempotent-safe: re-running just
-- adds another sample (a duplicate snapshot_at is harmless — the curve reads MAX per bucket).
-- 16 days covers the SB 14-day attribution window plus slack.
CREATE OR REPLACE PROCEDURE `onyga-482313.OI.SP_SNAPSHOT_ADS_RESTATEMENT`()
BEGIN
  INSERT INTO `onyga-482313.OI.FACT_ADS_RESTATEMENT`
    (report_date, snapshot_at, channel, spend, sales, orders, clicks, age_days)
  SELECT
    date AS report_date,
    CURRENT_TIMESTAMP() AS snapshot_at,
    COALESCE(campaign_type, 'UNKNOWN') AS channel,
    ROUND(SUM(Ads_cost), 2)  AS spend,
    ROUND(SUM(Ads_sales), 2) AS sales,
    SUM(Ads_orders)          AS orders,
    SUM(Ads_clicks)          AS clicks,
    DATE_DIFF(CURRENT_DATE('America/Los_Angeles'), date, DAY) AS age_days
  FROM `onyga-482313.OI.FACT_AMAZON_ADS`
  WHERE date >= DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL 16 DAY)
  GROUP BY date, campaign_type

  UNION ALL

  SELECT
    date, CURRENT_TIMESTAMP(), 'ALL',
    ROUND(SUM(Ads_cost), 2), ROUND(SUM(Ads_sales), 2), SUM(Ads_orders), SUM(Ads_clicks),
    DATE_DIFF(CURRENT_DATE('America/Los_Angeles'), date, DAY)
  FROM `onyga-482313.OI.FACT_AMAZON_ADS`
  WHERE date >= DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL 16 DAY)
  GROUP BY date;
END;
