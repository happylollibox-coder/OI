-- =============================================
-- OI Database Project - DIM_STRATEGY_TEMPLATE Table
-- =============================================
--
-- Purpose: Predefined advertising strategy playbooks.
--          Each template describes a reusable strategy with recommended
--          campaign settings, so the system can learn which strategies
--          work best and recommend them with optimal parameters.
-- Method: Manual INSERT / UPDATE (maintained by user)
-- Project: onyga-482313
-- Dataset: OI
--
-- =============================================

CREATE TABLE IF NOT EXISTS `onyga-482313.OI.DIM_STRATEGY_TEMPLATE` (
  -- Primary Key
  strategy_id STRING NOT NULL,

  -- Strategy identity
  strategy_name STRING NOT NULL,
  description STRING,

  -- Recommended campaign settings
  recommended_campaign_type STRING,          -- SP, SB, or BOTH
  recommended_match_type STRING,             -- EXACT, BROAD, PHRASE, AUTO, MIXED
  recommended_bidding_strategy STRING,       -- DOWN_ONLY, UP_AND_DOWN, LEGACY_FOR_SALES
  recommended_top_of_search_pct INT64,       -- 0-900 (Amazon placement boost %)
  recommended_product_page_pct INT64,        -- 0-900 (Amazon placement boost %)
  recommended_bid_min FLOAT64,              -- suggested minimum keyword bid ($)
  recommended_bid_max FLOAT64,              -- suggested maximum keyword bid ($)
  recommended_daily_budget FLOAT64,         -- suggested daily campaign budget ($)

  -- Peak season modifiers (seasonal_index >= 1.5: Valentine's, Easter, BF/CM, Christmas)
  peak_bid_multiplier FLOAT64,             -- multiply base bids by this during peak (e.g. 2.0 = 2x)
  peak_budget_multiplier FLOAT64,          -- multiply base budget by this during peak
  peak_tos_add_pct INT64,                  -- add to base TOS % during peak (can be negative)
  peak_notes STRING,                       -- guidance text for peak season

  -- Off-season modifiers (seasonal_index < 0.5: summer, post-holiday Jan)
  offseason_bid_multiplier FLOAT64,        -- multiply base bids during off-season (e.g. 0.5 = half)
  offseason_budget_multiplier FLOAT64,     -- multiply base budget during off-season
  offseason_tos_add_pct INT64,             -- add to base TOS % during off-season
  offseason_notes STRING,                  -- guidance text for off-season

  -- Season applicability
  season_applicability STRING,             -- ALL_SEASONS, PEAK_ONLY, OFF_SEASON_ONLY, PEAK_PREFERRED, OFF_SEASON_PREFERRED

  -- Graduation criteria: when does an experiment using this strategy become a proven rule?
  min_experiments_to_graduate INT64,        -- min experiments needed before trusting results
  min_days_to_graduate INT64,              -- min days an experiment must run
  min_seasonal_lift_to_graduate FLOAT64,   -- min seasonal-adjusted lift % to pass

  -- When to use
  use_case STRING,                          -- description of when this strategy applies
  tags STRING,                              -- comma-separated tags for filtering

  -- Active flag
  is_active BOOL DEFAULT TRUE,

  -- Metadata
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP(),
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP(),

  PRIMARY KEY (strategy_id) NOT ENFORCED
)
OPTIONS (
  description = "Predefined advertising strategy playbooks with recommended settings. Used by the experiment system to learn which strategies produce the best organic lift."
);

-- =============================================
-- SEED DATA: 10 Strategy Templates
-- =============================================
DELETE FROM `onyga-482313.OI.DIM_STRATEGY_TEMPLATE` WHERE TRUE;

INSERT INTO `onyga-482313.OI.DIM_STRATEGY_TEMPLATE`
  (strategy_id, strategy_name, description,
   recommended_campaign_type, recommended_match_type, recommended_bidding_strategy,
   recommended_top_of_search_pct, recommended_product_page_pct,
   recommended_bid_min, recommended_bid_max, recommended_daily_budget,
   use_case, tags, is_active)
VALUES
  -- 1. Brand Defense
  ('BRAND_DEFENSE',
   'Brand Defense',
   'Protect your own brand keywords from competitor ads. Ensures your products appear at top-of-search when shoppers search for your brand name.',
   'SP', 'EXACT', 'DOWN_ONLY',
   300, 0,
   0.30, 0.75, 10.00,
   'Use when competitors are bidding on your brand name (Happy Lolli, happy lollipop journal, etc.). Always-on strategy to maintain brand search dominance.',
   'brand,defensive,always-on',
   TRUE),

  -- 2. Hunter / Competitor Conquest
  ('HUNTER',
   'Hunter',
   'Target competitor brand names and high-converting competitor product keywords to capture their traffic.',
   'SP', 'BROAD', 'UP_AND_DOWN',
   200, 100,
   0.50, 1.50, 15.00,
   'Use to steal market share from specific competitors. Best during competitor out-of-stock or when your product has a clear advantage.',
   'competitor,offensive,aggressive',
   TRUE),

  -- 3. Exact Keyword Boost
  ('EXACT_BOOST',
   'Exact Keyword Boost',
   'Push a specific proven keyword aggressively with exact match targeting and high top-of-search placement.',
   'SP', 'EXACT', 'DOWN_ONLY',
   500, 0,
   0.50, 2.00, 20.00,
   'Use for keywords already proven to convert organically. Goal is to dominate the SERP and boost organic ranking through increased sales velocity.',
   'exact,keyword,ranking,aggressive',
   TRUE),

  -- 4. Category Conquest
  ('CATEGORY_CONQUEST',
   'Category Conquest',
   'Broad and auto targeting to discover new high-potential keywords in your product category.',
   'SP', 'AUTO', 'DOWN_ONLY',
   0, 0,
   0.25, 0.75, 10.00,
   'Use for keyword discovery. Run for 2-4 weeks, harvest converting search terms, then create exact/phrase campaigns for winners.',
   'discovery,broad,auto,category',
   TRUE),

  -- 5. Product / ASIN Defense
  ('PRODUCT_DEFENSE',
   'Product Defense',
   'Target your own product detail pages to prevent competitor ads from appearing on your listings.',
   'SP', 'EXACT', 'DOWN_ONLY',
   0, 300,
   0.30, 0.75, 8.00,
   'Use when competitors are running product targeting ads on your ASINs. Focus on product page placement rather than search.',
   'defensive,product-page,asin-targeting',
   TRUE),

  -- 6. Seasonal Push
  ('SEASONAL_PUSH',
   'Seasonal Push',
   'Aggressive ad ramp-up around holidays and seasonal events with increased budgets and placement bids.',
   'BOTH', 'MIXED', 'UP_AND_DOWN',
   500, 200,
   0.75, 3.00, 30.00,
   'Use 2-3 weeks before major gift-giving holidays (Valentines, Mothers Day, Christmas). Increase bids and budget progressively during ramp-up.',
   'seasonal,holiday,aggressive,temporary',
   TRUE),

  -- 7. New Product Launch
  ('NEW_LAUNCH',
   'New Product Launch',
   'Aggressive multi-campaign strategy for new ASIN launches. Uses all match types and high visibility to build initial sales velocity.',
   'BOTH', 'MIXED', 'UP_AND_DOWN',
   400, 200,
   0.75, 2.50, 25.00,
   'Use for the first 4-8 weeks after launching a new ASIN. Combine auto discovery + exact targeting on researched keywords. Accept lower ROAS initially.',
   'launch,new-product,aggressive,multi-campaign',
   TRUE),

  -- 8. Low-Cost Discovery
  ('LOW_COST_DISCOVERY',
   'Low-Cost Discovery',
   'Auto campaigns with low bids to find converting keywords at minimal cost. The net for catching long-tail opportunities.',
   'SP', 'AUTO', 'DOWN_ONLY',
   0, 0,
   0.10, 0.35, 5.00,
   'Always-on background campaign. Low bids ensure only cheap clicks. Review weekly for search terms to promote to exact campaigns.',
   'discovery,low-cost,auto,always-on,long-tail',
   TRUE),

  -- 9. Top-of-Search Domination
  ('TOS_DOMINATION',
   'Top-of-Search Domination',
   'Extreme top-of-search placement to maximize visibility for key search terms. Trades efficiency for dominance.',
   'SP', 'EXACT', 'DOWN_ONLY',
   900, 0,
   1.00, 3.00, 25.00,
   'Use for your top 3-5 most important keywords when you need maximum visibility. Monitor ACOS closely -- this is a visibility play, not an efficiency play.',
   'tos,visibility,aggressive,exact',
   TRUE),

  -- 10. Retargeting / Re-engagement
  ('RETARGETING',
   'Retargeting',
   'Target audiences who have previously viewed or purchased your products to drive repeat purchases and cross-sells.',
   'SB', 'MIXED', 'DOWN_ONLY',
   100, 100,
   0.30, 1.00, 10.00,
   'Use Sponsored Brands with custom audiences. Effective for products with repeat purchase potential or complementary product lines.',
   'retargeting,audience,sb,repeat-purchase',
   TRUE);
