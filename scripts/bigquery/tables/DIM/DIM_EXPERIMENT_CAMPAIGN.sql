-- =============================================
-- OI Database Project - DIM_EXPERIMENT_CAMPAIGN Table
-- =============================================
--
-- Purpose: Links campaigns to experiments (many campaigns per experiment)
-- Method: Manual INSERT (user links campaigns when setting up experiment)
-- Project: onyga-482313
-- Dataset: OI
--
-- =============================================

CREATE TABLE IF NOT EXISTS `onyga-482313.OI.DIM_EXPERIMENT_CAMPAIGN` (
  -- Composite Key
  experiment_id STRING NOT NULL,  -- FK to DIM_EXPERIMENT
  campaign_id STRING NOT NULL,    -- matches FACT_AMAZON_ADS.campaign_id

  -- Readability
  campaign_name STRING,

  -- Manual-entry placement settings (not available in Fivetran sync)
  top_of_search_pct INT64,     -- Amazon placement bid boost % for top-of-search (0-900)
  product_page_pct INT64,      -- Amazon placement bid boost % for product pages (0-900)
  rest_of_search_pct INT64,    -- Amazon placement bid boost % for rest of search (0-900)

  -- Notes
  notes STRING,                -- campaign-specific notes or context

  PRIMARY KEY (experiment_id, campaign_id) NOT ENFORCED
)
OPTIONS (
  description = "Links Amazon Ads campaigns to experiments. Includes manual-entry placement settings. All other settings (bids, bidding strategy, match types) are auto-enriched via V_EXPERIMENT_CAMPAIGN_SETTINGS."
);
