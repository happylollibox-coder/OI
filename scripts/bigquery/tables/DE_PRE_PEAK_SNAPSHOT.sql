-- =====================================================
-- DE_PRE_PEAK_SNAPSHOT
-- Captures campaign settings BEFORE a Boost phase starts.
-- Used by Cooldown to know what to "restore to" after peak.
-- One row per campaign × target per holiday.
-- =====================================================
CREATE TABLE IF NOT EXISTS `onyga-482313.OI.DE_PRE_PEAK_SNAPSHOT` (
  -- Identity
  snapshot_date         DATE          NOT NULL,   -- when snapshot was taken (= boost_start date)
  holiday_name          STRING        NOT NULL,   -- e.g. "Easter"
  holiday_date          DATE          NOT NULL,   -- actual holiday date

  -- Campaign
  campaign_id           STRING        NOT NULL,
  campaign_name         STRING,
  campaign_type         STRING,                   -- SP / SB / SD
  bidding_strategy      STRING,
  daily_budget          FLOAT64,

  -- Targeting (one row per auto-targeting group or keyword)
  target_id             STRING,                   -- targeting_clause target_id or keyword_id
  targeting             STRING,                   -- loose-match, close-match, or keyword text
  targeting_type        STRING,                   -- QUERY_BROAD_REL_MATCHES, KEYWORD, etc.
  pre_peak_bid          FLOAT64,                  -- bid at snapshot time

  -- Campaign-level placement adjustments
  tos_pct               INT64         DEFAULT 0,  -- top-of-search %
  product_page_pct      INT64         DEFAULT 0,  -- product page %
  b2b_pct               INT64         DEFAULT 0,  -- Amazon Business %

  -- CPC baseline (30d avg before boost_start)
  avg_cpc_30d           FLOAT64,                  -- avg CPC over 30 days pre-boost
  avg_daily_spend_30d   FLOAT64,                  -- avg daily spend pre-boost
  avg_daily_orders_30d  FLOAT64,                  -- avg daily orders pre-boost

  -- Metadata
  created_at            TIMESTAMP     DEFAULT CURRENT_TIMESTAMP()
);
