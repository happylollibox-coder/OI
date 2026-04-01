-- ============================================================================
-- FACT_CAMPAIGN_CONFIG: Stores campaign configuration from Amazon Ads Bulksheets
-- Source: Amazon Ads Bulksheets v2.0 (.xlsx)
-- Contains: campaigns, ad groups, keywords, negative keywords, product targeting,
--           product ads, bidding adjustments, negative product targeting,
--           campaign negative keywords
-- One row per entity. snapshot_date tracks when the bulksheet was imported.
-- ============================================================================

CREATE TABLE IF NOT EXISTS `onyga-482313.OI.FACT_CAMPAIGN_CONFIG` (
  -- Import metadata
  snapshot_date DATE NOT NULL,
  source_file STRING,

  -- Entity hierarchy
  entity_type STRING NOT NULL,      -- CAMPAIGN, AD_GROUP, KEYWORD, NEGATIVE_KEYWORD,
                                    -- PRODUCT_TARGETING, PRODUCT_AD, BIDDING_ADJUSTMENT,
                                    -- NEGATIVE_PRODUCT_TARGETING, CAMPAIGN_NEGATIVE_KEYWORD
  campaign_id STRING NOT NULL,
  campaign_name STRING,
  ad_group_id STRING,
  ad_group_name STRING,

  -- Campaign-level fields
  campaign_state STRING,            -- enabled, paused, archived
  daily_budget FLOAT64,
  bidding_strategy STRING,          -- Dynamic bids - down only, Dynamic bids - up and down, Fixed bid
  targeting_type STRING,            -- Manual, Auto
  start_date STRING,

  -- Ad Group-level fields
  ad_group_state STRING,
  ad_group_default_bid FLOAT64,

  -- Keyword-level fields
  keyword_id STRING,
  keyword_text STRING,
  match_type STRING,                -- Broad, Phrase, Exact, Negative Phrase, Negative Exact
  bid FLOAT64,
  keyword_state STRING,

  -- Product Targeting fields
  product_targeting_id STRING,
  product_targeting_expression STRING,
  pt_bid FLOAT64,
  pt_state STRING,

  -- Product Ad fields
  ad_id STRING,
  sku STRING,
  asin STRING,
  ad_state STRING,

  -- Bidding Adjustment fields
  placement STRING,                 -- Placement Top, Placement Rest Of Search, Placement Amazon Business
  placement_percentage FLOAT64      -- e.g. 30 means +30% bid for that placement
)
PARTITION BY snapshot_date
CLUSTER BY entity_type, campaign_id;
