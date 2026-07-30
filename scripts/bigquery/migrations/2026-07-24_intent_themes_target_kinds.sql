-- 2026-07-24 — found by the first pass through V_INTENT_REVIEW_QUEUE.
--
-- The highest-spend UNMATCHED "search terms" are not search terms at all. Product-targeting
-- and auto-targeting placements arrive in FACT_AMAZON_ADS.search_term as bare ASINs
-- ('b0by8c82lg'), as 'asin="B0BD1D3J56"', or as '~unattributed'. 7,191 such rows carry
-- $61,832 of 365-day spend — the single largest rule gap in the queue.
--
-- They must NOT receive a keyword-derived occasion intent: nobody typed "b0by8c82lg" hoping
-- for a birthday gift. But they are real advertising with real economics, so dropping them
-- would hide the money. They get their own themes instead, at priority 1 so they always win,
-- and the CVR curve then prices product targeting as its own intent — which is what it is.
--
-- Also fixes stationery: the pattern was 'stationer|\bpens?\b|notebook', which misses
-- "stationary", by far the more common shopper spelling ("stationary for girls", 923 clicks).
--
-- SOP: docs/superpowers/specs/2026-07-24-intent-coverage-phase0-design.md

DELETE FROM `onyga-482313.OI.DE_INTENT_THEMES`
WHERE intent_key IN ('asin-target', 'auto-target');

INSERT INTO `onyga-482313.OI.DE_INTENT_THEMES`
  (intent_key, label, intent_type, match_ads_regex, cross_family, is_active, priority, notes,
   created_at, updated_at)
VALUES
  ('asin-target', 'ASIN Target', 'GENERIC',
   r'^b0[a-z0-9]{8}$|^asin="?b0[a-z0-9]{8}"?$',
   FALSE, TRUE, 1,
   'Product-targeting placement, not a shopper query. Priority 1 so it always wins before any keyword theme can misread an ASIN string. 7,147 bare-ASIN + 43 asin= rows, $61,266 of 365d spend at creation.',
   CURRENT_TIMESTAMP(), CURRENT_TIMESTAMP()),

  ('auto-target', 'Auto Target', 'GENERIC',
   r'^~|^(loose-match|close-match|complements|substitutes|category=)',
   FALSE, TRUE, 1,
   'Amazon auto-targeting bucket (~unattributed, close-match, complements…). Same reasoning as asin-target: real spend, but no shopper intent to read from the string.',
   CURRENT_TIMESTAMP(), CURRENT_TIMESTAMP());

-- Misspelling fix. "stationary" outspends "stationery" in this account.
UPDATE `onyga-482313.OI.DE_INTENT_THEMES`
SET match_ads_regex = r'stationer|station[ae]ry|\bpens?\b|notebook',
    notes = CONCAT(IFNULL(notes, ''), ' | 2026-07-24: added station[ae]ry — "stationary for girls" (923 clicks) was unmatched.'),
    updated_at = CURRENT_TIMESTAMP()
WHERE intent_key = 'stationery';
