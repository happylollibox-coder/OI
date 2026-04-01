-- =============================================
-- OI Database Project - V_EXPERIMENT_RESULTS_ASIN View
-- =============================================
--
-- Purpose: ASIN-level comparison from FACT_AMAZON_PERFORMANCE_DAILY
--          Captures the halo effect: did overall ASIN performance improve?
--          Includes SEASONALLY-ADJUSTED lift using V_SEASONAL_INDEX_WEEKLY
-- Source: FACT_AMAZON_PERFORMANCE_DAILY (Business Reports) + FACT_AMAZON_ADS + V_SEASONAL_INDEX_WEEKLY
-- Prefix: performance_ (Business Reports) / ads_ (Amazon Ads campaign spend) / seasonal_ (adjusted)
-- Dependencies: DIM_EXPERIMENT, DIM_EXPERIMENT_CAMPAIGN, FACT_AMAZON_PERFORMANCE_DAILY, V_SEASONAL_INDEX_WEEKLY
-- Project: onyga-482313
-- Dataset: OI
--
-- =============================================

CREATE OR REPLACE VIEW `onyga-482313.OI.V_EXPERIMENT_RESULTS_ASIN`
AS
WITH experiment_asins AS (
  -- Get ASINs targeted by each experiment
  SELECT DISTINCT
    e.experiment_id,
    e.experiment_name,
    e.start_date,
    COALESCE(e.end_date, CURRENT_DATE()) as effective_end_date,
    e.baseline_days,
    DATE_SUB(e.start_date, INTERVAL e.baseline_days DAY) as baseline_start,
    fa.advertised_asins as asin
  FROM `onyga-482313.OI.DIM_EXPERIMENT` e
  JOIN `onyga-482313.OI.DIM_EXPERIMENT_CAMPAIGN` ec ON e.experiment_id = ec.experiment_id
  JOIN `onyga-482313.OI.FACT_AMAZON_ADS` fa
    ON ec.campaign_id = fa.campaign_id
    AND fa.date >= e.start_date
    AND (e.end_date IS NULL OR fa.date <= e.end_date)
  WHERE e.status IN ('ACTIVE', 'COMPLETED')
    AND fa.advertised_asins IS NOT NULL
),
-- ASIN performance during BASELINE (PERFORMANCE_ source: Business Reports)
baseline_perf AS (
  SELECT
    ea.experiment_id,
    ea.asin,
    COUNT(DISTINCT fp.DATE) as baseline_days,
    SUM(fp.PURCHASED_ORDERS) as performance_bl_total_orders,
    SUM(fp.PURCHASED_UNITS) as performance_bl_total_units,
    SUM(fp.PURCHASED_AMOUNT_USD) as performance_bl_total_sales,
    SUM(fp.ASIN_SESSIONS) as performance_bl_sessions,
    SUM(fp.ASIN_PAGE_VIEWS) as performance_bl_page_views,
    SUM(CASE WHEN fp.DATA_SOURCE = 'organic' THEN fp.PURCHASED_ORDERS ELSE 0 END) as performance_bl_organic_units,
    SUM(CASE WHEN fp.DATA_SOURCE = 'organic' THEN fp.PURCHASED_AMOUNT_USD ELSE 0 END) as performance_bl_organic_sales,
    SUM(CASE WHEN fp.DATA_SOURCE != 'organic' THEN fp.PURCHASED_ORDERS ELSE 0 END) as performance_bl_ads_orders,
    SUM(CASE WHEN fp.DATA_SOURCE != 'organic' THEN fp.PURCHASED_AMOUNT_USD ELSE 0 END) as performance_bl_ads_sales
  FROM experiment_asins ea
  JOIN `onyga-482313.OI.FACT_AMAZON_PERFORMANCE_DAILY` fp
    ON fp.PURCHASED_ASIN = ea.asin
    AND fp.DATE >= ea.baseline_start
    AND fp.DATE < ea.start_date
  GROUP BY 1, 2
),
-- ASIN performance during EXPERIMENT (PERFORMANCE_ source: Business Reports)
experiment_perf AS (
  SELECT
    ea.experiment_id,
    ea.asin,
    COUNT(DISTINCT fp.DATE) as experiment_days,
    SUM(fp.PURCHASED_ORDERS) as performance_exp_total_orders,
    SUM(fp.PURCHASED_UNITS) as performance_exp_total_units,
    SUM(fp.PURCHASED_AMOUNT_USD) as performance_exp_total_sales,
    SUM(fp.ASIN_SESSIONS) as performance_exp_sessions,
    SUM(fp.ASIN_PAGE_VIEWS) as performance_exp_page_views,
    SUM(CASE WHEN fp.DATA_SOURCE = 'organic' THEN fp.PURCHASED_ORDERS ELSE 0 END) as performance_exp_organic_units,
    SUM(CASE WHEN fp.DATA_SOURCE = 'organic' THEN fp.PURCHASED_AMOUNT_USD ELSE 0 END) as performance_exp_organic_sales,
    SUM(CASE WHEN fp.DATA_SOURCE != 'organic' THEN fp.PURCHASED_ORDERS ELSE 0 END) as performance_exp_ads_orders,
    SUM(CASE WHEN fp.DATA_SOURCE != 'organic' THEN fp.PURCHASED_AMOUNT_USD ELSE 0 END) as performance_exp_ads_sales,
    SUM(fp.GROSS_PROFIT) as performance_exp_gross_profit
  FROM experiment_asins ea
  JOIN `onyga-482313.OI.FACT_AMAZON_PERFORMANCE_DAILY` fp
    ON fp.PURCHASED_ASIN = ea.asin
    AND fp.DATE >= ea.start_date
    AND fp.DATE <= ea.effective_end_date
  GROUP BY 1, 2
),
-- Ad spend from experiment campaigns specifically (ADS_ source: FACT_AMAZON_ADS)
exp_ad_spend AS (
  SELECT
    e.experiment_id,
    fa.advertised_asins as asin,
    SUM(fa.Ads_cost) as ads_exp_campaign_cost,
    SUM(fa.Ads_sales) as ads_exp_campaign_sales,
    SUM(fa.Ads_orders) as ads_exp_campaign_orders
  FROM `onyga-482313.OI.DIM_EXPERIMENT` e
  JOIN `onyga-482313.OI.DIM_EXPERIMENT_CAMPAIGN` ec ON e.experiment_id = ec.experiment_id
  JOIN `onyga-482313.OI.FACT_AMAZON_ADS` fa
    ON ec.campaign_id = fa.campaign_id
    AND fa.date >= e.start_date
    AND (e.end_date IS NULL OR fa.date <= e.end_date)
  GROUP BY 1, 2
),
-- Seasonal index: average for baseline and experiment periods
seasonal_ref AS (
  SELECT iso_week, week_start, week_end, seasonal_index
  FROM `onyga-482313.OI.V_SEASONAL_INDEX_WEEKLY`
),
-- For baseline period, use date range (baseline is in 2025 so date ranges work)
baseline_seasonal_avg AS (
  SELECT
    ea.experiment_id,
    ea.asin,
    ROUND(AVG(si.seasonal_index), 4) as bl_seasonal_index
  FROM (SELECT DISTINCT experiment_id, asin, baseline_start, start_date FROM experiment_asins) ea
  LEFT JOIN seasonal_ref si
    ON si.week_end >= ea.baseline_start
    AND si.week_start < ea.start_date
  GROUP BY 1, 2
),
-- For experiment period, build a date spine and join by ISO week (handles 2026+ dates)
experiment_seasonal_avg AS (
  SELECT
    ea.experiment_id,
    ea.asin,
    ROUND(AVG(si.seasonal_index), 4) as exp_seasonal_index
  FROM (SELECT DISTINCT experiment_id, asin, start_date, effective_end_date FROM experiment_asins) ea,
  UNNEST(GENERATE_DATE_ARRAY(ea.start_date, ea.effective_end_date, INTERVAL 7 DAY)) as sample_date
  LEFT JOIN seasonal_ref si
    ON EXTRACT(ISOWEEK FROM sample_date) = si.iso_week
  GROUP BY 1, 2
)
SELECT
  -- Keys
  CONCAT(ea.experiment_id, '|', ea.asin) as row_key,
  CONCAT(ea.experiment_id, '|', ea.asin) as experiment_asin_key,

  ea.experiment_id,
  ea.experiment_name,
  ea.asin,

  -- Baseline metrics (PERFORMANCE_ source: Business Reports)
  COALESCE(bl.baseline_days, 0) as baseline_days,
  COALESCE(bl.performance_bl_total_orders, 0) as performance_baseline_total_orders,
  ROUND(COALESCE(bl.performance_bl_total_sales, 0), 2) as performance_baseline_total_sales,
  COALESCE(bl.performance_bl_organic_units, 0) as performance_baseline_organic_units,
  ROUND(COALESCE(bl.performance_bl_organic_sales, 0), 2) as performance_baseline_organic_sales,
  COALESCE(bl.performance_bl_sessions, 0) as performance_baseline_sessions,

  -- Experiment metrics (PERFORMANCE_ source: Business Reports)
  COALESCE(ep.experiment_days, 0) as experiment_days,
  COALESCE(ep.performance_exp_total_orders, 0) as performance_experiment_total_orders,
  ROUND(COALESCE(ep.performance_exp_total_sales, 0), 2) as performance_experiment_total_sales,
  COALESCE(ep.performance_exp_organic_units, 0) as performance_experiment_organic_units,
  ROUND(COALESCE(ep.performance_exp_organic_sales, 0), 2) as performance_experiment_organic_sales,
  COALESCE(ep.performance_exp_ads_orders, 0) as performance_experiment_ads_orders,
  ROUND(COALESCE(ep.performance_exp_ads_sales, 0), 2) as performance_experiment_ads_sales,
  COALESCE(ep.performance_exp_sessions, 0) as performance_experiment_sessions,
  ROUND(COALESCE(ep.performance_exp_gross_profit, 0), 2) as performance_experiment_gross_profit,

  -- Experiment campaign spend (ADS_ source: FACT_AMAZON_ADS)
  ROUND(COALESCE(es.ads_exp_campaign_cost, 0), 2) as ads_experiment_campaign_cost,
  ROUND(COALESCE(es.ads_exp_campaign_sales, 0), 2) as ads_experiment_campaign_revenue,
  -- Ads ROAS = actual ad sales / actual ad cost (ads data only)
  ROUND(SAFE_DIVIDE(es.ads_exp_campaign_sales, NULLIF(es.ads_exp_campaign_cost, 0)), 2) as ads_experiment_campaign_roas,
  -- Total ROAS = total ASIN sales (from Business Reports) / ad cost
  -- This is the true return: every dollar of ad spend vs ALL revenue the ASIN generated
  -- Total ROAS >= Ads ROAS always (total sales includes organic + ad sales)
  ROUND(SAFE_DIVIDE(ep.performance_exp_total_sales, NULLIF(es.ads_exp_campaign_cost, 0)), 2) as total_experiment_roas,

  -- Normalized daily averages (PERFORMANCE_ source: Business Reports)
  ROUND(SAFE_DIVIDE(bl.performance_bl_total_orders, NULLIF(bl.baseline_days, 0)), 2) as performance_baseline_avg_daily_orders,
  ROUND(SAFE_DIVIDE(ep.performance_exp_total_orders, NULLIF(ep.experiment_days, 0)), 2) as performance_experiment_avg_daily_orders,
  ROUND(SAFE_DIVIDE(bl.performance_bl_organic_units, NULLIF(bl.baseline_days, 0)), 2) as performance_baseline_avg_daily_organic,
  ROUND(SAFE_DIVIDE(ep.performance_exp_organic_units, NULLIF(ep.experiment_days, 0)), 2) as performance_experiment_avg_daily_organic,

  -- Lift calculations (PERFORMANCE_ source: Business Reports)
  ROUND(SAFE_DIVIDE(
    SAFE_DIVIDE(ep.performance_exp_total_orders, NULLIF(ep.experiment_days, 0))
    - SAFE_DIVIDE(bl.performance_bl_total_orders, NULLIF(bl.baseline_days, 0)),
    NULLIF(SAFE_DIVIDE(bl.performance_bl_total_orders, NULLIF(bl.baseline_days, 0)), 0)
  ) * 100, 1) as performance_total_orders_lift_pct,

  ROUND(SAFE_DIVIDE(
    SAFE_DIVIDE(ep.performance_exp_organic_units, NULLIF(ep.experiment_days, 0))
    - SAFE_DIVIDE(bl.performance_bl_organic_units, NULLIF(bl.baseline_days, 0)),
    NULLIF(SAFE_DIVIDE(bl.performance_bl_organic_units, NULLIF(bl.baseline_days, 0)), 0)
  ) * 100, 1) as performance_organic_units_lift_pct,

  ROUND(SAFE_DIVIDE(
    SAFE_DIVIDE(ep.performance_exp_sessions, NULLIF(ep.experiment_days, 0))
    - SAFE_DIVIDE(bl.performance_bl_sessions, NULLIF(bl.baseline_days, 0)),
    NULLIF(SAFE_DIVIDE(bl.performance_bl_sessions, NULLIF(bl.baseline_days, 0)), 0)
  ) * 100, 1) as performance_sessions_lift_pct,

  -- =============================================
  -- SEASONALLY-ADJUSTED lift calculations
  -- Adjusts baseline expectation by the ratio of experiment vs baseline seasonal indices
  -- =============================================
  ROUND(bsa.bl_seasonal_index, 4) as seasonal_index_baseline_avg,
  ROUND(esa.exp_seasonal_index, 4) as seasonal_index_experiment_avg,
  ROUND(SAFE_DIVIDE(esa.exp_seasonal_index, NULLIF(bsa.bl_seasonal_index, 0)), 4) as seasonal_adjustment_ratio,

  -- Seasonally-adjusted baseline daily average = raw baseline avg * (exp_season / bl_season)
  ROUND(
    SAFE_DIVIDE(bl.performance_bl_total_orders, NULLIF(bl.baseline_days, 0))
    * SAFE_DIVIDE(esa.exp_seasonal_index, NULLIF(bsa.bl_seasonal_index, 0))
  , 2) as performance_seasonal_adj_baseline_avg_daily_orders,

  ROUND(
    SAFE_DIVIDE(bl.performance_bl_organic_units, NULLIF(bl.baseline_days, 0))
    * SAFE_DIVIDE(esa.exp_seasonal_index, NULLIF(bsa.bl_seasonal_index, 0))
  , 2) as performance_seasonal_adj_baseline_avg_daily_organic,

  -- Seasonal total orders lift
  ROUND(SAFE_DIVIDE(
    SAFE_DIVIDE(ep.performance_exp_total_orders, NULLIF(ep.experiment_days, 0))
    - (SAFE_DIVIDE(bl.performance_bl_total_orders, NULLIF(bl.baseline_days, 0))
       * SAFE_DIVIDE(esa.exp_seasonal_index, NULLIF(bsa.bl_seasonal_index, 0))),
    NULLIF(
      SAFE_DIVIDE(bl.performance_bl_total_orders, NULLIF(bl.baseline_days, 0))
      * SAFE_DIVIDE(esa.exp_seasonal_index, NULLIF(bsa.bl_seasonal_index, 0)), 0)
  ) * 100, 1) as performance_seasonal_total_orders_lift_pct,

  -- Seasonal organic orders lift (THE KEY METRIC)
  ROUND(SAFE_DIVIDE(
    SAFE_DIVIDE(ep.performance_exp_organic_units, NULLIF(ep.experiment_days, 0))
    - (SAFE_DIVIDE(bl.performance_bl_organic_units, NULLIF(bl.baseline_days, 0))
       * SAFE_DIVIDE(esa.exp_seasonal_index, NULLIF(bsa.bl_seasonal_index, 0))),
    NULLIF(
      SAFE_DIVIDE(bl.performance_bl_organic_units, NULLIF(bl.baseline_days, 0))
      * SAFE_DIVIDE(esa.exp_seasonal_index, NULLIF(bsa.bl_seasonal_index, 0)), 0)
  ) * 100, 1) as performance_seasonal_organic_units_lift_pct

FROM (SELECT DISTINCT experiment_id, experiment_name, asin FROM experiment_asins) ea
LEFT JOIN baseline_perf bl ON ea.experiment_id = bl.experiment_id AND ea.asin = bl.asin
LEFT JOIN experiment_perf ep ON ea.experiment_id = ep.experiment_id AND ea.asin = ep.asin
LEFT JOIN exp_ad_spend es ON ea.experiment_id = es.experiment_id AND ea.asin = es.asin
LEFT JOIN baseline_seasonal_avg bsa ON ea.experiment_id = bsa.experiment_id AND ea.asin = bsa.asin
LEFT JOIN experiment_seasonal_avg esa ON ea.experiment_id = esa.experiment_id AND ea.asin = esa.asin;
