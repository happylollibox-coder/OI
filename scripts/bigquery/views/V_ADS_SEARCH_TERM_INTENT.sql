-- =============================================
-- V_ADS_SEARCH_TERM_INTENT
-- Intent theme for every search term that has actually run in ads.
-- Grain: one row per distinct FACT_AMAZON_ADS.search_term.
--
-- WHY THIS EXISTS
-- V_INTENT_KEYWORDS resolves themes over FACT_RESEARCH_RANKED.query_text — the research/SQP
-- universe. FACT_AMAZON_ADS has 201,054 distinct search terms and only 6.8% of them exist
-- there; just 11.1% of ads clicks carry a real occasion. The terms that fall through are not
-- noise, they are the long tail that converts: LolliME back-to-school Aug 1 - Sep 28 2025,
-- tagged terms ran 2.22% CVR / $0.20 GP per click while untagged school terms ran 4.53% /
-- $0.72 — better than the account average. This view classifies from the words the shopper
-- typed, so nothing is invisible just because it never reached SQP.
--
-- MATCH RULE (DE_INTENT_THEMES.match_ads_regex, added 2026-07-24)
--   match_ads_regex must match LOWER(search_term), AND match_keyword_regex must also match
--   when it is non-null and different. Themes with a NULL match_ads_regex never match here —
--   attribute-only themes (match_product_type etc.) cannot be resolved from raw text.
--
-- SPECIFICITY ROUTING — one term gets exactly ONE theme, same principle as V_INTENT_KEYWORDS.
--   ads_specificity = 1, +1 when match_keyword_regex adds a second independent condition.
--   So christmas-gift (christmas AND gift) outranks both christmas and gift.
--   Ties break on priority ASC, then intent_key, so back-to-school (10) beats
--   journal-diary (30) for "school journal for girl".
--
-- Dependencies: FACT_AMAZON_ADS, DE_INTENT_THEMES
-- SOP: docs/superpowers/specs/2026-07-24-intent-coverage-phase0-design.md
-- Project: onyga-482313 / Dataset: OI
-- =============================================

CREATE OR REPLACE VIEW `onyga-482313.OI.V_ADS_SEARCH_TERM_INTENT` AS

WITH terms AS (
  SELECT DISTINCT search_term, LOWER(search_term) AS term_lc
  FROM `onyga-482313.OI.FACT_AMAZON_ADS`
  WHERE search_term IS NOT NULL AND search_term != ''
),

themes AS (
  SELECT
    intent_key, label, intent_type, holiday_name, priority,
    match_ads_regex, match_keyword_regex, match_ads_age_regex,
    1 + IF(match_keyword_regex IS NOT NULL
           AND match_keyword_regex != match_ads_regex, 1, 0)
      + IF(match_ads_age_regex IS NOT NULL, 1, 0) AS ads_specificity
  FROM `onyga-482313.OI.DE_INTENT_THEMES`
  WHERE is_active AND match_ads_regex IS NOT NULL
),

matched AS (
  SELECT
    t.search_term,
    th.intent_key, th.label, th.intent_type, th.holiday_name,
    th.priority, th.ads_specificity,
    ROW_NUMBER() OVER (
      PARTITION BY t.search_term
      ORDER BY th.ads_specificity DESC, th.priority ASC, th.intent_key ASC
    ) AS rn,
    COUNT(*) OVER (PARTITION BY t.search_term) AS match_count
  FROM terms t
  JOIN themes th
    ON REGEXP_CONTAINS(t.term_lc, th.match_ads_regex)
   AND (th.match_keyword_regex IS NULL
        OR th.match_keyword_regex = th.match_ads_regex
        OR REGEXP_CONTAINS(t.term_lc, th.match_keyword_regex))
   -- Age is the third independent condition. It is what lets tween-birthday-gift
   -- (birthday AND gift AND tween age = specificity 3) beat birthday-gift (2) on merit
   -- rather than on a priority tie-break.
   AND (th.match_ads_age_regex IS NULL
        OR REGEXP_CONTAINS(t.term_lc, th.match_ads_age_regex))
)

SELECT
  t.search_term,
  m.intent_key,
  m.label            AS intent_label,
  m.intent_type,
  m.holiday_name,
  m.ads_specificity,
  m.priority         AS matched_priority,
  COALESCE(m.match_count, 0) AS candidate_theme_count,
  m.intent_key IS NULL AS is_unclassified
FROM terms t
LEFT JOIN matched m
  ON m.search_term = t.search_term AND m.rn = 1;
