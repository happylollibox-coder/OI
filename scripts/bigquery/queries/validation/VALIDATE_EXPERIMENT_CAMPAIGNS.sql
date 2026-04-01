-- =============================================
-- Validation: Experiment campaigns (Experiment page)
-- =============================================
-- Purpose: Validate experiment_campaigns.json. Compare to dashboard Experiment page campaigns table.
-- Source: dashboard/refresh_data.py QUERIES["experiment_campaigns.json"] (lines 715-751)
-- Source: DIM_EXPERIMENT_CAMPAIGN, FACT_AMAZON_ADS (90 days)
-- =============================================

WITH mapped AS (
  SELECT experiment_id, campaign_id,
    top_of_search_pct, product_page_pct, rest_of_search_pct, notes
  FROM `onyga-482313.OI.DIM_EXPERIMENT_CAMPAIGN`
),
campaign_perf AS (
  SELECT campaign_id, campaign_name, campaign_type,
    ROUND(SUM(cost), 2) as spend,
    SUM(orders) as orders,
    SUM(clicks) as clicks,
    SUM(impressions) as impressions,
    CAST(MIN(date) AS STRING) as first_date,
    CAST(MAX(date) AS STRING) as last_date
  FROM `onyga-482313.OI.FACT_AMAZON_ADS`
  WHERE date >= DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY)
  GROUP BY campaign_id, campaign_name, campaign_type
  HAVING SUM(cost) > 0
)
SELECT
  m.experiment_id,
  cp.campaign_id,
  cp.campaign_name,
  cp.campaign_type,
  m.top_of_search_pct,
  m.product_page_pct,
  m.rest_of_search_pct,
  m.notes,
  cp.spend,
  cp.orders,
  cp.clicks,
  cp.impressions,
  cp.first_date,
  cp.last_date
FROM campaign_perf cp
LEFT JOIN mapped m ON cp.campaign_id = m.campaign_id
ORDER BY cp.spend DESC;
