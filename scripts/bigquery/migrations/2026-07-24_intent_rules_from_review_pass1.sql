-- 2026-07-24 — rule fixes found by review pass 1 over V_INTENT_REVIEW_QUEUE (top 30 by spend).
--
-- Reviewing thirty terms one by one produced seven systematic gaps rather than thirty verdicts.
-- That is the supervision loop working: a repeated miss is a rule bug, and fixing the rule is
-- both cheaper and more durable than recording the same judgement thirty times.
--
--   diaries for girls (403 clicks)      -> 'journal|diary' does not match the plural "diaries"
--   scrapbook kit + 4 variants (1,990)  -> crafts-diy missed scrapbook entirely
--   truth or dare + 2 variants (761)    -> your own game product, no social-game pattern existed
--   presents for N year old (1,676)     -> gift matched only \bgifts?\b, never "presents"
--   toys for 11 year old girls (348)    -> toys theme had no ads pattern at all
--   happy lolli (1,100, 10.73% CVR)     -> brand traffic, unidentifiable, no brand theme
--   tween/teen/girl "stuff" (~8,000)    -> audience-only browse terms with 0.0-3.3% CVR
--
-- SOP: docs/superpowers/specs/2026-07-24-intent-coverage-phase0-design.md

-- ---- widen existing patterns ------------------------------------------------
UPDATE `onyga-482313.OI.DE_INTENT_THEMES`
SET match_ads_regex = r'journal|diar(y|ies)',
    notes = CONCAT(IFNULL(notes,''), ' | 2026-07-24 review: "diaries" (plural) was unmatched, 403 clicks.'),
    updated_at = CURRENT_TIMESTAMP()
WHERE intent_key = 'journal-diary';

UPDATE `onyga-482313.OI.DE_INTENT_THEMES`
SET match_ads_regex = r'\bcraft|\bdiy\b|scrapbook',
    notes = CONCAT(IFNULL(notes,''), ' | 2026-07-24 review: scrapbook terms unmatched, ~1,990 clicks.'),
    updated_at = CURRENT_TIMESTAMP()
WHERE intent_key = 'crafts-diy';

-- "presents" is how a large share of gift shoppers phrase it. Matching only "gift" lost them.
UPDATE `onyga-482313.OI.DE_INTENT_THEMES`
SET match_ads_regex = r'\b(gifts?|presents?)\b',
    match_keyword_regex = r'\b(gifts?|presents?)\b',
    notes = CONCAT(IFNULL(notes,''), ' | 2026-07-24 review: added presents?, ~1,676 clicks were unmatched. match_keyword_regex widened in step so the -gift compounds inherit it.'),
    updated_at = CURRENT_TIMESTAMP()
WHERE intent_key = 'gift';

UPDATE `onyga-482313.OI.DE_INTENT_THEMES`
SET match_keyword_regex = r'\b(gifts?|presents?)\b', updated_at = CURRENT_TIMESTAMP()
WHERE match_keyword_regex = r'\bgifts?\b';

UPDATE `onyga-482313.OI.DE_INTENT_THEMES`
SET match_ads_regex = r'\btoys?\b',
    notes = CONCAT(IFNULL(notes,''), ' | 2026-07-24 review: toys had no ads pattern.'),
    updated_at = CURRENT_TIMESTAMP()
WHERE intent_key = 'toys';

UPDATE `onyga-482313.OI.DE_INTENT_THEMES`
SET match_ads_regex = r'truth or dare|would you rather|conversation (card|starter)|social game',
    notes = CONCAT(IFNULL(notes,''), ' | 2026-07-24 review: Truth Or Dare is our own Bottle-family game; 761 clicks were unmatched.'),
    updated_at = CURRENT_TIMESTAMP()
WHERE intent_key = 'social-game';

-- ---- two new themes ---------------------------------------------------------
DELETE FROM `onyga-482313.OI.DE_INTENT_THEMES` WHERE intent_key IN ('brand', 'browse-generic');

INSERT INTO `onyga-482313.OI.DE_INTENT_THEMES`
  (intent_key, label, intent_type, match_ads_regex, cross_family, is_active, priority, notes,
   created_at, updated_at)
VALUES
  -- Priority 2 (just under the target kinds): brand traffic must be identified before any
  -- occasion theme claims it. "happy lolli" converts at 10.73%, the best rate in the queue,
  -- and it belongs to Brand Defense — not to a generic intent that would bid it like cold
  -- traffic. Mirrors the DIM_BRAND_PHRASES vocabulary.
  ('brand', 'Brand', 'GENERIC',
   r'happy ?lolli|lolli ?(me|box|ball|bunny)|lolli journal|lollie?me|lollimee',
   TRUE, TRUE, 2,
   'Own-brand traffic. Found in review pass 1: "happy lolli" 1,100 clicks / 10.73% CVR sat UNMATCHED. V_INTENT_KEYWORDS anti-joins brand on the research side; this makes it visible on the ads side rather than absent.',
   CURRENT_TIMESTAMP(), CURRENT_TIMESTAMP()),

  -- Priority 90 — dead last, so it only ever claims what nothing else wants. These are
  -- audience-only browse queries ("girl stuff", "things for girls 10-12", "tween"). They are
  -- NOT junk to reject: ~8,000 clicks at 0.0-3.3% CVR is a large, identifiable money pit, and
  -- naming it is what lets V_INTENT_BID_BASE price it near zero and switch it off.
  ('browse-generic', 'Generic Browse', 'GENERIC',
   r'\b(stuff|things|trendy)\b|^(tween|teen|girls?|kids?)s?( girls?)?$|^\d{1,2} year old girls?$|^best (presents?|gifts?)$',
   FALSE, TRUE, 90,
   'Audience-only browse terms with no occasion and no product type. Found in review pass 1 — 13 of the top 30 unmatched terms, ~8,000 clicks, CVR 0.0-3.3%. Deliberately lowest priority.',
   CURRENT_TIMESTAMP(), CURRENT_TIMESTAMP());
