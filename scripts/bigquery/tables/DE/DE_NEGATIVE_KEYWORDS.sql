-- =============================================
-- DE_NEGATIVE_KEYWORDS — warehouse-owned negative-keyword registry
-- =============================================
--
-- Purpose: Authoritative, always-current list of negative keywords. Replaces the
--          Fivetran source (`V_SRC_AmazonAds_negative_keyword`), whose Amazon Ads
--          negative-keyword sync has been frozen since 2026-01-03 and is unavailable.
--
-- Lifecycle:
--   1. SEED  — Ori loads the current list once from an Amazon bulksheet download
--              (tools/load_negatives_seed.py). source='SEED'.
--   2. UPKEEP — this system is the only authority that mutates it afterward:
--              SP_SYNC_NEGATIVES folds in every NEGATE_* / REMOVE_NEGATIVE we upload,
--              read from FACT_PPC_CHANGE_LOG. source='COACH' | 'MANUAL'.
--
-- Grain: one row per negative keyword (campaign/ad-group + text + match type).
--
-- Project: onyga-482313 | Dataset: OI
-- =============================================

CREATE TABLE IF NOT EXISTS `onyga-482313.OI.DE_NEGATIVE_KEYWORDS` (
  negative_id     STRING,               -- Amazon Keyword ID from the sheet, else minted neg_<hash12>
  campaign_id     STRING NOT NULL,
  campaign_name   STRING,
  ad_group_id     STRING,               -- NULL for campaign-level negatives
  ad_group_name   STRING,
  keyword_text    STRING NOT NULL,
  match_type      STRING NOT NULL,      -- NEGATIVE_EXACT | NEGATIVE_PHRASE
  level           STRING NOT NULL,      -- CAMPAIGN | AD_GROUP
  state           STRING NOT NULL,      -- ENABLED | REMOVED
  source          STRING NOT NULL,      -- SEED | COACH | MANUAL
  added_at        TIMESTAMP NOT NULL,
  removed_at      TIMESTAMP,            -- set when state flips to REMOVED
  change_id       STRING,               -- FK to FACT_PPC_CHANGE_LOG when added/removed by us
  source_file     STRING,               -- seed bulksheet filename
  updated_at      TIMESTAMP NOT NULL
);
