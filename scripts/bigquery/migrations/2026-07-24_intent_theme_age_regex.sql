-- 2026-07-24 — review pass 3, found by Ori on the Intent Configuration page.
--
-- "10 year old girl birthday gifts" resolved to `birthday-gift` when it should be
-- `tween-birthday-gift`. Not a one-off: all 24 age-based compound themes match on
-- match_age_group, which is a FACT_RESEARCH_RANKED attribute. On the ads side there is no
-- attribute — only the words the shopper typed — so none of them could ever win, and every
-- age-qualified query collapsed onto its age-blind parent.
--
-- Fix: a third ads-side condition, match_ads_age_regex, ANDed alongside match_ads_regex and
-- match_keyword_regex in V_ADS_SEARCH_TERM_INTENT. That makes tween-birthday-gift specificity
-- 3 (birthday AND gift AND tween age) against birthday-gift's 2, so the more specific theme
-- wins on its own merits rather than on a priority tie-break.
--
-- The 8-14 bucket overlaps both Tween (8-12) and Teen (13-17) and would tie tween-* at
-- specificity 3 and priority 5, where the alphabetical tie-break hands it the win. Demoted to
-- priority 6 so the named age bands always resolve first and 8-14 only catches what they miss.
--
-- SOP: docs/superpowers/specs/2026-07-24-intent-coverage-phase0-design.md

ALTER TABLE `onyga-482313.OI.DE_INTENT_THEMES`
  ADD COLUMN IF NOT EXISTS match_ads_age_regex STRING;

-- 5-7 (Kid)
UPDATE `onyga-482313.OI.DE_INTENT_THEMES`
SET match_ads_age_regex = r'\b[567]\s*(year|yr)|\bages?\s*[567]\b|\b(kid|child|little girl)s?\b',
    updated_at = CURRENT_TIMESTAMP()
WHERE match_age_group = '5-7 (Kid)';

-- 8-12 (Tween). Includes bare "tween" and the "8-12" / "10-12" range spellings shoppers use.
UPDATE `onyga-482313.OI.DE_INTENT_THEMES`
SET match_ads_age_regex = r'\b(8|9|10|11|12)\s*(year|yr)|\bages?\s*(8|9|10|11|12)\b|\btween\b|\b(8|9|10)[\s-]*1[0-2]\b',
    updated_at = CURRENT_TIMESTAMP()
WHERE match_age_group = '8-12 (Tween)';

-- 13-17 (Teen)
UPDATE `onyga-482313.OI.DE_INTENT_THEMES`
SET match_ads_age_regex = r'\b1[3-7]\s*(year|yr)|\bages?\s*1[3-7]\b|\bteen(s|age|ager|agers)?\b',
    updated_at = CURRENT_TIMESTAMP()
WHERE match_age_group = '13-17 (Teen)';

-- 8-14 — the overlapping catch-all.
UPDATE `onyga-482313.OI.DE_INTENT_THEMES`
SET match_ads_age_regex = r'\b(8|9|1[0-4])\s*(year|yr)|\bages?\s*(8|9|1[0-4])\b',
    priority = 6,
    notes = CONCAT(IFNULL(notes,''), ' | 2026-07-24 pass 3: priority 5->6. Overlaps Tween and Teen; at equal priority the alphabetical tie-break stole "10 year old girl birthday gifts" from tween-birthday-gift.'),
    updated_at = CURRENT_TIMESTAMP()
WHERE match_age_group = '8-14';

-- The bare age-qualified gift themes (priority 41) get the same patterns; they sit below the
-- occasion compounds and above plain `gift` (40)... which means `gift` would win the priority
-- tie. Specificity settles it instead: tween-gift is 2 conditions (gift AND age), gift is 1.
UPDATE `onyga-482313.OI.DE_INTENT_THEMES`
SET priority = 39, updated_at = CURRENT_TIMESTAMP()
WHERE intent_key IN ('kid-gift', 'tween-gift', 'teen-gift');
