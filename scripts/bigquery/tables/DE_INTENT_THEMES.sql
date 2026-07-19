-- DE_INTENT_THEMES: registry of "intent themes" — the grouping unit for intent-grouped campaigns
-- (family × match-type × intent). Editable seed table; seeded broadly from the live segment
-- vocabulary, then pruned by Ori.
-- SOP: architecture/INTENT_CAMPAIGN_MODEL.md §A
-- NOTE ON NAMING: OI already uses "intent" for the keyword CLASS (BRAND/PRODUCT/GENERIC,
-- see V_KEYWORD_INTENT_CLASS). That meaning is unchanged. This table holds the *theme* bucket
-- (birthday, easter, beauty, journal…) — always call it an "intent theme".
-- Created: 2026-07-16
CREATE TABLE IF NOT EXISTS `onyga-482313.OI.DE_INTENT_THEMES` (
  intent_key STRING NOT NULL,            -- PK, kebab-case: 'birthday', 'easter', 'tween-gift'
  label STRING NOT NULL,                 -- display label: 'Birthday'
  intent_type STRING NOT NULL,           -- GENERIC | TIME_BASED
  -- Match rule: a term matches when ALL non-null match_* fields match (AND).
  -- Fields compare against FACT_RESEARCH_RANKED columns of the same name.
  match_occasion STRING,                 -- = FACT_RESEARCH_RANKED.occasion   (Birthday, Sleepover…)
  match_holiday STRING,                  -- = FACT_RESEARCH_RANKED.holiday    (Christmas, Easter…)
  match_product_type STRING,             -- = FACT_RESEARCH_RANKED.product_type (Beauty, Journal & Diary…)
  match_age_group STRING,                -- = FACT_RESEARCH_RANKED.age_group  (10-12 (Tween)…)
  match_keyword_regex STRING,            -- REGEXP_CONTAINS over LOWER(query_text), e.g. r'\bgifts?\b'
  holiday_name STRING,                   -- FK -> DIM_US_HOLIDAYS.holiday_name; supplies start/pause
                                         -- dates (boost_start / cooldown_end) for TIME_BASED intents
  cross_family BOOL,                     -- eligible for Brand-Spotlight / brand-store grouping
  is_active BOOL,                        -- excluded from V_INTENT_KEYWORDS when false
  priority INT64,                        -- tie-break ordering when a term matches several intents
  notes STRING,
  created_at TIMESTAMP,
  updated_at TIMESTAMP
);
