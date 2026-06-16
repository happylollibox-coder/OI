-- =============================================
-- DE_NEGATIVE_TARGETS — warehouse-owned negative PRODUCT-targeting registry
-- =============================================
--
-- Sibling of DE_NEGATIVE_KEYWORDS for negative product (ASIN/category) targets.
-- Replaces the frozen Fivetran source `negative_targeting_clause_history`
-- (stuck at 2025-12-29). Seeded from an Amazon bulksheet download via
-- tools/load_negatives_seed.py; maintained by SP_SYNC_NEGATIVES from
-- FACT_PPC_CHANGE_LOG (NEGATE_* on product targets / REMOVE).
--
-- Grain: one row per negative product target (campaign/ad-group + expression).
-- Project: onyga-482313 | Dataset: OI
-- =============================================

CREATE TABLE IF NOT EXISTS `onyga-482313.OI.DE_NEGATIVE_TARGETS` (
  negative_id           STRING,               -- Product Targeting ID from the sheet, else minted negt_<hash12>
  campaign_id           STRING NOT NULL,
  campaign_name         STRING,
  ad_group_id           STRING,               -- NULL for campaign-level
  ad_group_name         STRING,
  targeting_expression  STRING NOT NULL,      -- e.g. asin="B0XXXXXXX" or category="..."
  level                 STRING NOT NULL,      -- CAMPAIGN | AD_GROUP
  state                 STRING NOT NULL,      -- ENABLED | REMOVED
  source                STRING NOT NULL,      -- SEED | COACH | MANUAL
  added_at              TIMESTAMP NOT NULL,
  removed_at            TIMESTAMP,
  change_id             STRING,
  source_file           STRING,
  updated_at            TIMESTAMP NOT NULL
);
