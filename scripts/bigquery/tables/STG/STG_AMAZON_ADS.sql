-- =============================================
-- OI Database Project - STG_AMAZON_ADS Table
-- =============================================
--
-- Purpose: Staging table for Amazon Ads search term data enriched with advertised product ASIN information
-- Method: TRUNCATE + INSERT (full refresh)
-- Source: V_SRC_AmazonAds_SearchTerms + V_SRC_AmazonAds_advertised_product
-- Project: onyga-482313
-- Dataset: OI
--
-- =============================================

CREATE OR REPLACE TABLE `onyga-482313.OI.STG_AMAZON_ADS` (
  -- Ordered columns as specified
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
  impressions INT64,
  clicks INT64,
  orders INT64,
  units INT64,
  cost FLOAT64,
  sales FLOAT64,
  placement_type STRING,
  num_st_in_date_keyword INT64,
  num_ad_groups_for_st INT64,  -- Count of ad groups using the same search term for a specific date
  advertised_asins STRING,  -- Comma-separated list of all advertised ASINs for campaign+ad_group+date
  advertised_asins_count INT64,  -- Count of unique advertised ASINs
  most_advertised_asin_impressions STRING,  -- ASIN with highest impressions
  most_advertised_asin_clicks STRING,  -- ASIN with highest clicks
  most_advertised_asin_purchased STRING,  -- ASIN with highest orders_30d
  most_advertised_mismatch STRING,  -- Status indicating if the three most_advertised_asin fields are equal
  _fivetran_synced TIMESTAMP,
  source_table STRING,
  
  -- Primary Key: Based on SearchTerms natural key
  PRIMARY KEY (campaign_id, ad_group_id, keyword_id, date, search_term) NOT ENFORCED
)
PARTITION BY DATE_TRUNC(date, YEAR)
CLUSTER BY campaign_id, ad_group_id, date;

-- =============================================
-- TABLE DESCRIPTION
-- =============================================
--
-- This staging table holds Amazon Ads search term performance data enriched with
-- advertised product information. It is refreshed using TRUNCATE + INSERT method.
--
-- Key Features:
-- - Contains all columns from V_SRC_AmazonAds_SearchTerms
-- - Enriched with advertised ASIN information from V_SRC_AmazonAds_advertised_product
-- - ASIN matching uses Strategy B: campaign_id + ad_group_id + date
-- - All search term records are included (LEFT JOIN), with NULL ASIN fields when no match
--
-- The SP_LOAD_STG_AMAZON_ADS procedure manages this table:
-- - TRUNCATEs table on each run
-- - Aggregates advertised_product data by campaign+ad_group+date
-- - Joins to SearchTerms and inserts all records
--
-- ASIN Fields:
-- - advertised_asins: All ASINs advertised for this campaign+ad_group+date (comma-separated)
-- - advertised_asins_count: Number of unique ASINs
-- - most_advertised_asin_impressions: ASIN with highest impressions value
-- - most_advertised_asin_clicks: ASIN with highest clicks value
-- - most_advertised_asin_purchased: ASIN with highest orders_30d value
-- - most_advertised_mismatch: Status indicating if the three most_advertised_asin fields are equal
--   Values: 'All Match', 'Impressions=Clicks≠Purchased', 'Impressions=Purchased≠Clicks', 
--           'Clicks=Purchased≠Impressions', 'All Different', 'No ASIN Data'
--
-- Additional Fields:
-- - num_ad_groups_for_st: Count of ad groups using the same search term for a specific date
--
-- Column Order:
-- date, campaign_id, campaign_name, campaign_type, inferred_sales_module, ad_group_id, 
-- keyword_id, ad_keyword_status, targeting, search_term, impressions, clicks, orders, 
-- units, cost, sales, placement_type, num_st_in_date_keyword, num_ad_groups_for_st, 
-- advertised_asins, advertised_asins_count, most_advertised_asin_impressions, 
-- most_advertised_asin_clicks, most_advertised_asin_purchased, most_advertised_mismatch, 
-- _fivetran_synced, source_table
--
-- =============================================
