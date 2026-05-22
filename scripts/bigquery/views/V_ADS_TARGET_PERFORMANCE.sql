-- V_ADS_TARGET_PERFORMANCE: Compares monthly ads targets vs actual performance.
-- Used for the feedback loop — validates the profit model's predictions.
-- Joins DE_PLAN_ADS_TARGETS (targets) with V_ADS_CHANNEL_EFFICIENCY (actuals).
CREATE OR REPLACE VIEW `onyga-482313`.OI.V_ADS_TARGET_PERFORMANCE AS
WITH targets AS (
  SELECT
    t.family,
    t.yr,
    t.mo,
    t.channel,
    t.daily_spend_target,
    t.cpc_target,
    t.predicted_cvr,
    t.predicted_roas,
    t.predicted_units,
    t.predicted_net_profit,
    t.season_type,
    t.multiplier_k,
    t.cpc_exponent,
    t.cvr_exponent,
    t.ads_share,
    t.created_at
  FROM `onyga-482313`.OI.DE_PLAN_ADS_TARGETS t
),

actuals AS (
  SELECT
    ce.family,
    ce.yr,
    ce.mo,
    ce.search_type AS channel,
    -- From V_ADS_CHANNEL_EFFICIENCY
    SAFE_DIVIDE(ce.spend, NULLIF(ce.active_days, 0)) AS actual_daily_spend,
    SAFE_DIVIDE(ce.spend, NULLIF(ce.clicks, 0)) AS actual_cpc,
    SAFE_DIVIDE(ce.units, NULLIF(ce.clicks, 0)) AS actual_cvr,
    ce.units AS actual_ad_units,
    ce.sales AS actual_ad_sales,
    ce.spend AS actual_total_spend,
    ce.active_days,
    ce.impressions AS actual_impressions,
    ce.clicks AS actual_clicks,
    ce.net_roas AS actual_net_roas
  FROM `onyga-482313`.OI.V_ADS_CHANNEL_EFFICIENCY ce
)

SELECT
  t.family,
  t.yr,
  t.mo,
  t.channel,
  t.season_type,
  t.multiplier_k,

  -- Targets
  t.daily_spend_target,
  t.cpc_target,
  t.predicted_cvr,
  t.predicted_roas,
  t.predicted_units,
  t.predicted_net_profit,

  -- Actuals
  a.actual_daily_spend,
  a.actual_cpc,
  a.actual_cvr,
  a.actual_ad_units,
  a.actual_ad_sales,
  a.actual_total_spend,
  a.active_days,
  a.actual_net_roas,

  -- Actual ROAS (simple: ad_sales / spend)
  SAFE_DIVIDE(a.actual_ad_sales, a.actual_total_spend) AS actual_gross_roas,

  -- Gaps (positive = over target, negative = under)
  ROUND(SAFE_DIVIDE(a.actual_daily_spend - t.daily_spend_target, NULLIF(t.daily_spend_target, 0)), 3) AS spend_gap_pct,
  ROUND(SAFE_DIVIDE(a.actual_cpc - t.cpc_target, NULLIF(t.cpc_target, 0)), 3) AS cpc_gap_pct,
  ROUND(SAFE_DIVIDE(a.actual_cvr - t.predicted_cvr, NULLIF(t.predicted_cvr, 0)), 3) AS cvr_accuracy_pct,

  -- Model accuracy (predicted vs actual units)
  ROUND(SAFE_DIVIDE(CAST(a.actual_ad_units AS FLOAT64) - t.predicted_units, NULLIF(t.predicted_units, 0)), 3) AS units_accuracy_pct,

  -- Data completeness (did we have a full month of data?)
  EXTRACT(DAY FROM DATE(t.yr, t.mo, 1) + INTERVAL 1 MONTH - INTERVAL 1 DAY) AS days_in_month,
  CASE
    WHEN a.active_days >= EXTRACT(DAY FROM DATE(t.yr, t.mo, 1) + INTERVAL 1 MONTH - INTERVAL 1 DAY) - 2
    THEN 'COMPLETE'
    WHEN a.active_days > 0 THEN 'PARTIAL'
    ELSE 'NO_DATA'
  END AS data_status,

  -- Model parameters (for recalibration analysis)
  t.cpc_exponent,
  t.cvr_exponent,
  t.ads_share,
  t.created_at AS target_created_at

FROM targets t
LEFT JOIN actuals a
  ON a.family = t.family
  AND a.yr = t.yr
  AND a.mo = t.mo
  AND a.channel = t.channel
ORDER BY t.family, t.yr, t.mo, t.channel;
