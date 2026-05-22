-- V_EXPERIMENT_TEMPLATES: Experiments with ads performance summary
-- Replaces inline CTE in ExperimentTemplates cube (R2 compliance)
-- Grain: one row per experiment
CREATE OR REPLACE VIEW `onyga-482313`.OI.V_EXPERIMENT_TEMPLATES AS
WITH exp_data AS (
  SELECT
    e.strategy_id,
    e.experiment_id,
    e.experiment_name,
    e.description,
    e.status,
    CAST(e.start_date AS STRING) AS start_date,
    CAST(e.end_date AS STRING) AS end_date,
    e.baseline_days,
    e.outcome_score,
    e.outcome_tags,
    e.outcome_notes,
    e.lifecycle_stage,
    e.graduation_confidence,
    e.season_context,
    DATE_DIFF(COALESCE(e.end_date, CURRENT_DATE()), e.start_date, DAY) AS days_running
  FROM `onyga-482313`.OI.DIM_EXPERIMENT e
),
exp_perf AS (
  SELECT
    ec.experiment_id,
    ROUND(SUM(a.Ads_cost), 2) AS total_spend,
    SUM(a.Ads_orders) AS total_orders,
    SUM(a.Ads_clicks) AS total_clicks,
    SUM(a.Ads_impressions) AS total_impressions,
    ROUND(SUM(a.Ads_sales), 2) AS total_sales,
    ROUND(`onyga-482313`.OI.FN_NET_ROAS(SUM(a.Ads_sales), 0, SUM(a.Ads_cost)), 2) AS net_roas,
    ROUND(SAFE_DIVIDE(SUM(a.Ads_orders) * 100.0, NULLIF(SUM(a.Ads_clicks), 0)), 2) AS conv_rate,
    ROUND(SAFE_DIVIDE(SUM(a.Ads_cost), NULLIF(SUM(a.Ads_clicks), 0)), 2) AS cpc,
    COUNT(DISTINCT a.search_term) AS unique_search_terms
  FROM `onyga-482313`.OI.DIM_EXPERIMENT_CAMPAIGN ec
  JOIN `onyga-482313`.OI.FACT_AMAZON_ADS a
    ON ec.campaign_id = a.campaign_id
  WHERE a.Ads_cost > 0
  GROUP BY ec.experiment_id
)
SELECT
  d.strategy_id,
  d.experiment_id,
  d.experiment_name,
  d.description,
  d.status,
  d.start_date,
  d.end_date,
  d.baseline_days,
  d.outcome_score,
  d.outcome_tags,
  d.outcome_notes,
  d.lifecycle_stage,
  d.graduation_confidence,
  d.season_context,
  d.days_running,
  p.total_spend,
  p.total_orders,
  p.total_clicks,
  p.total_impressions,
  p.total_sales,
  p.net_roas,
  p.conv_rate,
  p.cpc,
  p.unique_search_terms
FROM exp_data d
LEFT JOIN exp_perf p ON d.experiment_id = p.experiment_id;
