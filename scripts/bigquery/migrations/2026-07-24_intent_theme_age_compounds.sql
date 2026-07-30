-- Age-compound themes had no match_ads_regex, so V_ADS_SEARCH_TERM_INTENT
-- (WHERE match_ads_regex IS NOT NULL) skipped them entirely. Give each the same
-- occasion pattern its age-blind parent already uses, plus the gift pattern.
UPDATE `onyga-482313.OI.DE_INTENT_THEMES`
SET match_ads_regex = r'birthday|\bbday\b',
    match_keyword_regex = r'\b(gifts?|presents?|regalos?)\b',
    updated_at = CURRENT_TIMESTAMP()
WHERE match_age_group IS NOT NULL AND match_occasion = 'Birthday';

UPDATE `onyga-482313.OI.DE_INTENT_THEMES`
SET match_ads_regex = r'christmas|xmas|stocking stuffer|advent calendar|\bsanta\b',
    match_keyword_regex = r'\b(gifts?|presents?|regalos?)\b',
    updated_at = CURRENT_TIMESTAMP()
WHERE match_age_group IS NOT NULL AND match_holiday = 'Christmas';

UPDATE `onyga-482313.OI.DE_INTENT_THEMES`
SET match_ads_regex = r'easter',
    match_keyword_regex = r'\b(gifts?|presents?|regalos?)\b',
    updated_at = CURRENT_TIMESTAMP()
WHERE match_age_group IS NOT NULL AND match_holiday = 'Easter';

UPDATE `onyga-482313.OI.DE_INTENT_THEMES`
SET match_ads_regex = r"mother'?s day|\bmom\b",
    match_keyword_regex = r'\b(gifts?|presents?|regalos?)\b',
    updated_at = CURRENT_TIMESTAMP()
WHERE match_age_group IS NOT NULL AND match_holiday = 'Mothers Day';

UPDATE `onyga-482313.OI.DE_INTENT_THEMES`
SET match_ads_regex = r'valentine|galentine',
    match_keyword_regex = r'\b(gifts?|presents?|regalos?)\b',
    updated_at = CURRENT_TIMESTAMP()
WHERE match_age_group IS NOT NULL AND match_holiday = 'Valentines';

-- Bare age-qualified gift themes: gift pattern only, age carried by match_ads_age_regex.
UPDATE `onyga-482313.OI.DE_INTENT_THEMES`
SET match_ads_regex = r'\b(gifts?|presents?|regalos?)\b',
    match_keyword_regex = r'\b(gifts?|presents?|regalos?)\b',
    updated_at = CURRENT_TIMESTAMP()
WHERE intent_key IN ('kid-gift', 'tween-gift', 'teen-gift', 'age-8-14-gift');

-- The priority=6 demotion of the 8-14 bucket was meant for the OCCASION compounds
-- (age-8-14-birthday-gift vs tween-birthday-gift, both specificity 3). Applied to the bare
-- age-8-14-gift it made priority 6 beat tween-gift/teen-gift at 39, so "13 year old girl gifts"
-- resolved to the 8-14 catch-all instead of Teen. Park it just below the named bands.
UPDATE `onyga-482313.OI.DE_INTENT_THEMES`
SET priority = 40, updated_at = CURRENT_TIMESTAMP()
WHERE intent_key = 'age-8-14-gift';
