-- 2026-07-24 — Phase 0 of the intent-CVR work: let intent themes classify ADS search terms.
--
-- Problem: DE_INTENT_THEMES matches on FACT_RESEARCH_RANKED attribute columns
-- (match_occasion / match_holiday / match_product_type). That universe is research/SQP-derived.
-- Only 6.8% of the 201,054 distinct FACT_AMAZON_ADS.search_term values have a row there, and
-- only 11.1% of ads clicks carry a real occasion. The traffic that is missed is the better
-- traffic — LolliME back-to-school, Aug 1 – Sep 28 2025: tagged terms 2.22% CVR / $0.20 GP per
-- click, untagged school terms 4.53% CVR / $0.72 GP per click.
--
-- Fix: add match_ads_regex — a pattern matched against LOWER(FACT_AMAZON_ADS.search_term) —
-- so a theme can be recognised from the words a shopper actually typed. Additive: existing
-- columns and V_INTENT_KEYWORDS behaviour are untouched.
--
-- Match rule in V_ADS_SEARCH_TERM_INTENT:
--   match_ads_regex must match, AND match_keyword_regex must match when non-null.
--   Compounds therefore need both (christmas-gift = christmas pattern AND \bgifts?\b).
-- SOP: docs/superpowers/specs/2026-07-24-intent-coverage-phase0-design.md

ALTER TABLE `onyga-482313.OI.DE_INTENT_THEMES`
  ADD COLUMN IF NOT EXISTS match_ads_regex STRING;

-- Occasion / holiday themes (priority 10-20).
-- back-to-school deliberately includes a bare \bschool\b arm: the previous rule was
-- 'back to school|school supplies', which caught the browsers ("school supplies for girls")
-- and missed every buyer ("school journal for girl", "middle school girls gifts",
-- "personal drawing school kit for kids").
UPDATE `onyga-482313.OI.DE_INTENT_THEMES` SET match_ads_regex = r'back to school|school suppl|\bschool\b', updated_at = CURRENT_TIMESTAMP() WHERE intent_key = 'back-to-school';
UPDATE `onyga-482313.OI.DE_INTENT_THEMES` SET match_ads_regex = r'black ?friday', updated_at = CURRENT_TIMESTAMP() WHERE intent_key = 'black-friday';
UPDATE `onyga-482313.OI.DE_INTENT_THEMES` SET match_ads_regex = r'christmas|xmas|stocking stuffer|advent calendar|\bsanta\b', updated_at = CURRENT_TIMESTAMP() WHERE intent_key IN ('christmas', 'christmas-gift');
UPDATE `onyga-482313.OI.DE_INTENT_THEMES` SET match_ads_regex = r'cyber ?monday', updated_at = CURRENT_TIMESTAMP() WHERE intent_key = 'cyber-monday';
UPDATE `onyga-482313.OI.DE_INTENT_THEMES` SET match_ads_regex = r'easter', updated_at = CURRENT_TIMESTAMP() WHERE intent_key IN ('easter', 'easter-gift', 'easter-basket');
UPDATE `onyga-482313.OI.DE_INTENT_THEMES` SET match_ads_regex = r'halloween|trick or treat', updated_at = CURRENT_TIMESTAMP() WHERE intent_key = 'halloween';
UPDATE `onyga-482313.OI.DE_INTENT_THEMES` SET match_ads_regex = r"mother'?s day|\bmom\b", updated_at = CURRENT_TIMESTAMP() WHERE intent_key IN ('mothers-day', 'mothers-day-gift');
UPDATE `onyga-482313.OI.DE_INTENT_THEMES` SET match_ads_regex = r'prime day', updated_at = CURRENT_TIMESTAMP() WHERE intent_key = 'prime-day';
UPDATE `onyga-482313.OI.DE_INTENT_THEMES` SET match_ads_regex = r'valentine|galentine', updated_at = CURRENT_TIMESTAMP() WHERE intent_key IN ('valentines-day', 'valentines-gift');
UPDATE `onyga-482313.OI.DE_INTENT_THEMES` SET match_ads_regex = r'birthday|\bbday\b', updated_at = CURRENT_TIMESTAMP() WHERE intent_key IN ('birthday', 'birthday-gift');
UPDATE `onyga-482313.OI.DE_INTENT_THEMES` SET match_ads_regex = r'\bcamp\b|summer camp', updated_at = CURRENT_TIMESTAMP() WHERE intent_key = 'camp';
UPDATE `onyga-482313.OI.DE_INTENT_THEMES` SET match_ads_regex = r'encourag|motivational|affirmation|self.esteem', updated_at = CURRENT_TIMESTAMP() WHERE intent_key = 'encouragement';
UPDATE `onyga-482313.OI.DE_INTENT_THEMES` SET match_ads_regex = r'get well|feel better', updated_at = CURRENT_TIMESTAMP() WHERE intent_key = 'get-well';
UPDATE `onyga-482313.OI.DE_INTENT_THEMES` SET match_ads_regex = r'graduation|\bgrad\b', updated_at = CURRENT_TIMESTAMP() WHERE intent_key = 'graduation';
UPDATE `onyga-482313.OI.DE_INTENT_THEMES` SET match_ads_regex = r'sleepover|slumber party|pajama party|\bpj party\b', updated_at = CURRENT_TIMESTAMP() WHERE intent_key = 'sleepover';
UPDATE `onyga-482313.OI.DE_INTENT_THEMES` SET match_ads_regex = r'sweet ?(16|sixteen)', updated_at = CURRENT_TIMESTAMP() WHERE intent_key = 'sweet-16';

-- Product-type themes that are reliably identifiable from raw text.
-- Left deliberately narrow — a wrong product-type tag is worse than none, because it steers
-- campaign grouping. Themes without a match_ads_regex simply never match on the ads side.
UPDATE `onyga-482313.OI.DE_INTENT_THEMES` SET match_ads_regex = r'journal|diary', updated_at = CURRENT_TIMESTAMP() WHERE intent_key = 'journal-diary';
UPDATE `onyga-482313.OI.DE_INTENT_THEMES` SET match_ads_regex = r'stationer|\bpens?\b|notebook', updated_at = CURRENT_TIMESTAMP() WHERE intent_key = 'stationery';
UPDATE `onyga-482313.OI.DE_INTENT_THEMES` SET match_ads_regex = r'keychain|key ?ring', updated_at = CURRENT_TIMESTAMP() WHERE intent_key = 'keychain';
UPDATE `onyga-482313.OI.DE_INTENT_THEMES` SET match_ads_regex = r'gift ?sets?|gift ?box', updated_at = CURRENT_TIMESTAMP() WHERE intent_key = 'gift-sets';
UPDATE `onyga-482313.OI.DE_INTENT_THEMES` SET match_ads_regex = r'mystery ?box', updated_at = CURRENT_TIMESTAMP() WHERE intent_key = 'mystery-box';
UPDATE `onyga-482313.OI.DE_INTENT_THEMES` SET match_ads_regex = r'bath|\bspa\b', updated_at = CURRENT_TIMESTAMP() WHERE intent_key = 'bath-spa';
UPDATE `onyga-482313.OI.DE_INTENT_THEMES` SET match_ads_regex = r'\bcraft|\bdiy\b', updated_at = CURRENT_TIMESTAMP() WHERE intent_key = 'crafts-diy';
UPDATE `onyga-482313.OI.DE_INTENT_THEMES` SET match_ads_regex = r'board ?game', updated_at = CURRENT_TIMESTAMP() WHERE intent_key = 'board-game';
UPDATE `onyga-482313.OI.DE_INTENT_THEMES` SET match_ads_regex = r'party suppl|party favor|party decor', updated_at = CURRENT_TIMESTAMP() WHERE intent_key = 'party-supplies';
UPDATE `onyga-482313.OI.DE_INTENT_THEMES` SET match_ads_regex = r'care package', updated_at = CURRENT_TIMESTAMP() WHERE intent_key = 'care-package';
UPDATE `onyga-482313.OI.DE_INTENT_THEMES` SET match_ads_regex = r'advent calendar', updated_at = CURRENT_TIMESTAMP() WHERE intent_key = 'advent-calendar';

-- Bare gift themes already carry match_keyword_regex = \bgifts?\b. Mirror it so they can act
-- as the lowest-specificity fallback on the ads side too.
UPDATE `onyga-482313.OI.DE_INTENT_THEMES` SET match_ads_regex = r'\bgifts?\b', updated_at = CURRENT_TIMESTAMP() WHERE intent_key = 'gift';
