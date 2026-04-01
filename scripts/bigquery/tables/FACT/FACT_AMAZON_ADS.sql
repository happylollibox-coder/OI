-- =============================================
-- OI Database Project - FACT_AMAZON_ADS Table
-- =============================================
--
-- Purpose: Fact table for Amazon Ads search term performance data
-- Method: TRUNCATE + INSERT (full refresh)
-- Source: STG_AMAZON_ADS
-- Project: onyga-482313
-- Dataset: OI
--
-- =============================================

CREATE OR REPLACE TABLE `onyga-482313.OI.FACT_AMAZON_ADS` (
  -- Same columns as STG_AMAZON_ADS
  date DATE NOT NULL,
  campaign_id STRING NOT NULL,
  campaign_name STRING,
  campaign_type STRING,
  inferred_sales_module STRING,
  ad_group_id STRING NOT NULL,
  keyword_id STRING NOT NULL,
  ad_keyword_status STRING,
  targeting STRING,
  targeting_type STRING,
  search_term STRING,
  Ads_impressions INT64,
  Ads_clicks INT64,
  Ads_orders INT64,
  Ads_units INT64,
  Ads_cost FLOAT64,
  Ads_sales FLOAT64,
  TOTAL_COST_PER_UNIT FLOAT64,  -- From DIM_COSTS_HISTORY (join on date, most_advertised_asin_purchased; first sku if multiple)
  GROSS_PROFIT FLOAT64,  -- Ads_sales - TOTAL_COST_PER_UNIT * Ads_units
  placement_type STRING,
  num_st_in_date_keyword INT64,
  num_ad_groups_for_st INT64,
  advertised_asins STRING,
  advertised_asins_count INT64,
  most_advertised_asin_impressions STRING,
  most_advertised_asin_clicks STRING,
  most_advertised_asin_purchased STRING,
  most_advertised_mismatch STRING,
  _fivetran_synced TIMESTAMP,
  source_table STRING,
  ASIN_BY_CAMPAIGN_NAME STRING,  -- Derived from campaign_name via CASE WHEN regex; fallback when most_advertised_asin_impressions is NULL
  Ads_key STRING,  -- Composite key: Ccampaign_id-Aad_group_id-Kkeyword_id (with prefix characters)
                   -- For SP campaigns: uses actual keyword_id
                   -- For SB campaigns: normalizes keyword_id to '-1' for matching
  
  -- Primary Key: Same as STG
  PRIMARY KEY (campaign_id, ad_group_id, keyword_id, date, search_term) NOT ENFORCED
)
PARTITION BY DATE_TRUNC(date, YEAR)
CLUSTER BY campaign_id, ad_group_id, date;

-- =============================================
-- TABLE DESCRIPTION
-- =============================================
--
-- This fact table holds Amazon Ads search term performance data from STG_AMAZON_ADS.
-- It is refreshed using TRUNCATE + INSERT method.
--
-- Key Features:
-- - Contains all columns from STG_AMAZON_ADS
-- - Adds Ads_key field for ads identification (Ccampaign_id-Aad_group_id-Kkeyword_id)
--   - Format: C prefix for campaign_id, A prefix for ad_group_id, K prefix for keyword_id
--   - For SP campaigns: uses actual keyword_id (Ccampaign_id-Aad_group_id-Kkeyword_id)
--   - For SB campaigns: normalizes keyword_id to '-1' (Ccampaign_id-Aad_group_id-K-1) for matching
-- - Same structure and data as staging table
--
-- The SP_FACT_AMAZON_ADS procedure manages this table:
-- - TRUNCATEs table on each run
-- - Copies all data from STG_AMAZON_ADS
-- - Calculates Ads_key for each row
--
-- =============================================
