-- =============================================
-- OI Database Project - DIM_AD_GROUP Table
-- =============================================
--
-- Purpose: SCD Type 2 dimension table for Amazon Ads ad group configuration
-- Source: V_SRC_AmazonAds_ad_group_history (Fivetran)
-- Pattern: SCD2 (close old row, insert new version on change)
-- Tracked fields: ad_group_name, state, serving_status, default_bid
-- effective_from/to: DATETIME derived from `date` column (last_updated_date)
-- Project: onyga-482313
-- Dataset: OI
--
-- =============================================

CREATE OR REPLACE TABLE `onyga-482313.OI.DIM_AD_GROUP` (
  -- Business Key
  ad_group_id STRING NOT NULL,

  -- Foreign Key
  campaign_id STRING NOT NULL,

  -- Ad Group Attributes (tracked for changes)
  ad_group_name STRING,
  state STRING,
  serving_status STRING,
  default_bid FLOAT64,

  -- Non-tracked attributes
  campaign_type STRING,
  creation_date TIMESTAMP,
  last_updated_date TIMESTAMP,
  _fivetran_synced TIMESTAMP,

  -- SCD Type 2 columns (DATETIME precision from source date column)
  effective_from DATETIME NOT NULL,
  effective_to DATETIME,
  is_current BOOL NOT NULL
)
CLUSTER BY campaign_id, ad_group_id, is_current;

-- =============================================
-- TABLE DESCRIPTION
-- =============================================
--
-- SCD Type 2 dimension tracking Amazon Ads ad group configuration over time.
-- Business key: ad_group_id
-- Tracked fields trigger a new version when changed:
--   ad_group_name, state, serving_status, default_bid
--
-- SCD2 timing:
-- - effective_from = DATETIME(date) from source view (last_updated_date)
-- - effective_to   = next version's effective_from (NULL if current)
-- - is_current     = TRUE for the latest version
--
-- Population:
-- - Populated via SP_LOAD_DIM_AD_GROUP stored procedure
-- - Source: V_SRC_AmazonAds_ad_group_history (Fivetran, auto-synced daily)
-- - Refresh: Daily via SP_ORCHESTRATE_DAILY_REFRESH
--
-- Query patterns:
--   Current state:  WHERE is_current = TRUE
--   Point-in-time:  WHERE effective_from <= @dt AND (effective_to IS NULL OR effective_to > @dt)
