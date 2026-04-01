-- =============================================
-- OI Database Project - DIM_AD_keyword Table
-- =============================================
--
-- Purpose: Dimension table for Amazon Ads keywords
-- Source: V_SRC_AmazonAds_keyword view (includes both SP and SB campaigns)
-- Pattern: TRUNCATE + INSERT (full refresh)
-- Project: onyga-482313
-- Dataset: OI
--
-- =============================================

CREATE OR REPLACE TABLE `onyga-482313.OI.DIM_AD_keyword` (
  -- Primary Key
  keyword_id STRING NOT NULL,
  
  -- Foreign Keys
  ad_group_id STRING NOT NULL,
  campaign_id STRING NOT NULL,
  
  -- Keyword Attributes
  keyword_text STRING,
  keyword_state STRING,
  match_type STRING,
  
  -- Fivetran Metadata
  _fivetran_synced TIMESTAMP,
  
  -- Constraints
  PRIMARY KEY (keyword_id, ad_group_id, campaign_id) NOT ENFORCED
)
CLUSTER BY campaign_id, ad_group_id, keyword_id;

-- =============================================
-- TABLE DESCRIPTION
-- =============================================
--
-- This dimension table stores Amazon Ads keyword master data from V_SRC_AmazonAds_keyword view.
-- Keywords are identified by keyword_id, ad_group_id, and campaign_id combination.
--
-- Key Features:
-- - keyword_id: Unique identifier for the keyword
-- - ad_group_id: Foreign key to ad group
-- - campaign_id: Foreign key to campaign
-- - keyword_text: The actual keyword text
-- - keyword_state: State of the keyword (e.g., 'enabled', 'paused')
-- - match_type: Match type (e.g., 'exact', 'phrase', 'broad')
-- - TRUNCATE + INSERT pattern: Full refresh on each run
--
-- Population:
-- - Populated via SP_LOAD_DIM_AD_keyword stored procedure
-- - Source: V_SRC_AmazonAds_keyword view (includes both SP and SB campaigns)
-- - Refresh: Daily via orchestrator
