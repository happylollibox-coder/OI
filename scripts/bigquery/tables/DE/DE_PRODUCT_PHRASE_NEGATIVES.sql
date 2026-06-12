-- =============================================
-- OI Database Project - DE_PRODUCT_PHRASE_NEGATIVES
-- =============================================
--
-- Purpose: Curated per-product negative keyword phrase list.
--          Used when generating new campaign bulksheets to auto-include
--          Campaign Negative Keyword rows.
--
-- Resolution logic (at query time via V_PRODUCT_PHRASE_NEGATIVES):
--   1. '_ALL' rows apply to every product family
--   2. Family-level rows (product_short_name IS NULL) apply to all products in that family
--   3. Product-level rows (product_short_name IS NOT NULL) override family-level
--
-- Defense exclusion: BRAND_DEFENSE and PRODUCT_DEFENSE strategies
--                    should NOT use negative phrases from this table.
--
-- Seed script: tools/seed_product_phrase_negatives.py
--
-- Project: onyga-482313
-- Dataset: OI
-- =============================================

CREATE TABLE IF NOT EXISTS `onyga-482313.OI.DE_PRODUCT_PHRASE_NEGATIVES` (
  id STRING NOT NULL,                              -- UUID
  parent_name STRING NOT NULL,                     -- '_ALL', 'Lollibox', 'Bottle', 'Fresh', 'LolliME'
  product_short_name STRING,                       -- NULL = applies to ALL products in family
  phrase STRING NOT NULL,                          -- The negative keyword text
  match_type STRING NOT NULL,                      -- 'Negative Phrase' or 'Negative Exact'
  source STRING NOT NULL,                          -- 'MANUAL' or 'COACH'
  status STRING NOT NULL,                          -- 'ACTIVE' or 'INACTIVE'
  created_at TIMESTAMP,
  updated_at TIMESTAMP
);
