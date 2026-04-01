-- =============================================
-- OI Database Project - FACT_AMAZON_PERFORMANCE_DAILY Table
-- =============================================
--
-- Purpose: Fact table for Amazon performance by purchased ASIN
-- Method: TRUNCATE + INSERT (full refresh)
-- Sources: FACT_AMAZON_ADS (ads), STG_AMAZON_PERFORMANCE (organic)
-- Project: onyga-482313
-- Dataset: OI
--
-- =============================================

CREATE OR REPLACE TABLE `onyga-482313.OI.FACT_AMAZON_PERFORMANCE_DAILY` (
  DATE DATE NOT NULL,
  PURCHASED_ASIN STRING NOT NULL,
  advertised_asin STRING,
  campaign_id STRING,
  ad_group_id STRING,
  ad_group_name STRING,
  ad_group_state STRING,
  keyword_id STRING,
  -- Campaign enrichment fields (from V_SRC_AmazonAds_campaign_history + V_SRC_AmazonAds_portfolio)
  campaign_serving_status STRING,
  campaign_name STRING,
  campaign_budget FLOAT64,
  brand_entity_id STRING,
  profile_id STRING,
  campaign_state STRING,
  campaign_bidding_strategy STRING,
  campaign_budget_type STRING,
  campaign_type STRING,
  portfolio_id STRING,
  portfolio_name STRING,
  portfolio_budget_amount FLOAT64,
  portfolio_budget_policy STRING,
  portfolio_budget_start_date DATE,
  portfolio_budget_end_date DATE,
  PURCHASED_ORDERS INT64,
  PURCHASED_UNITS INT64,
  PURCHASED_AMOUNT_USD FLOAT64,
  TOTAL_COST_PER_UNIT FLOAT64,  -- From DIM_COSTS_HISTORY (join on date, asin; first sku if multiple)
  GROSS_PROFIT FLOAT64,  -- PURCHASED_AMOUNT_USD - TOTAL_COST_PER_UNIT * PURCHASED_UNITS
  ASIN_SESSIONS INT64,
  ASIN_PAGE_VIEWS INT64,
  DATA_SOURCE STRING,  -- 'FACT_AMAZON_ADS' or 'STG_AMAZON_PERFORMANCE - FACT_AMAZON_ADS'
  DATA_QUALITY_STATUS STRING,  -- Data quality flag with descriptive messages (e.g., 'OK', 'Missing Organic data', 'Negative delta', etc.)
  Performance_TYPE STRING,  -- 'SP', 'SB', or 'Organic' indicating the performance source type
  factless_key STRING,  -- Composite key: YYYYMMDD-ASIN format for factless bridge joins
  Ads_key STRING,  -- Composite key: DYYYYMMDD-Ccampaign_id-Aad_group_id-Kkeyword_id for ads identification
  
  -- Primary Key: grain + data source
  PRIMARY KEY (DATE, PURCHASED_ASIN, advertised_asin, campaign_id, ad_group_id, keyword_id, DATA_SOURCE) NOT ENFORCED
)
PARTITION BY DATE_TRUNC(DATE, YEAR)
CLUSTER BY PURCHASED_ASIN, DATE;

-- =============================================
-- TABLE DESCRIPTION
-- =============================================
--
-- This fact table holds Amazon performance data by purchased ASIN from staging tables.
-- It is refreshed using TRUNCATE + INSERT method.
--
-- Key Features:
-- - Combines ads data from FACT_AMAZON_ADS (source of truth for ads sales)
--   with sales & traffic data from Seller Central (STG_AMAZON_PERFORMANCE)
-- - PURCHASED_ORDERS / PURCHASED_UNITS / PURCHASED_AMOUNT_USD hold purchase metrics
-- - ASIN_SESSIONS / ASIN_PAGE_VIEWS hold sessions and page views by ASIN
-- - DATA_SOURCE distinguishes between Ads rows and delta rows:
--   - 'FACT_AMAZON_ADS'
--   - 'STG_AMAZON_PERFORMANCE - FACT_AMAZON_ADS'
-- - DATA_QUALITY_STATUS provides data quality validation flags:
--   - 'OK' for valid data
--   - 'Missing Organic data' for dates with IS_LOADED=FALSE or missing dates
--   - 'Negative delta for [measure]' when raw delta was negative (clamped to 0)
--   - 'Ads [measure] in ads greater than total' when aggregated ads > performance
-- - Performance_TYPE indicates the performance source:
--   - 'SP' or 'SB' for Ads rows (from FACT_AMAZON_ADS)
--   - 'Organic' for delta rows (from STG_AMAZON_PERFORMANCE - FACT_AMAZON_ADS)
-- - factless_key: Composite key in format YYYYMMDD-ASIN for joining with FACT_FACTLESS_BRIDGE
-- - Campaign & portfolio enrichment (by DATE + campaign_id, with temporal validity):
--   - Joined from V_SRC_AmazonAds_campaign_history and V_SRC_AmazonAds_portfolio
--   - Includes campaign status, budget, type, and portfolio budget window
-- - Ad group enrichment (by DATE + campaign_id + ad_group_id, with temporal validity):
--   - Joined from V_SRC_AmazonAds_ad_group_history
--   - Includes ad_group_name and ad_group_state
-- - Ads_key: Composite key identifying ads combination (DYYYYMMDD-Ccampaign_id-Aad_group_id-Kkeyword_id)
--   - Format: D prefix for date (YYYYMMDD), C prefix for campaign_id, A prefix for ad_group_id, K prefix for keyword_id
--   - For SP campaigns: uses actual keyword_id
--   - For SB campaigns: normalizes keyword_id to '-1' for matching
--   - NULL for Organic rows (no ads context)
--
-- The SP_AMAZON_PERFORMANCE_DAILY procedure manages this table:
-- - TRUNCATEs table on each run
-- - Inserts Ads rows from FACT_AMAZON_ADS (aggregated by date, campaign, ad_group, keyword, ASIN)
-- - Inserts delta rows based on STG_AMAZON_PERFORMANCE minus aggregated FACT_AMAZON_ADS
--
--
-- =============================================
