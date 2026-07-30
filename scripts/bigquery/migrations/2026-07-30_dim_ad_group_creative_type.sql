-- =============================================
-- Migration: DIM_AD_GROUP.creative_type (2026-07-30)
-- =============================================
--
-- Adds the SB creative type to DIM_AD_GROUP as a derived Type-1 attribute, so the
-- ad_group -> creative_type derivation lives in ONE place (SP_LOAD_DIM_AD_GROUP)
-- instead of being copy-pasted in 4 views (V_ADS_COACH_DATA, V_WEEKLY_CELL_NET,
-- V_INTENT_KEYWORDS, V_CAMPAIGN_ROLE — the V_INTENT_KEYWORDS copy had already
-- drifted: it lacked the cost>0 filter the others had).
--
-- cost>0 decision (deliberate, data-checked 2026-07-30): the canonical derivation
-- does NOT filter on cost. Filtered vs unfiltered values never disagree where both
-- exist (0 of 58 spending ad groups differ), and the unfiltered read covers 23
-- zero-spend ad groups (new/paused SB launches) the filter left NULL.
--
-- Backfill: run `CALL onyga-482313.OI.SP_LOAD_DIM_AD_GROUP()` after this ALTER —
-- its Step 3 (Type-1 creative_type refresh) populates all rows, historical included.
--
-- Note: ADD COLUMN appends to the end of the live schema, so live column order
-- differs from a fresh CREATE off tables/DIM/DIM_AD_GROUP.sql. Harmless: the loader
-- uses explicit column lists.
--
-- =============================================

ALTER TABLE `onyga-482313.OI.DIM_AD_GROUP`
ADD COLUMN IF NOT EXISTS creative_type STRING;

ALTER TABLE `onyga-482313.OI.DIM_AD_GROUP`
ALTER COLUMN creative_type
SET OPTIONS (description = 'SB creative type (BRAND_VIDEO/PRODUCT_COLLECTION/VIDEO/STORE_SPOTLIGHT/...) derived in SP_LOAD_DIM_AD_GROUP from V_SRC_AmazonAds_sb_ad_report with campaign-name fallback; Type 1 (refreshed in place); NULL for SP ad groups.');
