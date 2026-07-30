-- 2026-07-24 — rule fixes from review pass 2 (queue positions 1-26 after pass 1).
--
-- Pass 2 found two whole categories the vocabulary had no word for, plus eight pattern gaps.
--
--   lisa frank, claires (411 clicks)     -> COMPETITOR brands. No theme existed. These are not
--                                           generic browse: someone searching a rival brand is a
--                                           different, and differently-priced, shopper.
--   regalos para niñas, diario para niñas -> Spanish. Every pattern was English-only.
--   preteen / pre teen / girly / teenage girl -> browse-generic missed these spellings
--   skincare, skin care                   -> beauty had no ads pattern
--   surprise box                          -> mystery-box matched only "mystery box"
--   stickers                              -> stationery
--   sketchbook, sketch book               -> journal-diary
--   games for N year old, girls night games -> social-game
--   slime kit                             -> crafts-diy
--   self care kit                         -> mental-wellness
--   084312699x                            -> ISBN. asin-target matched only ^b0........
--
-- SOP: docs/superpowers/specs/2026-07-24-intent-coverage-phase0-design.md

-- ---- new theme: competitor -------------------------------------------------
DELETE FROM `onyga-482313.OI.DE_INTENT_THEMES` WHERE intent_key = 'competitor';

INSERT INTO `onyga-482313.OI.DE_INTENT_THEMES`
  (intent_key, label, intent_type, match_ads_regex, cross_family, is_active, priority, notes,
   created_at, updated_at)
VALUES
  ('competitor', 'Competitor Brand', 'GENERIC',
   r"lisa frank|claire'?s|justice ?(brand|girls)|smiggle|typo shop|american girl|our generation",
   TRUE, TRUE, 3,
   'Rival-brand queries. Priority 3 — after our own brand (2) and the target kinds (1), before every occasion theme, because brand intent overrides topical intent. Found in review pass 2: lisa frank (244 clicks) and claires (167+131) sat UNMATCHED and would otherwise fall into browse-generic and be priced as cold traffic.',
   CURRENT_TIMESTAMP(), CURRENT_TIMESTAMP());

-- ---- widen existing patterns ------------------------------------------------
UPDATE `onyga-482313.OI.DE_INTENT_THEMES` SET
  match_ads_regex = r'\b(stuff|things|trendy|girly)\b|^(pre.?teen|tween|teen(age)?|girls?|kids?)s?( girls?)?$|^\d{1,2} year old girls?$|^best (presents?|gifts?)$|^(items|things) for (pre.?teen|tween|teen)|^girls? \d{1,2}-\d{1,2}$',
  notes = CONCAT(IFNULL(notes,''), ' | 2026-07-24 pass 2: added preteen/pre teen/teenage/girly and "girls 10-12" shapes.'),
  updated_at = CURRENT_TIMESTAMP()
WHERE intent_key = 'browse-generic';

UPDATE `onyga-482313.OI.DE_INTENT_THEMES` SET
  match_ads_regex = r'\bbeauty\b|skin.?care|makeup|nail (polish|kit)|lip ?gloss',
  notes = CONCAT(IFNULL(notes,''), ' | 2026-07-24 pass 2: beauty had no ads pattern; skincare/skin care were unmatched.'),
  updated_at = CURRENT_TIMESTAMP()
WHERE intent_key = 'beauty';

UPDATE `onyga-482313.OI.DE_INTENT_THEMES` SET
  match_ads_regex = r'(mystery|surprise) ?box',
  notes = CONCAT(IFNULL(notes,''), ' | 2026-07-24 pass 2: "surprise box" was unmatched.'),
  updated_at = CURRENT_TIMESTAMP()
WHERE intent_key = 'mystery-box';

UPDATE `onyga-482313.OI.DE_INTENT_THEMES` SET
  match_ads_regex = r'stationer|station[ae]ry|\bpens?\b|notebook|sticker',
  notes = CONCAT(IFNULL(notes,''), ' | 2026-07-24 pass 2: added sticker.'),
  updated_at = CURRENT_TIMESTAMP()
WHERE intent_key = 'stationery';

-- Spanish: diario = diary. Journal is the highest-value intent in the account, so losing its
-- Spanish queries matters more than the click count suggests.
UPDATE `onyga-482313.OI.DE_INTENT_THEMES` SET
  match_ads_regex = r'journal|diar(y|ies)|diario|sketch ?book',
  notes = CONCAT(IFNULL(notes,''), ' | 2026-07-24 pass 2: added sketchbook + Spanish "diario".'),
  updated_at = CURRENT_TIMESTAMP()
WHERE intent_key = 'journal-diary';

-- Spanish: regalo/regalos = gift/gifts.
UPDATE `onyga-482313.OI.DE_INTENT_THEMES` SET
  match_ads_regex = r'\b(gifts?|presents?|regalos?)\b',
  match_keyword_regex = r'\b(gifts?|presents?|regalos?)\b',
  notes = CONCAT(IFNULL(notes,''), ' | 2026-07-24 pass 2: added Spanish "regalo".'),
  updated_at = CURRENT_TIMESTAMP()
WHERE intent_key = 'gift';

UPDATE `onyga-482313.OI.DE_INTENT_THEMES` SET
  match_keyword_regex = r'\b(gifts?|presents?|regalos?)\b', updated_at = CURRENT_TIMESTAMP()
WHERE match_keyword_regex = r'\b(gifts?|presents?)\b';

UPDATE `onyga-482313.OI.DE_INTENT_THEMES` SET
  match_ads_regex = r'truth or dare|would you rather|conversation (card|starter)|social game|girls? night game|\bgames? for\b',
  notes = CONCAT(IFNULL(notes,''), ' | 2026-07-24 pass 2: "games for 10 year old girls" converts at 11.0% and was unmatched.'),
  updated_at = CURRENT_TIMESTAMP()
WHERE intent_key = 'social-game';

UPDATE `onyga-482313.OI.DE_INTENT_THEMES` SET
  match_ads_regex = r'\bcraft|\bdiy\b|scrapbook|slime',
  notes = CONCAT(IFNULL(notes,''), ' | 2026-07-24 pass 2: added slime.'),
  updated_at = CURRENT_TIMESTAMP()
WHERE intent_key = 'crafts-diy';

UPDATE `onyga-482313.OI.DE_INTENT_THEMES` SET
  match_ads_regex = r'self.?care|mindful|wellness|anxiety|affirmation',
  notes = CONCAT(IFNULL(notes,''), ' | 2026-07-24 pass 2: mental-wellness had no ads pattern; "self care kit for teen girls" was unmatched.'),
  updated_at = CURRENT_TIMESTAMP()
WHERE intent_key = 'mental-wellness';

-- ISBNs arrive in the same slot as ASINs and are equally not shopper queries.
UPDATE `onyga-482313.OI.DE_INTENT_THEMES` SET
  match_ads_regex = r'^b0[a-z0-9]{8}$|^asin="?b0[a-z0-9]{8}"?$|^[0-9]{9}[0-9x]$',
  notes = CONCAT(IFNULL(notes,''), ' | 2026-07-24 pass 2: added ISBN-10 shape (084312699x).'),
  updated_at = CURRENT_TIMESTAMP()
WHERE intent_key = 'asin-target';
