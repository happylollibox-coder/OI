-- V_CAMPAIGN_LAUNCH_PERF
-- Purpose: First-3-month performance metrics per campaign.
--          Shows how campaigns perform during their launch period
--          (creation_date → creation_date + 3 months).
-- Dependencies: DIM_CAMPAIGN, FACT_AMAZON_ADS, DIM_EXPERIMENT_CAMPAIGN,
--               DIM_EXPERIMENT, DIM_STRATEGY_TEMPLATE
-- Materialized to: T_CAMPAIGN_LAUNCH_PERF (via SP_REFRESH_CUBE_TABLES)
--
-- IMPORTANT: Only includes campaigns whose creation_date falls within our
-- FACT_AMAZON_ADS data range (data_reliability = 'reliable'). This avoids
-- showing misleading zero-performance for old campaigns created before
-- our data history began.

CREATE OR REPLACE VIEW `onyga-482313.OI.V_CAMPAIGN_LAUNCH_PERF` AS
WITH campaign_info AS (
  SELECT
    dc.campaign_id,
    dc.campaign_name,
    dc.campaign_type,
    dc.state as campaign_state,
    CAST(dc.creation_date AS DATE) as creation_date,
    DATE_ADD(CAST(dc.creation_date AS DATE), INTERVAL 3 MONTH) as window_end,
    ec.experiment_id,
    e.experiment_name,
    e.strategy_id,
    st.strategy_name
  FROM `onyga-482313.OI.DIM_CAMPAIGN` dc
  LEFT JOIN (
    -- Deduplicate: pick one experiment per campaign (prefer non-UNKNOWN)
    SELECT campaign_id, experiment_id,
      ROW_NUMBER() OVER (PARTITION BY campaign_id ORDER BY CASE WHEN experiment_id = 'UNKNOWN' THEN 1 ELSE 0 END, experiment_id) as rn
    FROM `onyga-482313.OI.DIM_EXPERIMENT_CAMPAIGN`
  ) ec ON dc.campaign_id = ec.campaign_id AND ec.rn = 1
  LEFT JOIN `onyga-482313.OI.DIM_EXPERIMENT` e ON ec.experiment_id = e.experiment_id
  LEFT JOIN `onyga-482313.OI.DIM_STRATEGY_TEMPLATE` st ON e.strategy_id = st.strategy_id
  WHERE dc.is_current = TRUE
),

-- Earliest date in FACT to detect pre-history campaigns
fact_bounds AS (
  SELECT MIN(date) as earliest_fact_date
  FROM `onyga-482313.OI.FACT_AMAZON_ADS`
),

launch_perf AS (
  SELECT
    ci.campaign_id,
    ci.campaign_name,
    ci.campaign_type,
    ci.campaign_state,
    ci.creation_date,
    ci.window_end,
    ci.experiment_id,
    ci.experiment_name,
    ci.strategy_id,
    COALESCE(ci.strategy_name, 'No Strategy') as strategy_name,
    DATE_DIFF(CURRENT_DATE(), ci.creation_date, DAY) as campaign_age_days,
    CASE
      WHEN DATE_DIFF(CURRENT_DATE(), ci.creation_date, DAY) < 90 THEN 'Under 3 months'
      ELSE 'Complete (3m+)'
    END as window_status,
    -- Data reliability: is creation_date within our FACT data range?
    -- 'reliable' = we have data from day 1 of the campaign
    -- 'unreliable' = campaign predates our data, metrics are incomplete
    CASE
      WHEN ci.creation_date >= fb.earliest_fact_date THEN 'reliable'
      WHEN ci.creation_date >= DATE_SUB(fb.earliest_fact_date, INTERVAL 7 DAY) THEN 'reliable'
      ELSE 'unreliable'
    END as data_reliability,
    -- First 3 month metrics
    COALESCE(SUM(f.Ads_units), 0) as units,
    COALESCE(SUM(f.Ads_clicks), 0) as clicks,
    COALESCE(SUM(f.Ads_impressions), 0) as impressions,
    COALESCE(SUM(f.Ads_orders), 0) as orders,
    ROUND(COALESCE(SUM(f.Ads_cost), 0), 2) as ad_spend,
    ROUND(COALESCE(SUM(f.Ads_sales), 0), 2) as ad_sales,
    ROUND(COALESCE(SUM(f.GROSS_PROFIT), 0), 2) as gross_profit,
    ROUND(COALESCE(SUM(f.GROSS_PROFIT), 0) - COALESCE(SUM(f.Ads_cost), 0), 2) as net_profit,
    ROUND(SAFE_DIVIDE(SUM(f.Ads_cost), NULLIF(SUM(f.Ads_clicks), 0)), 2) as cpc,
    ROUND(SAFE_DIVIDE(
      COALESCE(SUM(f.GROSS_PROFIT), 0) - COALESCE(SUM(f.Ads_cost), 0),
      NULLIF(SUM(f.Ads_cost), 0)
    ) + 1, 2) as net_roas,
    COUNT(DISTINCT f.date) as active_days
  FROM campaign_info ci
  CROSS JOIN fact_bounds fb
  LEFT JOIN `onyga-482313.OI.FACT_AMAZON_ADS` f
    ON ci.campaign_id = f.campaign_id
    AND f.date >= ci.creation_date
    AND f.date < ci.window_end
  GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13
)

-- Only output campaigns with reliable launch data
SELECT * FROM launch_perf
WHERE data_reliability = 'reliable';
