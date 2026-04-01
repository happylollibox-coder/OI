-- =============================================
-- OI Database Project - V_EXPERIMENT_SUMMARY View
-- =============================================
--
-- Purpose: One-row scorecard per experiment combining search term + ASIN results
-- Prefix convention:
--   search_*      = from SQP via V_EXPERIMENT_RESULTS_SEARCH_TERM
--   performance_* = from Business Reports via V_EXPERIMENT_RESULTS_ASIN
--   ads_*         = from Amazon Ads via V_EXPERIMENT_RESULTS_ASIN
-- Dependencies: V_EXPERIMENT_RESULTS_SEARCH_TERM, V_EXPERIMENT_RESULTS_ASIN, DIM_EXPERIMENT
-- Project: onyga-482313
-- Dataset: OI
--
-- =============================================

CREATE OR REPLACE VIEW `onyga-482313.OI.V_EXPERIMENT_SUMMARY`
AS
WITH
-- =============================================
-- Unit economics per ASIN (reusable pattern: DIM_PRODUCT + DIM_COSTS_HISTORY)
-- selling_price - TOTAL_COST_PER_UNIT = margin_per_unit
-- Uses DIM_COSTS_HISTORY.TOTAL_COST_PER_UNIT for margin calculation
-- =============================================
asin_unit_economics AS (
  SELECT
    p.asin,
    p.listing_price_amount as selling_price,
    COALESCE(ch.TOTAL_COST_PER_UNIT, 0) as total_cost_per_unit,
    p.listing_price_amount - COALESCE(ch.TOTAL_COST_PER_UNIT, 0) as margin_per_unit
  FROM `onyga-482313.OI.DIM_PRODUCT` p
  LEFT JOIN (
    SELECT asin, TOTAL_COST_PER_UNIT,
      ROW_NUMBER() OVER (PARTITION BY asin ORDER BY end_date DESC) as rn
    FROM `onyga-482313.OI.DIM_COSTS_HISTORY`
  ) ch ON p.asin = ch.asin AND ch.rn = 1
  WHERE p.asin IS NOT NULL
),

search_term_summary AS (
  SELECT
    experiment_id,
    COUNT(DISTINCT search_term) as tracked_search_terms,
    SUM(search_experiment_total_orders) as search_exp_total_orders,
    SUM(search_ads_experiment_orders) as search_ads_exp_orders,
    SUM(search_experiment_organic_units) as search_exp_organic_units,
    SUM(search_baseline_total_orders) as search_bl_total_orders,
    SUM(search_baseline_organic_units) as search_bl_organic_units,
    COUNTIF(search_organic_units_lift_pct > 0) as terms_with_positive_lift,
    COUNTIF(search_organic_units_lift_pct < 0) as terms_with_negative_lift,
    COUNTIF(search_organic_units_lift_pct IS NULL OR search_organic_units_lift_pct = 0) as terms_neutral,
    ROUND(AVG(CASE WHEN search_organic_units_lift_pct IS NOT NULL THEN search_organic_units_lift_pct END), 1) as search_avg_organic_lift_pct,
    -- Normalized (seasonal-free) search term lifts using TOTAL orders (reliable)
    COUNTIF(normalized_total_lift_pct > 0) as terms_seasonal_positive_lift,
    COUNTIF(normalized_total_lift_pct < 0) as terms_seasonal_negative_lift,
    ROUND(AVG(CASE WHEN normalized_total_lift_pct IS NOT NULL THEN normalized_total_lift_pct END), 1) as search_normalized_avg_total_lift_pct,
    -- Organic data reliability
    COUNTIF(organic_data_unreliable) as terms_with_unreliable_organic,
    -- Ads ROAS aggregated across search terms
    ROUND(SAFE_DIVIDE(SUM(ads_term_sales), NULLIF(SUM(ads_term_cost), 0)), 2) as search_ads_roas,
    -- Amazon market potential (total Amazon orders across all tracked terms)
    SUM(search_baseline_amazon_orders) as search_bl_amazon_total_orders,
    SUM(search_experiment_amazon_orders) as search_exp_amazon_total_orders,

    -- SQP Share Metrics: weighted averages across search terms
    -- Baseline shares (aggregated: sum(yours) / sum(amazon))
    ROUND(SAFE_DIVIDE(
      SUM(search_baseline_impressions),
      NULLIF(SUM(search_baseline_amazon_impressions), 0)
    ) * 100, 2) as search_bl_impressions_share_pct,
    ROUND(SAFE_DIVIDE(
      SUM(search_baseline_clicks),
      NULLIF(SUM(search_baseline_amazon_clicks), 0)
    ) * 100, 2) as search_bl_clicks_share_pct,
    ROUND(SAFE_DIVIDE(
      SUM(search_baseline_cart_adds),
      NULLIF(SUM(search_baseline_amazon_cart_adds), 0)
    ) * 100, 2) as search_bl_cart_adds_share_pct,
    ROUND(SAFE_DIVIDE(
      SUM(search_baseline_total_orders),
      NULLIF(SUM(search_baseline_amazon_orders), 0)
    ) * 100, 2) as search_bl_orders_share_pct,
    ROUND(SAFE_DIVIDE(
      SUM(search_baseline_total_orders),
      NULLIF(SUM(search_baseline_clicks), 0)
    ) * 100, 2) as search_bl_conversion_rate_pct,
    ROUND(SAFE_DIVIDE(
      SUM(search_baseline_clicks),
      NULLIF(SUM(search_baseline_impressions), 0)
    ) * 100, 2) as search_bl_ctr_pct,

    -- Experiment shares (aggregated)
    ROUND(SAFE_DIVIDE(
      SUM(search_experiment_impressions),
      NULLIF(SUM(search_experiment_amazon_impressions), 0)
    ) * 100, 2) as search_exp_impressions_share_pct,
    ROUND(SAFE_DIVIDE(
      SUM(search_experiment_clicks),
      NULLIF(SUM(search_experiment_amazon_clicks), 0)
    ) * 100, 2) as search_exp_clicks_share_pct,
    ROUND(SAFE_DIVIDE(
      SUM(search_experiment_cart_adds),
      NULLIF(SUM(search_experiment_amazon_cart_adds), 0)
    ) * 100, 2) as search_exp_cart_adds_share_pct,
    ROUND(SAFE_DIVIDE(
      SUM(search_experiment_total_orders),
      NULLIF(SUM(search_experiment_amazon_orders), 0)
    ) * 100, 2) as search_exp_orders_share_pct,
    ROUND(SAFE_DIVIDE(
      SUM(search_experiment_total_orders),
      NULLIF(SUM(search_experiment_clicks), 0)
    ) * 100, 2) as search_exp_conversion_rate_pct,
    ROUND(SAFE_DIVIDE(
      SUM(search_experiment_clicks),
      NULLIF(SUM(search_experiment_impressions), 0)
    ) * 100, 2) as search_exp_ctr_pct
  FROM `onyga-482313.OI.V_EXPERIMENT_RESULTS_SEARCH_TERM`
  GROUP BY 1
),
asin_summary AS (
  SELECT
    experiment_id,
    COUNT(DISTINCT asin) as tracked_asins,
    SUM(performance_baseline_total_orders) as performance_bl_total_orders,
    SUM(performance_baseline_organic_units) as performance_bl_organic_units,
    ROUND(SUM(performance_baseline_total_sales), 2) as performance_bl_total_sales,
    SUM(performance_experiment_total_orders) as performance_exp_total_orders,
    SUM(performance_experiment_organic_units) as performance_exp_organic_units,
    ROUND(SUM(performance_experiment_total_sales), 2) as performance_exp_total_sales,
    ROUND(SUM(ads_experiment_campaign_cost), 2) as ads_total_experiment_cost,
    ROUND(SUM(ads_experiment_campaign_revenue), 2) as ads_total_experiment_revenue,
    ROUND(AVG(ads_experiment_campaign_roas), 2) as ads_avg_roas,
    -- Total ROAS = total ASIN sales / ad cost (always >= ads_avg_roas)
    ROUND(SAFE_DIVIDE(SUM(performance_experiment_total_sales), NULLIF(SUM(ads_experiment_campaign_cost), 0)), 2) as total_avg_roas,
    ROUND(SUM(performance_experiment_gross_profit), 2) as performance_total_gross_profit,
    ROUND(AVG(performance_total_orders_lift_pct), 1) as performance_avg_total_lift_pct,
    ROUND(AVG(performance_organic_units_lift_pct), 1) as performance_avg_organic_lift_pct,
    ROUND(AVG(performance_sessions_lift_pct), 1) as performance_avg_sessions_lift_pct,
    -- Seasonal-adjusted ASIN lifts
    ROUND(AVG(seasonal_adjustment_ratio), 4) as seasonal_adjustment_ratio,
    ROUND(AVG(performance_seasonal_total_orders_lift_pct), 1) as performance_seasonal_avg_total_lift_pct,
    ROUND(AVG(performance_seasonal_organic_units_lift_pct), 1) as performance_seasonal_avg_organic_lift_pct
  FROM `onyga-482313.OI.V_EXPERIMENT_RESULTS_ASIN`
  GROUP BY 1
),

-- =============================================
-- Net ROAS per experiment (aggregated from daily snapshots)
-- net_revenue = TOTAL_units * margin_per_unit (includes organic halo)
-- net_roas = net_revenue / ad_spend (> 1.0 = profitable)
-- =============================================
experiment_net_roas AS (
  SELECT
    fed.experiment_id,
    SUM(fed.performance_total_units) as total_units,
    SUM(fed.ads_exp_units) as ads_units,
    ROUND(AVG(ue.margin_per_unit), 2) as avg_margin_per_unit,
    ROUND(SUM(fed.performance_total_units * ue.margin_per_unit), 2) as net_revenue,
    ROUND(SUM(fed.ads_exp_units * ue.margin_per_unit), 2) as ads_only_net_revenue,
    ROUND(SUM(fed.ads_exp_cost), 2) as net_roas_ad_spend
  FROM `onyga-482313.OI.FACT_EXPERIMENT_DAILY` fed
  JOIN asin_unit_economics ue ON fed.asin = ue.asin
  GROUP BY 1
)

SELECT
  -- Keys
  e.experiment_id as row_key,

  e.experiment_id,
  e.experiment_name,
  e.description,
  e.status,
  e.start_date,
  e.end_date,
  DATE_DIFF(COALESCE(e.end_date, CURRENT_DATE()), e.start_date, DAY) as days_running,
  e.baseline_days,
  e.outcome_score,
  e.outcome_tags,

  -- Search Term Level (SEARCH_ source: SQP)
  COALESCE(st.tracked_search_terms, 0) as tracked_search_terms,
  COALESCE(st.terms_with_positive_lift, 0) as terms_positive_organic_lift,
  COALESCE(st.terms_with_negative_lift, 0) as terms_negative_organic_lift,
  COALESCE(st.terms_neutral, 0) as terms_neutral,
  st.search_avg_organic_lift_pct,
  -- Normalized (seasonal-free) search term counts (using TOTAL orders, not organic)
  COALESCE(st.terms_seasonal_positive_lift, 0) as terms_normalized_positive_total_lift,
  COALESCE(st.terms_seasonal_negative_lift, 0) as terms_normalized_negative_total_lift,
  st.search_normalized_avg_total_lift_pct,
  -- Organic data reliability
  COALESCE(st.terms_with_unreliable_organic, 0) as terms_with_unreliable_organic,
  st.search_ads_roas,
  -- Amazon market potential
  COALESCE(st.search_bl_amazon_total_orders, 0) as search_baseline_amazon_total_orders,
  COALESCE(st.search_exp_amazon_total_orders, 0) as search_experiment_amazon_total_orders,

  -- ASIN Level (PERFORMANCE_ source: Business Reports)
  COALESCE(a.tracked_asins, 0) as tracked_asins,
  COALESCE(a.performance_bl_total_orders, 0) as performance_baseline_total_orders,
  COALESCE(a.performance_exp_total_orders, 0) as performance_experiment_total_orders,
  COALESCE(a.performance_bl_organic_units, 0) as performance_baseline_organic_units,
  COALESCE(a.performance_exp_organic_units, 0) as performance_experiment_organic_units,
  ROUND(COALESCE(a.performance_bl_total_sales, 0), 2) as performance_baseline_total_sales,
  ROUND(COALESCE(a.performance_exp_total_sales, 0), 2) as performance_experiment_total_sales,
  a.performance_avg_total_lift_pct as performance_total_orders_lift_pct,
  a.performance_avg_organic_lift_pct as performance_organic_units_lift_pct,
  a.performance_avg_sessions_lift_pct as performance_sessions_lift_pct,
  -- Seasonal-adjusted ASIN lifts
  a.seasonal_adjustment_ratio,
  a.performance_seasonal_avg_total_lift_pct as performance_seasonal_total_orders_lift_pct,
  a.performance_seasonal_avg_organic_lift_pct as performance_seasonal_organic_units_lift_pct,

  -- Ad Efficiency (ADS_ source: FACT_AMAZON_ADS)
  COALESCE(a.ads_total_experiment_cost, 0) as ads_total_spend,
  COALESCE(a.ads_total_experiment_revenue, 0) as ads_total_revenue,
  a.ads_avg_roas,
  -- Total ROAS = total ASIN revenue / ad cost (always >= ads_avg_roas)
  a.total_avg_roas,
  COALESCE(a.performance_total_gross_profit, 0) as performance_total_gross_profit,

  -- =============================================
  -- SQP SHARE METRICS: Baseline vs Experiment
  -- =============================================
  -- Baseline shares
  st.search_bl_impressions_share_pct,
  st.search_bl_clicks_share_pct,
  st.search_bl_cart_adds_share_pct,
  st.search_bl_orders_share_pct,
  st.search_bl_conversion_rate_pct,
  st.search_bl_ctr_pct,

  -- Experiment shares
  st.search_exp_impressions_share_pct,
  st.search_exp_clicks_share_pct,
  st.search_exp_cart_adds_share_pct,
  st.search_exp_orders_share_pct,
  st.search_exp_conversion_rate_pct,
  st.search_exp_ctr_pct,

  -- Share deltas (experiment - baseline, in percentage points)
  ROUND(COALESCE(st.search_exp_impressions_share_pct, 0) - COALESCE(st.search_bl_impressions_share_pct, 0), 2) as search_impressions_share_delta_pp,
  ROUND(COALESCE(st.search_exp_clicks_share_pct, 0) - COALESCE(st.search_bl_clicks_share_pct, 0), 2) as search_clicks_share_delta_pp,
  ROUND(COALESCE(st.search_exp_cart_adds_share_pct, 0) - COALESCE(st.search_bl_cart_adds_share_pct, 0), 2) as search_cart_adds_share_delta_pp,
  ROUND(COALESCE(st.search_exp_orders_share_pct, 0) - COALESCE(st.search_bl_orders_share_pct, 0), 2) as search_orders_share_delta_pp,
  ROUND(COALESCE(st.search_exp_conversion_rate_pct, 0) - COALESCE(st.search_bl_conversion_rate_pct, 0), 2) as search_conversion_rate_delta_pp,
  ROUND(COALESCE(st.search_exp_ctr_pct, 0) - COALESCE(st.search_bl_ctr_pct, 0), 2) as search_ctr_delta_pp,

  -- =============================================
  -- NET ROAS: profitability where break-even = 1.0
  -- net_revenue = total_units * (selling_price - cost_per_unit)
  -- net_roas = net_revenue / ad_spend
  -- =============================================
  nr.avg_margin_per_unit,
  COALESCE(nr.total_units, 0) as total_units_sold,
  COALESCE(nr.ads_units, 0) as ads_units_sold,
  COALESCE(nr.net_revenue, 0) as net_revenue,
  COALESCE(nr.ads_only_net_revenue, 0) as ads_only_net_revenue,
  ROUND(SAFE_DIVIDE(nr.net_revenue, NULLIF(nr.net_roas_ad_spend, 0)), 2) as net_roas,
  ROUND(SAFE_DIVIDE(nr.ads_only_net_revenue, NULLIF(nr.net_roas_ad_spend, 0)), 2) as ads_only_net_roas,
  ROUND(COALESCE(nr.net_revenue, 0) - COALESCE(nr.net_roas_ad_spend, 0), 2) as cumulative_net_profit,

  -- Verdict (based on SEASONAL-ADJUSTED PERFORMANCE_ organic lift, falls back to raw if seasonal is NULL)
  CASE
    WHEN COALESCE(a.performance_seasonal_avg_organic_lift_pct, a.performance_avg_organic_lift_pct) > 10 THEN 'STRONG_POSITIVE'
    WHEN COALESCE(a.performance_seasonal_avg_organic_lift_pct, a.performance_avg_organic_lift_pct) > 0 THEN 'WEAK_POSITIVE'
    WHEN COALESCE(a.performance_seasonal_avg_organic_lift_pct, a.performance_avg_organic_lift_pct) IS NULL THEN 'INSUFFICIENT_DATA'
    WHEN COALESCE(a.performance_seasonal_avg_organic_lift_pct, a.performance_avg_organic_lift_pct) > -10 THEN 'WEAK_NEGATIVE'
    ELSE 'STRONG_NEGATIVE'
  END as organic_verdict

FROM `onyga-482313.OI.DIM_EXPERIMENT` e
LEFT JOIN search_term_summary st ON e.experiment_id = st.experiment_id
LEFT JOIN asin_summary a ON e.experiment_id = a.experiment_id
LEFT JOIN experiment_net_roas nr ON e.experiment_id = nr.experiment_id;
