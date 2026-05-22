-- =============================================
-- OI Database Project - DIM_KEYWORD Table
-- =============================================
--
-- Purpose: SCD Type 2 dimension table for Amazon Ads keywords
--          Replaces former DIM_AD_keyword (which was TRUNCATE+INSERT and missing bid column)
-- Source: V_SRC_AmazonAds_keyword (Fivetran)
-- Pattern: SCD2 (close old row, insert new version on change)
-- Tracked fields: keyword_text, state, match_type, bid
-- effective_from/to: DATETIME derived from _fivetran_synced - 3ms
-- Project: onyga-482313
-- Dataset: OI
--
-- =============================================

CREATE OR REPLACE TABLE `onyga-482313.OI.DIM_KEYWORD` (
  -- Business Key
  keyword_id STRING NOT NULL,

  -- Foreign Keys
  ad_group_id STRING NOT NULL,
  campaign_id STRING NOT NULL,

  -- Keyword Attributes (tracked for changes)
  keyword_text STRING,
  state STRING,
  match_type STRING,
  bid FLOAT64,

  -- Fivetran Metadata
  _fivetran_synced TIMESTAMP,

  -- SCD Type 2 columns (DATETIME precision from _fivetran_synced - 3ms)
  effective_from DATETIME NOT NULL,
  effective_to DATETIME,
  is_current BOOL NOT NULL
)
CLUSTER BY campaign_id, ad_group_id, keyword_id, is_current;

-- =============================================
-- TABLE DESCRIPTION
-- =============================================
--
-- SCD Type 2 dimension tracking Amazon Ads keyword configuration over time.
-- Replaces DIM_AD_keyword which was missing the bid column and used TRUNCATE+INSERT.
-- Business key: keyword_id (unique across ad_group_id and campaign_id)
-- Tracked fields trigger a new version when changed:
--   keyword_text, state, match_type, bid
--
-- SCD2 timing:
-- - effective_from = DATETIME(_fivetran_synced) - 3 MILLISECOND
-- - effective_to   = next version's effective_from (NULL if current)
-- - is_current     = TRUE for the latest version
--
-- Population:
-- - Populated via SP_LOAD_DIM_KEYWORD stored procedure
-- - Source: V_SRC_AmazonAds_keyword (Fivetran, auto-synced daily)
-- - Refresh: Daily via SP_ORCHESTRATE_DAILY_REFRESH
--
-- Query patterns:
--   Current state:  WHERE is_current = TRUE
--   Point-in-time:  WHERE effective_from <= @dt AND (effective_to IS NULL OR effective_to > @dt)
--   Bid history:    SELECT bid, effective_from FROM DIM_KEYWORD WHERE keyword_id = @id ORDER BY effective_from
