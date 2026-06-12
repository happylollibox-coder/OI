-- V_CAMPAIGN_LAUNCH_MONTHLY
-- Purpose: First-3-month performance with MONTHLY BUCKETS per campaign.
--          M1 = days 0-30, M2 = days 30-60, M3 = days 60-90 from creation.
--          Includes ASIN + parent_name for Parent/Product filtering.
-- Dependencies: DIM_CAMPAIGN, FACT_AMAZON_ADS, DIM_EXPERIMENT_CAMPAIGN,
--               DIM_EXPERIMENT, DIM_STRATEGY_TEMPLATE, DIM_PRODUCT
-- Materialized to: T_CAMPAIGN_LAUNCH_MONTHLY (via SP_REFRESH_CUBE_TABLES)

CREATE OR REPLACE VIEW `onyga-482313.OI.V_CAMPAIGN_LAUNCH_MONTHLY` AS
WITH campaign_info AS (
  SELECT
    dc.campaign_id,
    dc.campaign_name,
    dc.campaign_type,
    dc.state AS campaign_state,
    CAST(dc.creation_date AS DATE) AS creation_date,
    ec.experiment_id,
    e.experiment_name,
    e.strategy_id,
    st.strategy_name
  FROM `onyga-482313.OI.DIM_CAMPAIGN` dc
  LEFT JOIN (
    SELECT campaign_id, experiment_id,
      ROW_NUMBER() OVER (PARTITION BY campaign_id ORDER BY CASE WHEN experiment_id = 'UNKNOWN' THEN 1 ELSE 0 END, experiment_id) AS rn
    FROM `onyga-482313.OI.DIM_EXPERIMENT_CAMPAIGN`
  ) ec ON dc.campaign_id = ec.campaign_id AND ec.rn = 1
  LEFT JOIN `onyga-482313.OI.DIM_EXPERIMENT` e ON ec.experiment_id = e.experiment_id
  LEFT JOIN `onyga-482313.OI.DIM_STRATEGY_TEMPLATE` st ON e.strategy_id = st.strategy_id
  WHERE dc.is_current = TRUE
),

-- Earliest date in FACT to detect pre-history campaigns
fact_bounds AS (
  SELECT MIN(date) AS earliest_fact_date
  FROM `onyga-482313.OI.FACT_AMAZON_ADS`
),

-- Primary ASIN per campaign (most-advertised by impressions)
campaign_asin AS (
  SELECT
    campaign_id,
    COALESCE(most_advertised_asin_impressions, ASIN_BY_CAMPAIGN_NAME) AS asin,
    SUM(Ads_impressions) AS total_impr
  FROM `onyga-482313.OI.FACT_AMAZON_ADS`
  WHERE COALESCE(most_advertised_asin_impressions, ASIN_BY_CAMPAIGN_NAME) IS NOT NULL
  GROUP BY 1, 2
),
campaign_primary_asin AS (
  SELECT campaign_id, asin
  FROM (
    SELECT campaign_id, asin,
      ROW_NUMBER() OVER (PARTITION BY campaign_id ORDER BY total_impr DESC) AS rn
    FROM campaign_asin
  )
  WHERE rn = 1
),

-- Monthly bucketed metrics (M1 = 0-30d, M2 = 30-60d, M3 = 60-90d)
monthly_metrics AS (
  SELECT
    ci.campaign_id,
    ci.campaign_name,
    ci.campaign_type,
    ci.campaign_state,
    ci.creation_date,
    COALESCE(ci.strategy_name, 'No Strategy') AS strategy_name,
    ci.experiment_id,
    ci.experiment_name,

    -- Data reliability
    CASE
      WHEN ci.creation_date >= fb.earliest_fact_date THEN 'reliable'
      WHEN ci.creation_date >= DATE_SUB(fb.earliest_fact_date, INTERVAL 7 DAY) THEN 'reliable'
      ELSE 'unreliable'
    END AS data_reliability,

    -- Last active date and end-date logic
    -- Use campaign_state as primary signal: ENABLED = Active (NULL end date)
    -- For non-ENABLED campaigns, show last activity date
    MAX(f.date) AS last_active_date,
    CASE
      WHEN ci.campaign_state = 'ENABLED' THEN NULL  -- Active / Delivering
      ELSE MAX(f.date)
    END AS end_date_display,

    -- Months active (for monthly avg)
    GREATEST(CEIL(DATE_DIFF(COALESCE(MAX(f.date), ci.creation_date), ci.creation_date, DAY) / 30.0), 1) AS months_active,

    -- All-time net profit (within 3-month window)
    ROUND(COALESCE(SUM(f.GROSS_PROFIT), 0) - COALESCE(SUM(f.Ads_cost), 0), 2) AS total_net_profit,

    -- Month 1: days 0-30
    COALESCE(SUM(CASE WHEN DATE_DIFF(f.date, ci.creation_date, DAY) < 30 THEN f.Ads_units END), 0) AS m1_units,
    ROUND(SAFE_DIVIDE(
      SUM(CASE WHEN DATE_DIFF(f.date, ci.creation_date, DAY) < 30 THEN f.Ads_cost END),
      NULLIF(SUM(CASE WHEN DATE_DIFF(f.date, ci.creation_date, DAY) < 30 THEN f.Ads_clicks END), 0)
    ), 2) AS m1_cpc,
    ROUND(COALESCE(SUM(CASE WHEN DATE_DIFF(f.date, ci.creation_date, DAY) < 30 THEN f.Ads_cost END), 0), 2) AS m1_ad_spend,
    ROUND(SAFE_DIVIDE(
      COALESCE(SUM(CASE WHEN DATE_DIFF(f.date, ci.creation_date, DAY) < 30 THEN f.GROSS_PROFIT END), 0)
        - COALESCE(SUM(CASE WHEN DATE_DIFF(f.date, ci.creation_date, DAY) < 30 THEN f.Ads_cost END), 0),
      NULLIF(SUM(CASE WHEN DATE_DIFF(f.date, ci.creation_date, DAY) < 30 THEN f.Ads_cost END), 0)
    ) + 1, 2) AS m1_net_roas,

    -- Month 2: days 30-60
    COALESCE(SUM(CASE WHEN DATE_DIFF(f.date, ci.creation_date, DAY) >= 30 AND DATE_DIFF(f.date, ci.creation_date, DAY) < 60 THEN f.Ads_units END), 0) AS m2_units,
    ROUND(SAFE_DIVIDE(
      SUM(CASE WHEN DATE_DIFF(f.date, ci.creation_date, DAY) >= 30 AND DATE_DIFF(f.date, ci.creation_date, DAY) < 60 THEN f.Ads_cost END),
      NULLIF(SUM(CASE WHEN DATE_DIFF(f.date, ci.creation_date, DAY) >= 30 AND DATE_DIFF(f.date, ci.creation_date, DAY) < 60 THEN f.Ads_clicks END), 0)
    ), 2) AS m2_cpc,
    ROUND(COALESCE(SUM(CASE WHEN DATE_DIFF(f.date, ci.creation_date, DAY) >= 30 AND DATE_DIFF(f.date, ci.creation_date, DAY) < 60 THEN f.Ads_cost END), 0), 2) AS m2_ad_spend,
    ROUND(SAFE_DIVIDE(
      COALESCE(SUM(CASE WHEN DATE_DIFF(f.date, ci.creation_date, DAY) >= 30 AND DATE_DIFF(f.date, ci.creation_date, DAY) < 60 THEN f.GROSS_PROFIT END), 0)
        - COALESCE(SUM(CASE WHEN DATE_DIFF(f.date, ci.creation_date, DAY) >= 30 AND DATE_DIFF(f.date, ci.creation_date, DAY) < 60 THEN f.Ads_cost END), 0),
      NULLIF(SUM(CASE WHEN DATE_DIFF(f.date, ci.creation_date, DAY) >= 30 AND DATE_DIFF(f.date, ci.creation_date, DAY) < 60 THEN f.Ads_cost END), 0)
    ) + 1, 2) AS m2_net_roas,

    -- Month 3: days 60-90
    COALESCE(SUM(CASE WHEN DATE_DIFF(f.date, ci.creation_date, DAY) >= 60 AND DATE_DIFF(f.date, ci.creation_date, DAY) < 90 THEN f.Ads_units END), 0) AS m3_units,
    ROUND(SAFE_DIVIDE(
      SUM(CASE WHEN DATE_DIFF(f.date, ci.creation_date, DAY) >= 60 AND DATE_DIFF(f.date, ci.creation_date, DAY) < 90 THEN f.Ads_cost END),
      NULLIF(SUM(CASE WHEN DATE_DIFF(f.date, ci.creation_date, DAY) >= 60 AND DATE_DIFF(f.date, ci.creation_date, DAY) < 90 THEN f.Ads_clicks END), 0)
    ), 2) AS m3_cpc,
    ROUND(COALESCE(SUM(CASE WHEN DATE_DIFF(f.date, ci.creation_date, DAY) >= 60 AND DATE_DIFF(f.date, ci.creation_date, DAY) < 90 THEN f.Ads_cost END), 0), 2) AS m3_ad_spend,
    ROUND(SAFE_DIVIDE(
      COALESCE(SUM(CASE WHEN DATE_DIFF(f.date, ci.creation_date, DAY) >= 60 AND DATE_DIFF(f.date, ci.creation_date, DAY) < 90 THEN f.GROSS_PROFIT END), 0)
        - COALESCE(SUM(CASE WHEN DATE_DIFF(f.date, ci.creation_date, DAY) >= 60 AND DATE_DIFF(f.date, ci.creation_date, DAY) < 90 THEN f.Ads_cost END), 0),
      NULLIF(SUM(CASE WHEN DATE_DIFF(f.date, ci.creation_date, DAY) >= 60 AND DATE_DIFF(f.date, ci.creation_date, DAY) < 90 THEN f.Ads_cost END), 0)
    ) + 1, 2) AS m3_net_roas

  FROM campaign_info ci
  CROSS JOIN fact_bounds fb
  LEFT JOIN `onyga-482313.OI.FACT_AMAZON_ADS` f
    ON ci.campaign_id = f.campaign_id
    AND f.date >= ci.creation_date
    AND f.date < DATE_ADD(ci.creation_date, INTERVAL 3 MONTH)
  GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9
)

-- Final output: join with primary ASIN + DIM_PRODUCT for parent_name
SELECT
  mm.*,
  cpa.asin,
  p.parent_name,
  ROUND(SAFE_DIVIDE(mm.total_net_profit, mm.months_active), 2) AS net_profit_monthly_avg
FROM monthly_metrics mm
LEFT JOIN campaign_primary_asin cpa ON mm.campaign_id = cpa.campaign_id
LEFT JOIN `onyga-482313.OI.DIM_PRODUCT` p ON cpa.asin = p.asin
WHERE mm.data_reliability = 'reliable';
