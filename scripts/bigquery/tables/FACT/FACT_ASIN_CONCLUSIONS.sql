-- =============================================
-- OI Database Project - FACT_ASIN_CONCLUSIONS Table
-- =============================================
--
-- Purpose: Strategy-level conclusions from experiments.
--          Captures what each strategy does for each ASIN/segment:
--          ads ROAS, SQP organic lift, per-format performance, and actionable learnings.
--
--          Lifecycle:
--            1. SP_UPDATE_ASIN_CONCLUSIONS runs every 14+ days on ACTIVE experiments
--            2. Creates/updates DRAFT rows with latest data
--            3. User can set status = 'DISABLED' to exclude from future suggestions
--            4. DRAFT rows are continuously updated; DISABLED rows are skipped
--
-- Grain: One row per asin + strategy_id + experiment_segment + season_context
--
-- Dependencies: SP_UPDATE_ASIN_CONCLUSIONS (populates this table)
-- Downstream:   V_EXPERIMENT_SUGGESTED_CAMPAIGNS (reads DRAFT rows for budgets)
--
-- Project: onyga-482313
-- Dataset: OI
--
-- =============================================

CREATE TABLE IF NOT EXISTS `onyga-482313.OI.FACT_ASIN_CONCLUSIONS`
(
  -- Composite key
  asin                        STRING    NOT NULL,
  strategy_id                 STRING    NOT NULL,     -- EXACT_BOOST, HUNTER, LOW_COST_DISCOVERY, etc.
  experiment_segment          STRING    NOT NULL,     -- BRAND, PRODUCT, ACTIVITY, BIRTHDAY_KIDS, GIFT_TEEN, etc.
  season_context              STRING    NOT NULL,     -- NORMAL, PEAK

  -- Lifecycle
  status                      STRING    NOT NULL,     -- DRAFT, DISABLED
  created_at                  TIMESTAMP NOT NULL,
  updated_at                  TIMESTAMP NOT NULL,

  -- 3-tier ROAS (all where > 1.0 = profitable)
  ads_only_net_roas           FLOAT64,                -- Tier 2: (ads_units * margin) / ad_spend
  sqp_net_roas                FLOAT64,                -- Tier 3: (sqp_purchases * margin) / ad_spend
  asin_net_roas               FLOAT64,                -- Tier 1: (all_asin_units * margin) / ad_spend (reference only)
  traditional_roas            FLOAT64,                -- Revenue / ad_spend (for reference)

  -- SQP organic metrics (search-term-level, from FACT_SEARCH_QUERY)
  sqp_organic_purchases       INT64,                  -- Your purchases on experiment search terms (organic + ads)
  sqp_matched_terms           INT64,                  -- How many experiment search terms matched SQP data
  sqp_weeks_observed          INT64,                  -- SQP weeks of data

  -- Per ad-format performance (ads_only_net_roas per format)
  sp_net_roas                 FLOAT64,                -- SP campaigns net ROAS
  sp_cost                     FLOAT64,
  sp_orders                   INT64,
  sb_video_net_roas           FLOAT64,                -- SB_VIDEO campaigns net ROAS
  sb_video_cost               FLOAT64,
  sb_video_orders             INT64,
  sb_store_net_roas           FLOAT64,                -- SB_STORE campaigns net ROAS
  sb_store_cost               FLOAT64,
  sb_store_orders             INT64,

  -- Budget and bidding
  proven_daily_budget         FLOAT64,                -- Actual avg daily spend
  avg_cpc                     FLOAT64,                -- Average cost per click
  avg_bid                     FLOAT64,                -- Average keyword bid

  -- Data backing
  experiment_count            INT64,
  total_experiment_days       INT64,
  total_ad_spend              FLOAT64,
  contributing_experiment_ids ARRAY<STRING>,

  -- Auto-generated learning
  learning_summary            STRING,                 -- Human-readable conclusion text

  -- Context
  product_short_name          STRING,
  avg_margin_per_unit         FLOAT64,

  -- Parent family metrics (cross-sibling impact)
  parent_name                 STRING,                  -- Product family (e.g. 'lollibox', 'LolliME', 'fresh')
  parent_family_net_profit    FLOAT64,                 -- Family-level: all sibling margins - all family ad spend
  parent_family_net_roas      FLOAT64,                 -- Family-level ROAS
  parent_family_ad_spend      FLOAT64,                 -- Total ad spend across all siblings
  parent_family_units         INT64                    -- Total units sold across all siblings
)
OPTIONS (
  description = "Strategy-level experiment conclusions with DRAFT/DISABLED lifecycle. DRAFT rows auto-update from active experiments with 14+ days data. Grain: asin + strategy_id + experiment_segment + season_context."
);
