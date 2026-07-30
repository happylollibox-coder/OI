-- DE_INTENT_CAMPAIGN: the intent-campaign-grid registry — campaign_id ↔ (product, intent, rung).
--
-- WHY IT EXISTS
-- The grid (spec 2026-07-25) is cell = product × intent × rung with PERMANENT campaigns; all
-- seasonal movement is dated bid/state changes. Everything that reasons about a grid campaign
-- (month plan, checkpoint, outcomes) joins THROUGH this table on campaign_id.
--
-- NAMES ARE NOT KEYS. 2026-07-24 we found ME-AUTO and "ME-SP/AUTO (discovery,Mint)" are the
-- SAME campaign renamed (id 527422818407259), and LolliBall's campaigns are invisible to the
-- ASIN_BY_CAMPAIGN_NAME join entirely. campaign_name_at_creation is display-only.
--
-- LIFECYCLE
--   PENDING_UPLOAD  row created alongside the build bulksheet; campaign_id = placeholder name.
--   ACTIVE          the reconciliation job matched the name in FACT_AMAZON_ADS first-sight and
--                   LOCKED the numeric campaign_id. From then on the name may drift freely.
--   PAUSED_BAND     paused by band/state logic (seasonal OFF) — still a grid member.
--   PAUSED_DEMOTED  rung demoted (90d net ROAS < floor at conclusive clicks) — pause, never delete.
--   RETIRED         manually retired; kept for history.
--
-- rung values match CoveragePage STRAT_LABEL keys EXACTLY so label maps are shared:
--   BROAD_SP | EXACT | PHRASE | BROAD_VIDEO | BROAD_SPOTLIGHT
--   + AUTO (per-product discovery, intent_key='discovery')
--   + PT_ASIN (competitor product targeting, intent_key='competitor') — added 2026-07-25
--
-- SOP: architecture/INTENT_CAMPAIGN_GRID.md (Phase 1.4)
-- Created: 2026-07-25 (grid plan Phase 1.1)

CREATE TABLE IF NOT EXISTS `onyga-482313.OI.DE_INTENT_CAMPAIGN` (
  campaign_id STRING NOT NULL,              -- placeholder name until ACTIVE locks numeric id
  campaign_name_at_creation STRING,
  product_short_name STRING NOT NULL,
  intent_key STRING NOT NULL,
  rung STRING NOT NULL,                     -- BROAD_SP|EXACT|PHRASE|BROAD_VIDEO|BROAD_SPOTLIGHT
  tier STRING NOT NULL,                     -- A|B|LAUNCH
  state STRING NOT NULL,                    -- PENDING_UPLOAD|ACTIVE|PAUSED_BAND|PAUSED_DEMOTED|RETIRED
  admitted_reason STRING,                   -- TIER_A_BUILD|ABSORBED|LAUNCH_ADMISSION|TIER_B_GRADUATION|RUNG_EARNED
  created_at TIMESTAMP,
  updated_at TIMESTAMP,
  updated_by STRING
)
OPTIONS (
  description = "Intent-campaign-grid registry: campaign_id <-> (product, intent, rung, tier, state). Names are display-only; joins run on campaign_id (locked at reconciliation). Demotion = pause, never delete. See architecture/INTENT_CAMPAIGN_GRID.md."
);
