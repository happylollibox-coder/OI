-- =============================================
-- OI Database Project - DIM_STRATEGY_CAMPAIGN_TEMPLATE Table
-- =============================================
--
-- Purpose: Defines the campaign mix (recipe) for each strategy template.
--          Each strategy prescribes 1-4 specific campaigns to open,
--          specifying ad format, match type, bids, and placement settings.
--
--          Used by V_EXPERIMENT_SUGGESTED_CAMPAIGNS to expand each suggestion
--          into actionable "open these campaigns" instructions.
--
-- Grain: One row per strategy + campaign_seq
--
-- Project: onyga-482313
-- Dataset: OI
--
-- =============================================

CREATE TABLE IF NOT EXISTS `onyga-482313.OI.DIM_STRATEGY_CAMPAIGN_TEMPLATE` (
  strategy_id           STRING    NOT NULL,   -- FK to DIM_STRATEGY_TEMPLATE
  campaign_seq          INT64     NOT NULL,   -- 1, 2, 3... priority order
  ad_format             STRING    NOT NULL,   -- SP, SB_VIDEO, SB_STORE
  match_type            STRING    NOT NULL,   -- EXACT, BROAD, AUTO, PHRASE, PRODUCT_TARGETING
  bidding_strategy      STRING,               -- DOWN_ONLY, UP_AND_DOWN
  bid_min               FLOAT64,
  bid_max               FLOAT64,
  daily_budget          FLOAT64,
  top_of_search_pct     INT64,                -- TOS bid adjustment %
  product_page_pct      INT64,                -- Product page bid adjustment %
  purpose               STRING,               -- What this campaign does
  naming_hint           STRING,               -- Naming convention hint
  is_required           BOOL      DEFAULT TRUE,  -- Must-have vs nice-to-have
  notes                 STRING
);
