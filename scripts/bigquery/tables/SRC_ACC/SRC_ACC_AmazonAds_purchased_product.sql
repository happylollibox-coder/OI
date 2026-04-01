-- =============================================
-- OI Database Project - SRC_ACC_AmazonAds_purchased_product Table
-- =============================================
--
-- Purpose: Accumulation table for Amazon Ads purchased product data
-- Method: MERGE from V_SRC_AmazonAds_purchased_product (insert if not exists)
-- Key Behavior: 1d measures are captured on first insert and never updated,
--               preserving the early snapshot as a 1d attribution proxy (especially for SB).
--               All other measures (7d, 14d, 30d, default) are updated on each run.
-- Project: onyga-482313
-- Dataset: OI
--
-- =============================================

CREATE TABLE IF NOT EXISTS `onyga-482313.OI.SRC_ACC_AmazonAds_purchased_product` (
  DATE DATE NOT NULL,
  PURCHASED_ASIN STRING NOT NULL,
  advertised_asin STRING NOT NULL,
  campaign_id STRING NOT NULL,
  ad_group_id STRING NOT NULL,
  keyword_id STRING NOT NULL,
  -- Default measures (SP=1d, SB=14d from source)
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
  data_source STRING,
  -- Metadata
  first_seen_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP(),
  last_updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP(),
  -- Primary Key
  PRIMARY KEY (DATE, PURCHASED_ASIN, advertised_asin, campaign_id, ad_group_id, keyword_id) NOT ENFORCED
)
PARTITION BY DATE_TRUNC(DATE, YEAR)
CLUSTER BY PURCHASED_ASIN, DATE;

-- =============================================
-- TABLE DESCRIPTION
-- =============================================
--
-- Accumulation table for purchased product data from Amazon Ads.
-- Data is MERGEd from V_SRC_AmazonAds_purchased_product:
-- - New rows: INSERT with 1d measures captured (COALESCE of source 1d or default measures)
-- - Existing rows: UPDATE all measures EXCEPT 1d (preserving early 1d snapshot)
--
-- This is critical for SB campaigns which only have 14d attribution in Fivetran.
-- By capturing the 14d value on first appearance (when it's still small/fresh),
-- we approximate the 1d attribution window.
--
-- SP campaigns already have true 1d values from Fivetran, so accumulation
-- simply preserves them as-is.
--
-- =============================================
