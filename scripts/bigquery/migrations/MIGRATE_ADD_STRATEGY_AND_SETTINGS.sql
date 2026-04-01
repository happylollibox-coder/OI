-- =============================================
-- OI Database Project - Migration: Strategy Templates & Campaign Settings
-- =============================================
--
-- Purpose: Adds strategy templates, campaign settings enrichment, and
--          enhanced learnings to the Experiment Learning System
--
-- Changes:
--   1. Creates DIM_STRATEGY_TEMPLATE table + seeds 10 strategy playbooks
--   2. ALTER DIM_EXPERIMENT: adds strategy_id column
--   3. ALTER DIM_EXPERIMENT_CAMPAIGN: adds placement % and notes columns
--   4. Updates EXP001 with strategy_id = 'EXACT_BOOST'
--   5. Creates V_EXPERIMENT_CAMPAIGN_SETTINGS view
--   6. Recreates V_EXPERIMENT_LEARNINGS (enhanced with 4 new dimensions)
--   7. Recreates SP_EXPERIMENT_WEEKLY_REVIEW (2 new recommendation sections)
--
-- Run order: Execute this script as a single batch in BigQuery.
--            Steps 5-7 (views/procedures) are idempotent (CREATE OR REPLACE).
--
-- Project: onyga-482313
-- Dataset: OI
-- Date: 2026-02-09
--
-- =============================================

-- =============================================
-- STEP 1: Create DIM_STRATEGY_TEMPLATE table
-- =============================================

CREATE TABLE IF NOT EXISTS `onyga-482313.OI.DIM_STRATEGY_TEMPLATE` (
  strategy_id STRING NOT NULL,
  strategy_name STRING NOT NULL,
  description STRING,
  recommended_campaign_type STRING,
  recommended_match_type STRING,
  recommended_bidding_strategy STRING,
  recommended_top_of_search_pct INT64,
  recommended_product_page_pct INT64,
  recommended_bid_min FLOAT64,
  recommended_bid_max FLOAT64,
  recommended_daily_budget FLOAT64,
  use_case STRING,
  tags STRING,
  is_active BOOL DEFAULT TRUE,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP(),
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP(),
  PRIMARY KEY (strategy_id) NOT ENFORCED
)
OPTIONS (
  description = "Predefined advertising strategy playbooks with recommended settings. Used by the experiment system to learn which strategies produce the best organic lift."
);

-- Seed strategy templates
DELETE FROM `onyga-482313.OI.DIM_STRATEGY_TEMPLATE` WHERE TRUE;

INSERT INTO `onyga-482313.OI.DIM_STRATEGY_TEMPLATE`
  (strategy_id, strategy_name, description,
   recommended_campaign_type, recommended_match_type, recommended_bidding_strategy,
   recommended_top_of_search_pct, recommended_product_page_pct,
   recommended_bid_min, recommended_bid_max, recommended_daily_budget,
   use_case, tags, is_active)
VALUES
  ('BRAND_DEFENSE',
   'Brand Defense',
   'Protect your own brand keywords from competitor ads. Ensures your products appear at top-of-search when shoppers search for your brand name.',
   'SP', 'EXACT', 'DOWN_ONLY',
   300, 0,
   0.30, 0.75, 10.00,
   'Use when competitors are bidding on your brand name (Happy Lolli, happy lollipop journal, etc.). Always-on strategy to maintain brand search dominance.',
   'brand,defensive,always-on',
   TRUE),

  ('HUNTER',
   'Hunter',
   'Target competitor brand names and high-converting competitor product keywords to capture their traffic.',
   'SP', 'BROAD', 'UP_AND_DOWN',
   200, 100,
   0.50, 1.50, 15.00,
   'Use to steal market share from specific competitors. Best during competitor out-of-stock or when your product has a clear advantage.',
   'competitor,offensive,aggressive',
   TRUE),

  ('EXACT_BOOST',
   'Exact Keyword Boost',
   'Push a specific proven keyword aggressively with exact match targeting and high top-of-search placement.',
   'SP', 'EXACT', 'DOWN_ONLY',
   500, 0,
   0.50, 2.00, 20.00,
   'Use for keywords already proven to convert organically. Goal is to dominate the SERP and boost organic ranking through increased sales velocity.',
   'exact,keyword,ranking,aggressive',
   TRUE),

  ('CATEGORY_CONQUEST',
   'Category Conquest',
   'Broad and auto targeting to discover new high-potential keywords in your product category.',
   'SP', 'AUTO', 'DOWN_ONLY',
   0, 0,
   0.25, 0.75, 10.00,
   'Use for keyword discovery. Run for 2-4 weeks, harvest converting search terms, then create exact/phrase campaigns for winners.',
   'discovery,broad,auto,category',
   TRUE),

  ('PRODUCT_DEFENSE',
   'Product Defense',
   'Target your own product detail pages to prevent competitor ads from appearing on your listings.',
   'SP', 'EXACT', 'DOWN_ONLY',
   0, 300,
   0.30, 0.75, 8.00,
   'Use when competitors are running product targeting ads on your ASINs. Focus on product page placement rather than search.',
   'defensive,product-page,asin-targeting',
   TRUE),

  ('SEASONAL_PUSH',
   'Seasonal Push',
   'Aggressive ad ramp-up around holidays and seasonal events with increased budgets and placement bids.',
   'BOTH', 'MIXED', 'UP_AND_DOWN',
   500, 200,
   0.75, 3.00, 30.00,
   'Use 2-3 weeks before major gift-giving holidays (Valentines, Mothers Day, Christmas). Increase bids and budget progressively during ramp-up.',
   'seasonal,holiday,aggressive,temporary',
   TRUE),

  ('NEW_LAUNCH',
   'New Product Launch',
   'Aggressive multi-campaign strategy for new ASIN launches. Uses all match types and high visibility to build initial sales velocity.',
   'BOTH', 'MIXED', 'UP_AND_DOWN',
   400, 200,
   0.75, 2.50, 25.00,
   'Use for the first 4-8 weeks after launching a new ASIN. Combine auto discovery + exact targeting on researched keywords. Accept lower ROAS initially.',
   'launch,new-product,aggressive,multi-campaign',
   TRUE),

  ('LOW_COST_DISCOVERY',
   'Low-Cost Discovery',
   'Auto campaigns with low bids to find converting keywords at minimal cost. The net for catching long-tail opportunities.',
   'SP', 'AUTO', 'DOWN_ONLY',
   0, 0,
   0.10, 0.35, 5.00,
   'Always-on background campaign. Low bids ensure only cheap clicks. Review weekly for search terms to promote to exact campaigns.',
   'discovery,low-cost,auto,always-on,long-tail',
   TRUE),

  ('TOS_DOMINATION',
   'Top-of-Search Domination',
   'Extreme top-of-search placement to maximize visibility for key search terms. Trades efficiency for dominance.',
   'SP', 'EXACT', 'DOWN_ONLY',
   900, 0,
   1.00, 3.00, 25.00,
   'Use for your top 3-5 most important keywords when you need maximum visibility. Monitor ACOS closely -- this is a visibility play, not an efficiency play.',
   'tos,visibility,aggressive,exact',
   TRUE),

  ('RETARGETING',
   'Retargeting',
   'Target audiences who have previously viewed or purchased your products to drive repeat purchases and cross-sells.',
   'SB', 'MIXED', 'DOWN_ONLY',
   100, 100,
   0.30, 1.00, 10.00,
   'Use Sponsored Brands with custom audiences. Effective for products with repeat purchase potential or complementary product lines.',
   'retargeting,audience,sb,repeat-purchase',
   TRUE);

-- =============================================
-- STEP 2: ALTER DIM_EXPERIMENT - add strategy_id
-- =============================================

ALTER TABLE `onyga-482313.OI.DIM_EXPERIMENT`
ADD COLUMN IF NOT EXISTS strategy_id STRING;

-- =============================================
-- STEP 3: ALTER DIM_EXPERIMENT_CAMPAIGN - add placement & notes columns
-- =============================================

ALTER TABLE `onyga-482313.OI.DIM_EXPERIMENT_CAMPAIGN`
ADD COLUMN IF NOT EXISTS top_of_search_pct INT64;

ALTER TABLE `onyga-482313.OI.DIM_EXPERIMENT_CAMPAIGN`
ADD COLUMN IF NOT EXISTS product_page_pct INT64;

ALTER TABLE `onyga-482313.OI.DIM_EXPERIMENT_CAMPAIGN`
ADD COLUMN IF NOT EXISTS rest_of_search_pct INT64;

ALTER TABLE `onyga-482313.OI.DIM_EXPERIMENT_CAMPAIGN`
ADD COLUMN IF NOT EXISTS notes STRING;

-- =============================================
-- STEP 4: Update EXP001 with strategy_id
-- =============================================

UPDATE `onyga-482313.OI.DIM_EXPERIMENT`
SET strategy_id = 'EXACT_BOOST',
    updated_at = CURRENT_TIMESTAMP()
WHERE experiment_id = 'EXP001';

-- =============================================
-- STEP 5: Recreate FACT_EXPERIMENT_DAILY with renamed columns
-- (prefix convention: ads_exp_*, ads_all_*, performance_*)
-- NOTE: This drops existing data. Re-run SP_EXPERIMENT_DAILY_SNAPSHOT to backfill.
-- =============================================

DROP TABLE IF EXISTS `onyga-482313.OI.FACT_EXPERIMENT_DAILY`;

CREATE TABLE `onyga-482313.OI.FACT_EXPERIMENT_DAILY` (
  snapshot_date DATE NOT NULL,
  experiment_id STRING NOT NULL,
  asin STRING NOT NULL,
  day_number INT64,
  ads_exp_orders INT64,
  ads_exp_units INT64,
  ads_exp_cost FLOAT64,
  ads_exp_sales FLOAT64,
  ads_all_orders INT64,
  ads_all_units INT64,
  ads_all_cost FLOAT64,
  ads_all_sales FLOAT64,
  performance_total_orders INT64,
  performance_total_units INT64,
  performance_total_sales FLOAT64,
  performance_sessions INT64,
  performance_page_views INT64,
  performance_organic_units INT64,
  performance_organic_units INT64,
  performance_organic_sales FLOAT64,
  cum_ads_exp_orders INT64,
  cum_ads_exp_cost FLOAT64,
  cum_ads_exp_sales FLOAT64,
  cum_ads_all_orders INT64,
  cum_performance_total_orders INT64,
  cum_performance_total_sales FLOAT64,
  cum_performance_organic_units INT64,
  cum_performance_organic_sales FLOAT64,
  performance_baseline_avg_daily_total_orders FLOAT64,
  performance_baseline_avg_daily_organic_units FLOAT64,
  performance_baseline_avg_daily_total_sales FLOAT64,
  performance_baseline_avg_daily_sessions FLOAT64,
  performance_organic_lift_vs_baseline FLOAT64,
  PRIMARY KEY (snapshot_date, experiment_id, asin) NOT ENFORCED
)
PARTITION BY DATE_TRUNC(snapshot_date, MONTH)
CLUSTER BY experiment_id, asin
OPTIONS (
  description = "Daily progress snapshots for active experiments. Prefixed: ads_exp_/ads_all_ from Amazon Ads, performance_ from Business Reports."
);
