-- =============================================
-- OI Database Project - FACT_EXPERIMENT_DAILY Table
-- =============================================
--
-- Purpose: Daily progress snapshots for active experiments (ASIN-level)
-- Method: MERGE (upsert daily by SP_EXPERIMENT_DAILY_SNAPSHOT)
-- Source: FACT_AMAZON_PERFORMANCE_DAILY, FACT_AMAZON_ADS, DIM_EXPERIMENT
-- Prefix convention:
--   ads_exp_*     = Amazon Ads, experiment campaigns only
--   ads_all_*     = Amazon Ads, all campaigns on this ASIN
--   performance_* = Business Reports (FACT_AMAZON_PERFORMANCE_DAILY)
-- Project: onyga-482313
-- Dataset: OI
--
-- =============================================

CREATE TABLE IF NOT EXISTS `onyga-482313.OI.FACT_EXPERIMENT_DAILY` (
  -- Keys
  snapshot_date DATE NOT NULL,
  experiment_id STRING NOT NULL,
  asin STRING NOT NULL,

  -- Experiment context
  day_number INT64,  -- days since experiment start_date

  -- Daily metrics: Ads from experiment campaigns only (ADS_ source: FACT_AMAZON_ADS)
  ads_exp_orders INT64,
  ads_exp_units INT64,
  ads_exp_cost FLOAT64,
  ads_exp_sales FLOAT64,

  -- Daily metrics: All Ads on this ASIN (ADS_ source: FACT_AMAZON_ADS)
  ads_all_orders INT64,
  ads_all_units INT64,
  ads_all_cost FLOAT64,
  ads_all_sales FLOAT64,

  -- Daily metrics: Total ASIN performance (PERFORMANCE_ source: Business Reports)
  performance_total_orders INT64,
  performance_total_units INT64,
  performance_total_sales FLOAT64,
  performance_sessions INT64,
  performance_page_views INT64,

  -- Daily metrics: Organic = performance total - ads all (PERFORMANCE_ derived)
  performance_organic_units INT64,
  performance_organic_units INT64,
  performance_organic_sales FLOAT64,

  -- Cumulative since experiment start
  cum_ads_exp_orders INT64,
  cum_ads_exp_cost FLOAT64,
  cum_ads_exp_sales FLOAT64,
  cum_ads_all_orders INT64,
  cum_performance_total_orders INT64,
  cum_performance_total_sales FLOAT64,
  cum_performance_organic_units INT64,
  cum_performance_organic_sales FLOAT64,

  -- Baseline reference (avg daily from baseline period, PERFORMANCE_ source)
  performance_baseline_avg_daily_total_orders FLOAT64,
  performance_baseline_avg_daily_organic_units FLOAT64,
  performance_baseline_avg_daily_total_sales FLOAT64,
  performance_baseline_avg_daily_sessions FLOAT64,

  -- Lift vs baseline (PERFORMANCE_ derived) - RAW (no seasonal adjustment)
  performance_organic_lift_vs_baseline FLOAT64,

  -- Seasonal adjustment (from V_SEASONAL_INDEX_WEEKLY, reference ASIN B0C1VLXYBP)
  seasonal_index FLOAT64,                                        -- seasonal index for this snapshot_date's week
  seasonal_index_baseline_avg FLOAT64,                           -- avg seasonal index across baseline period
  performance_seasonal_expected_daily_orders FLOAT64,            -- baseline_avg * (seasonal_index / baseline_avg_index)
  cum_performance_seasonal_expected_orders FLOAT64,              -- cumulative sum of daily seasonal expectations
  performance_seasonal_organic_lift_vs_baseline FLOAT64,         -- (cum_actual - cum_expected) / cum_expected

  factless_key STRING,  -- YYYYMMDD-ASIN for bridge joins

  PRIMARY KEY (snapshot_date, experiment_id, asin) NOT ENFORCED
)
PARTITION BY DATE_TRUNC(snapshot_date, MONTH)
CLUSTER BY experiment_id, asin
OPTIONS (
  description = "Daily progress snapshots for active experiments. Prefixed: ads_exp_/ads_all_ from Amazon Ads, performance_ from Business Reports."
);
