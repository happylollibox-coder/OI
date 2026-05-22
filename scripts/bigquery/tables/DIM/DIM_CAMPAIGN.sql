-- =============================================
-- OI Database Project - DIM_CAMPAIGN Table
-- =============================================
--
-- Purpose: SCD Type 2 dimension table for Amazon Ads campaign configuration
-- Source: V_SRC_AmazonAds_campaign_history (Fivetran)
-- Pattern: SCD2 (close old row, insert new version on change)
-- Tracked fields: campaign_name, campaign_type, state, serving_status,
--                 daily_budget, bidding_strategy, portfolio_id
-- effective_from/to: DATETIME derived from `date` column (last_updated_date)
-- Project: onyga-482313
-- Dataset: OI
--
-- =============================================

CREATE OR REPLACE TABLE `onyga-482313.OI.DIM_CAMPAIGN` (
  -- Business Key
  campaign_id STRING NOT NULL,

  -- Campaign Attributes (tracked for changes)
  campaign_name STRING,
  campaign_type STRING,
  state STRING,
  serving_status STRING,
  daily_budget FLOAT64,
  bidding_strategy STRING,
  portfolio_id STRING,
  portfolio_name STRING,

  -- Non-tracked attributes
  profile_id STRING,
  creation_date TIMESTAMP,
  last_updated_date TIMESTAMP,
  _fivetran_synced TIMESTAMP,

  -- SCD Type 2 columns (DATETIME precision from source date column)
  effective_from DATETIME NOT NULL,
  effective_to DATETIME,
  is_current BOOL NOT NULL
)
CLUSTER BY campaign_id, is_current;

-- =============================================
-- TABLE DESCRIPTION
-- =============================================
--
-- SCD Type 2 dimension tracking Amazon Ads campaign configuration over time.
-- Business key: campaign_id
-- Tracked fields trigger a new version when changed:
--   campaign_name, campaign_type, state, serving_status,
--   daily_budget, bidding_strategy, portfolio_id, portfolio_name
--
-- SCD2 timing:
-- - effective_from = DATETIME(date) from source view (last_updated_date)
-- - effective_to   = next version's effective_from (NULL if current)
-- - is_current     = TRUE for the latest version
--
-- Population:
-- - Populated via SP_LOAD_DIM_CAMPAIGN stored procedure
-- - Source: V_SRC_AmazonAds_campaign_history (Fivetran, auto-synced daily)
-- - Refresh: Daily via SP_ORCHESTRATE_DAILY_REFRESH
--
-- Query patterns:
--   Current state:  WHERE is_current = TRUE
--   Point-in-time:  WHERE effective_from <= @dt AND (effective_to IS NULL OR effective_to > @dt)
