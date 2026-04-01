-- =============================================
-- OI Database Project - STG_AmazonAds_purchased_product Table
-- =============================================
--
-- Purpose: Staging table for Amazon Ads purchased product data
-- Method: TRUNCATE + INSERT (full refresh)
-- Source: V_SRC_AmazonAds_purchased_product
-- Project: onyga-482313
-- Dataset: OI
--
-- =============================================

CREATE OR REPLACE TABLE `onyga-482313.OI.STG_AmazonAds_purchased_product` (
  DATE DATE NOT NULL,
  PURCHASED_ASIN STRING NOT NULL,
  advertised_asin STRING,
  campaign_id STRING,
  ad_group_id STRING,
  keyword_id STRING,
  PURCHASED_ORDERS INT64,
  PURCHASED_UNITS INT64,
  PURCHASED_AMOUNT_USD FLOAT64,
  -- Attribution window variants
  PURCHASED_ORDERS_1d INT64,
  PURCHASED_ORDERS_7d INT64,
  PURCHASED_ORDERS_14d INT64,
  PURCHASED_ORDERS_30d INT64,
  PURCHASED_UNITS_1d INT64,
  PURCHASED_UNITS_7d INT64,
  PURCHASED_UNITS_14d INT64,
  PURCHASED_UNITS_30d INT64,
  PURCHASED_AMOUNT_USD_1d FLOAT64,
  PURCHASED_AMOUNT_USD_7d FLOAT64,
  PURCHASED_AMOUNT_USD_14d FLOAT64,
  PURCHASED_AMOUNT_USD_30d FLOAT64,
  data_source STRING,  -- 'SP' or 'SB' indicating campaign type
  
  -- Primary Key (natural grain of the source)
  PRIMARY KEY (DATE, PURCHASED_ASIN, advertised_asin, campaign_id, ad_group_id, keyword_id) NOT ENFORCED
)
PARTITION BY DATE_TRUNC(DATE, YEAR)
CLUSTER BY PURCHASED_ASIN, DATE;

-- =============================================
-- TABLE DESCRIPTION
-- =============================================
--
-- This staging table holds purchased product data from Amazon Ads
-- at DATE + PURCHASED_ASIN + advertised_asin + campaign/ad_group/keyword level.
-- It is refreshed using TRUNCATE + INSERT method.
--
-- Columns:
-- - DATE: Report date
-- - PURCHASED_ASIN: ASIN that was purchased
-- - advertised_asin: ASIN that was advertised
-- - campaign_id / ad_group_id / keyword_id: Ads hierarchy identifiers
-- - PURCHASED_ORDERS: Orders attributed to this combination (default window)
-- - PURCHASED_UNITS: Units attributed to this combination (default window)
-- - PURCHASED_AMOUNT_USD: Sales amount attributed (USD, default window)
-- - PURCHASED_ORDERS_1d/_7d/_14d/_30d: Orders by attribution window (SB: only 14d available)
-- - PURCHASED_UNITS_1d/_7d/_14d/_30d: Units by attribution window (SB: only 14d available)
-- - PURCHASED_AMOUNT_USD_1d/_7d/_14d/_30d: Sales by attribution window (SB: only 14d available)
-- - data_source: Campaign type - 'SP' (Sponsored Products) or 'SB' (Sponsored Brands)
--
-- =============================================
