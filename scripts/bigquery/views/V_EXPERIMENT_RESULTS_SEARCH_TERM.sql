-- =============================================
-- OI Database Project - V_EXPERIMENT_RESULTS_SEARCH_TERM View
-- =============================================
--
-- Purpose: Per search term weekly comparison: experiment period vs baseline
--          Answers: "Did organic sales change for keywords I'm advertising?"
--
-- Features:
--   1. SQP SHARE METRICS: impressions, clicks, cart adds, orders share, CTR, conversion
--   2. AMAZON MARKET TOTALS: total Amazon orders = market potential at 100% share
--   3. ADS ROAS per search term: Ad Sales / Ad Cost (from FACT_AMAZON_ADS)
--   4. NORMALIZED COMPARISON: baseline and experiment values normalized to seasonal index 1.0
--      - Actual = raw weekly avg (what really happened)
--      - Normalized = actual / seasonal_index (what it would be in a "normal" week)
--      - Compare normalized-to-normalized for true lift without seasonal confusion
--
-- Source: FACT_AMAZON_SEARCH_PERFORMANCE_WEEKLY (SQP), FACT_AMAZON_ADS, V_SEASONAL_INDEX_WEEKLY
-- Prefix: search_ (SQP measures), ads_ (Amazon Ads measures)
-- Dependencies: V_EXPERIMENT_SEARCH_TERMS, DIM_EXPERIMENT, DIM_EXPERIMENT_CAMPAIGN
-- Project: onyga-482313
-- Dataset: OI
--
-- =============================================

CREATE OR REPLACE VIEW `onyga-482313.OI.V_EXPERIMENT_RESULTS_SEARCH_TERM`
AS
WITH experiment_terms AS (
  SELECT DISTINCT
    experiment_id,
    experiment_name,
    search_term,
    asin,
    has_overlap,
    ads_other_campaigns_count
  FROM `onyga-482313.OI.V_EXPERIMENT_SEARCH_TERMS`
),
experiment_dates AS (
  SELECT
    experiment_id,
    start_date,
    COALESCE(end_date, CURRENT_DATE()) as effective_end_date,
    baseline_days,
    DATE_SUB(start_date, INTERVAL baseline_days DAY) as baseline_start,
    DATE_SUB(start_date, INTERVAL 1 DAY) as baseline_end
  FROM `onyga-482313.OI.DIM_EXPERIMENT`
  WHERE status IN ('ACTIVE', 'COMPLETED')
),
-- SQP data during EXPERIMENT period (SQP DATA_SOURCE only for share metrics)
sqp_experiment AS (
  SELECT
    et.experiment_id,
    et.search_term,
    et.asin,
    COUNT(DISTINCT f.Reporting_Date) as experiment_weeks,
    -- Your metrics (SEARCH_)
    SUM(COALESCE(f.Impressions, 0)) as search_exp_impressions,
    SUM(COALESCE(f.Clicks, 0)) as search_exp_clicks,
    SUM(COALESCE(f.Cart_Adds, 0)) as search_exp_cart_adds,
    SUM(COALESCE(f.ORDERS, 0)) as search_exp_total_orders,
    -- Amazon total metrics (SEARCH AMAZON_) = MARKET POTENTIAL
    SUM(COALESCE(f.AMAZON_IMPRESSIONS, 0)) as search_exp_amazon_impressions,
    SUM(COALESCE(f.AMAZON_Clicks, 0)) as search_exp_amazon_clicks,
    SUM(COALESCE(f.AMAZON_Cart_Adds, 0)) as search_exp_amazon_cart_adds,
    SUM(COALESCE(f.AMAZON_ORDERS, 0)) as search_exp_amazon_orders,
    -- Ads metrics from SQP
    SUM(COALESCE(f.ADS_Impressions, 0)) as search_ads_exp_impressions,
    SUM(COALESCE(f.ADS_Clicks, 0)) as search_ads_exp_clicks,
    SUM(COALESCE(f.ADS_Orders, 0)) as search_ads_exp_orders,
    -- Organic = total - ads
    SUM(COALESCE(f.ORDERS, 0)) - SUM(COALESCE(f.ADS_Orders, 0)) as search_exp_organic_units
  FROM experiment_terms et
  JOIN experiment_dates ed ON et.experiment_id = ed.experiment_id
  LEFT JOIN `onyga-482313.OI.FACT_AMAZON_SEARCH_PERFORMANCE_WEEKLY` f
    ON LOWER(f.Search_Query) = LOWER(et.search_term)
    AND f.ASIN = et.asin
    AND f.DATA_SOURCE = 'SQP'
    AND f.Reporting_Date >= ed.start_date
    AND f.Reporting_Date <= ed.effective_end_date
  GROUP BY 1, 2, 3
),
-- SQP data during BASELINE period
sqp_baseline AS (
  SELECT
    et.experiment_id,
    et.search_term,
    et.asin,
    COUNT(DISTINCT f.Reporting_Date) as baseline_weeks,
    -- Your metrics (SEARCH_)
    SUM(COALESCE(f.Impressions, 0)) as search_bl_impressions,
    SUM(COALESCE(f.Clicks, 0)) as search_bl_clicks,
    SUM(COALESCE(f.Cart_Adds, 0)) as search_bl_cart_adds,
    SUM(COALESCE(f.ORDERS, 0)) as search_bl_total_orders,
    -- Amazon total metrics (SEARCH AMAZON_) = MARKET POTENTIAL
    SUM(COALESCE(f.AMAZON_IMPRESSIONS, 0)) as search_bl_amazon_impressions,
    SUM(COALESCE(f.AMAZON_Clicks, 0)) as search_bl_amazon_clicks,
    SUM(COALESCE(f.AMAZON_Cart_Adds, 0)) as search_bl_amazon_cart_adds,
    SUM(COALESCE(f.AMAZON_ORDERS, 0)) as search_bl_amazon_orders,
    -- Ads metrics from SQP
    SUM(COALESCE(f.ADS_Orders, 0)) as search_ads_bl_orders,
    -- Organic = total - ads
    SUM(COALESCE(f.ORDERS, 0)) - SUM(COALESCE(f.ADS_Orders, 0)) as search_bl_organic_units
  FROM experiment_terms et
  JOIN experiment_dates ed ON et.experiment_id = ed.experiment_id
  LEFT JOIN `onyga-482313.OI.FACT_AMAZON_SEARCH_PERFORMANCE_WEEKLY` f
    ON LOWER(f.Search_Query) = LOWER(et.search_term)
    AND f.ASIN = et.asin
    AND f.DATA_SOURCE = 'SQP'
    AND f.Reporting_Date >= ed.baseline_start
    AND f.Reporting_Date < ed.start_date
  GROUP BY 1, 2, 3
),
-- Ads performance per search term from FACT_AMAZON_ADS (experiment campaigns only)
ads_per_term AS (
  SELECT
    ec.experiment_id,
    LOWER(fa.search_term) as search_term,
    SUM(fa.Ads_impressions) as ads_impressions,
    SUM(fa.Ads_clicks) as ads_clicks,
    SUM(fa.Ads_orders) as ads_orders,
    SUM(fa.Ads_units) as ads_units,
    ROUND(SUM(fa.Ads_cost), 2) as ads_cost,
    ROUND(SUM(fa.Ads_sales), 2) as ads_sales
  FROM `onyga-482313.OI.DIM_EXPERIMENT_CAMPAIGN` ec
  JOIN `onyga-482313.OI.FACT_AMAZON_ADS` fa ON ec.campaign_id = fa.campaign_id
  JOIN experiment_dates ed ON ec.experiment_id = ed.experiment_id
  WHERE fa.date >= ed.start_date
    AND fa.date <= ed.effective_end_date
  GROUP BY 1, 2
),
-- Seasonal index averages per experiment period
seasonal_ref AS (
  SELECT iso_week, week_start, week_end, seasonal_index
  FROM `onyga-482313.OI.V_SEASONAL_INDEX_WEEKLY`
),
baseline_seasonal_avg AS (
  SELECT
    ed.experiment_id,
    ROUND(AVG(si.seasonal_index), 4) as bl_seasonal_index
  FROM experiment_dates ed
  LEFT JOIN seasonal_ref si
    ON si.week_end >= ed.baseline_start
    AND si.week_start < ed.start_date
  GROUP BY 1
),
experiment_seasonal_avg AS (
  SELECT
    ed.experiment_id,
    ROUND(AVG(si.seasonal_index), 4) as exp_seasonal_index
  FROM experiment_dates ed,
  UNNEST(GENERATE_DATE_ARRAY(ed.start_date, ed.effective_end_date, INTERVAL 7 DAY)) as sample_date
  LEFT JOIN seasonal_ref si
    ON EXTRACT(ISOWEEK FROM sample_date) = si.iso_week
  GROUP BY 1
),
seasonal_avgs AS (
  SELECT
    bsa.experiment_id,
    bsa.bl_seasonal_index,
    esa.exp_seasonal_index
  FROM baseline_seasonal_avg bsa
  JOIN experiment_seasonal_avg esa ON bsa.experiment_id = esa.experiment_id
)
SELECT
  -- Keys
  CONCAT(et.experiment_id, '|', et.search_term, '|', et.asin) as row_key,
  CONCAT(et.search_term, '|', et.asin) as search_term_key,
  CONCAT(et.experiment_id, '|', et.asin) as experiment_asin_key,

  et.experiment_id,
  et.experiment_name,
  et.search_term,
  et.asin,
  et.has_overlap,
  et.ads_other_campaigns_count,

  -- =============================================
  -- BASELINE period (SEARCH_ source: SQP)
  -- =============================================
  COALESCE(bl.baseline_weeks, 0) as baseline_weeks,
  COALESCE(bl.search_bl_impressions, 0) as search_baseline_impressions,
  COALESCE(bl.search_bl_clicks, 0) as search_baseline_clicks,
  COALESCE(bl.search_bl_cart_adds, 0) as search_baseline_cart_adds,
  COALESCE(bl.search_bl_total_orders, 0) as search_baseline_total_orders,
  COALESCE(bl.search_bl_organic_units, 0) as search_baseline_organic_units,
  ROUND(SAFE_DIVIDE(bl.search_bl_total_orders, NULLIF(bl.baseline_weeks, 0)), 3) as search_baseline_avg_weekly_orders,
  ROUND(SAFE_DIVIDE(bl.search_bl_organic_units, NULLIF(bl.baseline_weeks, 0)), 3) as search_baseline_avg_weekly_organic,

  -- Baseline Amazon totals (MARKET POTENTIAL: what if you had 100% share)
  COALESCE(bl.search_bl_amazon_impressions, 0) as search_baseline_amazon_impressions,
  COALESCE(bl.search_bl_amazon_clicks, 0) as search_baseline_amazon_clicks,
  COALESCE(bl.search_bl_amazon_cart_adds, 0) as search_baseline_amazon_cart_adds,
  COALESCE(bl.search_bl_amazon_orders, 0) as search_baseline_amazon_orders,
  -- MAGNITUDE: Baseline Amazon avg weekly orders (market size per week)
  ROUND(SAFE_DIVIDE(bl.search_bl_amazon_orders, NULLIF(bl.baseline_weeks, 0)), 1) as search_baseline_amazon_avg_weekly_orders,
  -- MAGNITUDE: Baseline Amazon conversion rate (market benchmark)
  ROUND(SAFE_DIVIDE(bl.search_bl_amazon_orders, NULLIF(bl.search_bl_amazon_clicks, 0)) * 100, 2) as search_baseline_amazon_conversion_rate_pct,
  -- MAGNITUDE: Baseline Amazon CTR (market benchmark)
  ROUND(SAFE_DIVIDE(bl.search_bl_amazon_clicks, NULLIF(bl.search_bl_amazon_impressions, 0)) * 100, 2) as search_baseline_amazon_ctr_pct,

  -- Baseline SQP SHARE METRICS
  ROUND(SAFE_DIVIDE(bl.search_bl_impressions, NULLIF(bl.search_bl_amazon_impressions, 0)) * 100, 2) as search_baseline_impressions_share_pct,
  ROUND(SAFE_DIVIDE(bl.search_bl_clicks, NULLIF(bl.search_bl_amazon_clicks, 0)) * 100, 2) as search_baseline_clicks_share_pct,
  ROUND(SAFE_DIVIDE(bl.search_bl_cart_adds, NULLIF(bl.search_bl_amazon_cart_adds, 0)) * 100, 2) as search_baseline_cart_adds_share_pct,
  ROUND(SAFE_DIVIDE(bl.search_bl_total_orders, NULLIF(bl.search_bl_amazon_orders, 0)) * 100, 2) as search_baseline_orders_share_pct,
  ROUND(SAFE_DIVIDE(bl.search_bl_total_orders, NULLIF(bl.search_bl_clicks, 0)) * 100, 2) as search_baseline_conversion_rate_pct,
  ROUND(SAFE_DIVIDE(bl.search_bl_clicks, NULLIF(bl.search_bl_impressions, 0)) * 100, 2) as search_baseline_ctr_pct,

  -- =============================================
  -- EXPERIMENT period (SEARCH_ source: SQP)
  -- =============================================
  COALESCE(se.experiment_weeks, 0) as experiment_weeks,
  COALESCE(se.search_exp_impressions, 0) as search_experiment_impressions,
  COALESCE(se.search_exp_clicks, 0) as search_experiment_clicks,
  COALESCE(se.search_exp_cart_adds, 0) as search_experiment_cart_adds,
  COALESCE(se.search_exp_total_orders, 0) as search_experiment_total_orders,
  COALESCE(se.search_ads_exp_orders, 0) as search_ads_experiment_orders,
  COALESCE(se.search_exp_organic_units, 0) as search_experiment_organic_units,
  ROUND(SAFE_DIVIDE(se.search_exp_total_orders, NULLIF(se.experiment_weeks, 0)), 3) as search_experiment_avg_weekly_orders,
  ROUND(SAFE_DIVIDE(se.search_exp_organic_units, NULLIF(se.experiment_weeks, 0)), 3) as search_experiment_avg_weekly_organic,

  -- Experiment Amazon totals (MARKET POTENTIAL)
  COALESCE(se.search_exp_amazon_impressions, 0) as search_experiment_amazon_impressions,
  COALESCE(se.search_exp_amazon_clicks, 0) as search_experiment_amazon_clicks,
  COALESCE(se.search_exp_amazon_cart_adds, 0) as search_experiment_amazon_cart_adds,
  COALESCE(se.search_exp_amazon_orders, 0) as search_experiment_amazon_orders,
  -- MAGNITUDE: Experiment Amazon avg weekly orders (market size per week)
  ROUND(SAFE_DIVIDE(se.search_exp_amazon_orders, NULLIF(se.experiment_weeks, 0)), 1) as search_experiment_amazon_avg_weekly_orders,
  -- MAGNITUDE: Experiment Amazon conversion rate (market benchmark)
  ROUND(SAFE_DIVIDE(se.search_exp_amazon_orders, NULLIF(se.search_exp_amazon_clicks, 0)) * 100, 2) as search_experiment_amazon_conversion_rate_pct,
  -- MAGNITUDE: Experiment Amazon CTR (market benchmark)
  ROUND(SAFE_DIVIDE(se.search_exp_amazon_clicks, NULLIF(se.search_exp_amazon_impressions, 0)) * 100, 2) as search_experiment_amazon_ctr_pct,

  -- Experiment SQP SHARE METRICS
  ROUND(SAFE_DIVIDE(se.search_exp_impressions, NULLIF(se.search_exp_amazon_impressions, 0)) * 100, 2) as search_experiment_impressions_share_pct,
  ROUND(SAFE_DIVIDE(se.search_exp_clicks, NULLIF(se.search_exp_amazon_clicks, 0)) * 100, 2) as search_experiment_clicks_share_pct,
  ROUND(SAFE_DIVIDE(se.search_exp_cart_adds, NULLIF(se.search_exp_amazon_cart_adds, 0)) * 100, 2) as search_experiment_cart_adds_share_pct,
  ROUND(SAFE_DIVIDE(se.search_exp_total_orders, NULLIF(se.search_exp_amazon_orders, 0)) * 100, 2) as search_experiment_orders_share_pct,
  ROUND(SAFE_DIVIDE(se.search_exp_total_orders, NULLIF(se.search_exp_clicks, 0)) * 100, 2) as search_experiment_conversion_rate_pct,
  ROUND(SAFE_DIVIDE(se.search_exp_clicks, NULLIF(se.search_exp_impressions, 0)) * 100, 2) as search_experiment_ctr_pct,

  -- =============================================
  -- SHARE METRIC DELTAS (experiment - baseline, in percentage POINTS)
  -- =============================================
  ROUND(
    SAFE_DIVIDE(se.search_exp_impressions, NULLIF(se.search_exp_amazon_impressions, 0)) * 100
    - SAFE_DIVIDE(bl.search_bl_impressions, NULLIF(bl.search_bl_amazon_impressions, 0)) * 100
  , 2) as search_impressions_share_delta_pp,
  ROUND(
    SAFE_DIVIDE(se.search_exp_clicks, NULLIF(se.search_exp_amazon_clicks, 0)) * 100
    - SAFE_DIVIDE(bl.search_bl_clicks, NULLIF(bl.search_bl_amazon_clicks, 0)) * 100
  , 2) as search_clicks_share_delta_pp,
  ROUND(
    SAFE_DIVIDE(se.search_exp_cart_adds, NULLIF(se.search_exp_amazon_cart_adds, 0)) * 100
    - SAFE_DIVIDE(bl.search_bl_cart_adds, NULLIF(bl.search_bl_amazon_cart_adds, 0)) * 100
  , 2) as search_cart_adds_share_delta_pp,
  ROUND(
    SAFE_DIVIDE(se.search_exp_total_orders, NULLIF(se.search_exp_amazon_orders, 0)) * 100
    - SAFE_DIVIDE(bl.search_bl_total_orders, NULLIF(bl.search_bl_amazon_orders, 0)) * 100
  , 2) as search_orders_share_delta_pp,
  ROUND(
    SAFE_DIVIDE(se.search_exp_total_orders, NULLIF(se.search_exp_clicks, 0)) * 100
    - SAFE_DIVIDE(bl.search_bl_total_orders, NULLIF(bl.search_bl_clicks, 0)) * 100
  , 2) as search_conversion_rate_delta_pp,
  ROUND(
    SAFE_DIVIDE(se.search_exp_clicks, NULLIF(se.search_exp_impressions, 0)) * 100
    - SAFE_DIVIDE(bl.search_bl_clicks, NULLIF(bl.search_bl_impressions, 0)) * 100
  , 2) as search_ctr_delta_pp,

  -- =============================================
  -- ADS PERFORMANCE per search term (from FACT_AMAZON_ADS, experiment campaigns only)
  -- Note: Total ROAS cannot be calculated per search term (SQP has no sales $).
  --       Total ROAS is at the ASIN level only (V_EXPERIMENT_RESULTS_ASIN).
  -- =============================================
  COALESCE(apt.ads_impressions, 0) as ads_term_impressions,
  COALESCE(apt.ads_clicks, 0) as ads_term_clicks,
  COALESCE(apt.ads_orders, 0) as ads_term_orders,
  COALESCE(apt.ads_cost, 0) as ads_term_cost,
  COALESCE(apt.ads_sales, 0) as ads_term_sales,
  -- Ads ROAS = actual ad attributed sales / actual ad cost (actuals only, no estimates)
  ROUND(SAFE_DIVIDE(apt.ads_sales, NULLIF(apt.ads_cost, 0)), 2) as ads_term_roas,
  -- Ad CPC
  ROUND(SAFE_DIVIDE(apt.ads_cost, NULLIF(apt.ads_clicks, 0)), 2) as ads_term_cpc,
  -- Ad conversion rate
  ROUND(SAFE_DIVIDE(apt.ads_orders, NULLIF(apt.ads_clicks, 0)) * 100, 2) as ads_term_conversion_rate_pct,

  -- =============================================
  -- ORDER LIFT (raw, not seasonally adjusted)
  -- =============================================
  COALESCE(se.search_exp_total_orders, 0) - COALESCE(bl.search_bl_total_orders, 0) as search_total_orders_delta,
  ROUND(SAFE_DIVIDE(
    SAFE_DIVIDE(se.search_exp_total_orders, NULLIF(se.experiment_weeks, 0))
    - SAFE_DIVIDE(bl.search_bl_total_orders, NULLIF(bl.baseline_weeks, 0)),
    NULLIF(SAFE_DIVIDE(bl.search_bl_total_orders, NULLIF(bl.baseline_weeks, 0)), 0)
  ) * 100, 1) as search_total_orders_lift_pct,

  COALESCE(se.search_exp_organic_units, 0) - COALESCE(bl.search_bl_organic_units, 0) as search_organic_units_delta,
  ROUND(SAFE_DIVIDE(
    SAFE_DIVIDE(se.search_exp_organic_units, NULLIF(se.experiment_weeks, 0))
    - SAFE_DIVIDE(bl.search_bl_organic_units, NULLIF(bl.baseline_weeks, 0)),
    NULLIF(SAFE_DIVIDE(bl.search_bl_organic_units, NULLIF(bl.baseline_weeks, 0)), 0)
  ) * 100, 1) as search_organic_units_lift_pct,

  -- =============================================
  -- SEASONAL CONTEXT
  -- =============================================
  sa.bl_seasonal_index,
  sa.exp_seasonal_index,
  ROUND(SAFE_DIVIDE(sa.exp_seasonal_index, NULLIF(sa.bl_seasonal_index, 0)), 4) as seasonal_adjustment_ratio,

  -- =============================================
  -- DATA RELIABILITY FLAGS
  -- SQP organic = total_orders - ads_orders can be negative when:
  --   1. SB/SBV campaigns not fully counted in SQP ORDERS column
  --   2. Amazon privacy threshold hides small order counts (shows 0)
  -- When organic < 0, organic metrics are UNRELIABLE for this term
  -- =============================================
  CASE
    WHEN COALESCE(se.search_exp_total_orders, 0) < COALESCE(se.search_ads_exp_orders, 0)
      OR COALESCE(bl.search_bl_total_orders, 0) < COALESCE(bl.search_ads_bl_orders, 0)
    THEN TRUE ELSE FALSE
  END as organic_data_unreliable,

  -- =============================================
  -- NORMALIZED COMPARISON (remove seasonal effect for fair comparison)
  --
  -- Uses TOTAL ORDERS (reliable) not organic (unreliable for SB campaigns)
  --
  -- "Normalized" = actual / seasonal_index → what it would be in a normal (index=1.0) week
  -- Example:
  --   Baseline: 0.25 orders/wk during Christmas (index 4.5) → normalized: 0.056/wk
  --   Experiment: 0.14 orders/wk in January (index 1.9)    → normalized: 0.075/wk
  --   Raw looks like -44% drop. Normalized shows +34% lift (the real underlying improvement)
  -- =============================================

  -- TOTAL ORDERS: Baseline actual vs normalized
  ROUND(SAFE_DIVIDE(bl.search_bl_total_orders, NULLIF(bl.baseline_weeks, 0)), 3) as baseline_actual_avg_weekly_total,
  ROUND(SAFE_DIVIDE(
    SAFE_DIVIDE(bl.search_bl_total_orders, NULLIF(bl.baseline_weeks, 0)),
    NULLIF(sa.bl_seasonal_index, 0)
  ), 3) as baseline_normalized_avg_weekly_total,

  -- TOTAL ORDERS: Experiment actual vs normalized
  ROUND(SAFE_DIVIDE(se.search_exp_total_orders, NULLIF(se.experiment_weeks, 0)), 3) as experiment_actual_avg_weekly_total,
  ROUND(SAFE_DIVIDE(
    SAFE_DIVIDE(se.search_exp_total_orders, NULLIF(se.experiment_weeks, 0)),
    NULLIF(sa.exp_seasonal_index, 0)
  ), 3) as experiment_normalized_avg_weekly_total,

  -- NORMALIZED TOTAL LIFT: the TRUE seasonal-free comparison
  ROUND(SAFE_DIVIDE(
    SAFE_DIVIDE(se.search_exp_total_orders, NULLIF(se.experiment_weeks, 0)) / NULLIF(sa.exp_seasonal_index, 0)
    - SAFE_DIVIDE(bl.search_bl_total_orders, NULLIF(bl.baseline_weeks, 0)) / NULLIF(sa.bl_seasonal_index, 0),
    NULLIF(SAFE_DIVIDE(bl.search_bl_total_orders, NULLIF(bl.baseline_weeks, 0)) / NULLIF(sa.bl_seasonal_index, 0), 0)
  ) * 100, 1) as normalized_total_lift_pct,

  -- AMAZON MARKET: Baseline vs Experiment normalized (shows if market itself changed)
  ROUND(SAFE_DIVIDE(bl.search_bl_amazon_orders, NULLIF(bl.baseline_weeks, 0)), 1) as baseline_actual_amazon_weekly_orders,
  ROUND(SAFE_DIVIDE(
    SAFE_DIVIDE(bl.search_bl_amazon_orders, NULLIF(bl.baseline_weeks, 0)),
    NULLIF(sa.bl_seasonal_index, 0)
  ), 1) as baseline_normalized_amazon_weekly_orders,
  ROUND(SAFE_DIVIDE(se.search_exp_amazon_orders, NULLIF(se.experiment_weeks, 0)), 1) as experiment_actual_amazon_weekly_orders,
  ROUND(SAFE_DIVIDE(
    SAFE_DIVIDE(se.search_exp_amazon_orders, NULLIF(se.experiment_weeks, 0)),
    NULLIF(sa.exp_seasonal_index, 0)
  ), 1) as experiment_normalized_amazon_weekly_orders

FROM experiment_terms et
LEFT JOIN sqp_experiment se ON et.experiment_id = se.experiment_id AND et.search_term = se.search_term AND et.asin = se.asin
LEFT JOIN sqp_baseline bl ON et.experiment_id = bl.experiment_id AND et.search_term = bl.search_term AND et.asin = bl.asin
LEFT JOIN ads_per_term apt ON et.experiment_id = apt.experiment_id AND LOWER(et.search_term) = apt.search_term
LEFT JOIN seasonal_avgs sa ON et.experiment_id = sa.experiment_id;
