-- =============================================
-- Validation: Ads Performance - Portfolio Level
-- =============================================
-- Purpose: Validate Ads Performance hierarchy at Portfolio level for gap analysis vs Amazon Ads Console.
-- Source: dashboard/refresh_data.py QUERIES["ads_7d.json"] (lines 773-865)
-- Compare: Run this query, then compare to Amazon Ads Console Portfolio view for same date range.
--
-- Usage: Replace @start_date and @end_date with explicit dates (e.g. 2026-02-22 to 2026-02-28).
--        In BigQuery: use DECLARE or replace literals.
-- =============================================

-- Parameters (replace with your date range):
-- SET @start_date = DATE('2026-02-22');
-- SET @end_date = DATE('2026-02-28');

WITH row_asin AS (
  SELECT
    a.*,
    COALESCE(
      a.most_advertised_asin_impressions,
      a.most_advertised_asin_clicks,
      a.most_advertised_asin_purchased,
      TRIM(SPLIT(COALESCE(a.advertised_asins, ''), ',')[SAFE_OFFSET(0)])
    ) AS row_asin
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` a
  WHERE a.date BETWEEN DATE('2026-02-22') AND DATE('2026-02-28')
    AND (a.cost > 0 OR a.clicks > 0 OR a.orders > 0)
),
portfolio_agg AS (
  SELECT
    COALESCE(pf.portfolio_name, 'Unassigned') AS portfolio_name,
    ROUND(SUM(a.cost), 2) AS spend,
    ROUND(SUM(a.sales), 2) AS sales,
    SUM(a.orders) AS orders,
    SUM(a.clicks) AS clicks,
    SUM(a.impressions) AS impressions,
    ROUND(SAFE_DIVIDE(SUM(a.orders) * 100.0, NULLIF(SUM(a.clicks), 0)), 2) AS conv_rate,
    ROUND(SAFE_DIVIDE(SUM(a.cost), NULLIF(SUM(a.clicks), 0)), 2) AS cpc,
    ROUND(SAFE_DIVIDE(SUM(a.sales) - SUM(a.cost), NULLIF(SUM(a.cost), 0)), 2) AS roas,
    ROUND(SAFE_DIVIDE(SUM(a.clicks) * 100.0, NULLIF(SUM(a.impressions), 0)), 2) AS ctr_pct
  FROM row_asin a
  JOIN `onyga-482313.OI.DIM_PRODUCT` p
    ON p.asin = a.row_asin AND p.asin IS NOT NULL AND p.asin != 'UNKNOWN'
  LEFT JOIN `onyga-482313.OI.V_SRC_AmazonAds_campaign_history` ch
    ON a.campaign_id = ch.campaign_id
    AND TIMESTAMP(a.date) BETWEEN ch.OI_start_date AND ch.OI_end_date
  LEFT JOIN `onyga-482313.OI.V_SRC_AmazonAds_portfolio` pf
    ON ch.portfolio_id = pf.portfolio_id
    AND TIMESTAMP(a.date) BETWEEN pf.OI_start_date AND pf.OI_end_date
  GROUP BY 1
)
SELECT
  portfolio_name,
  spend,
  sales,
  orders,
  clicks,
  impressions,
  conv_rate,
  cpc,
  roas,
  ctr_pct
FROM portfolio_agg
ORDER BY spend DESC;
