-- DE_FAMILY_INTENT_OVERRIDE: per-(family x intent theme) manual relevance override.
-- DE_INTENT_THEMES.is_active is GLOBAL — it can't express "school is irrelevant for LolliME
-- but fine for Lollibox". Relevance is really per family, so this table forces an intent
-- ON or OFF for one family, beating the automatic fit+profit gates in V_INTENT_KEYWORDS.
--   force_relevant = FALSE -> never suggest this intent for this family (e.g. a money-loser
--                             the profit gate hasn't caught yet, or an off-brand theme)
--   force_relevant = TRUE  -> always suggest it, even if it fails the rank/profit gates
--                             (e.g. a strategic bet with no data yet)
-- Leave a family x intent absent to let the automatic gates decide.
-- SOP: architecture/INTENT_CAMPAIGN_MODEL.md §A.2b
-- Created: 2026-07-16
CREATE TABLE IF NOT EXISTS `onyga-482313.OI.DE_FAMILY_INTENT_OVERRIDE` (
  parent_name STRING NOT NULL,      -- DIM_PRODUCT.parent_name (family)
  intent_key STRING NOT NULL,       -- DE_INTENT_THEMES.intent_key
  force_relevant BOOL NOT NULL,     -- TRUE = force on, FALSE = force off
  reason STRING,                    -- why — keep the judgement auditable
  created_at TIMESTAMP,
  updated_at TIMESTAMP
);
