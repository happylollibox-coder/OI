-- =============================================
-- V_ADS_SEARCH_TERM_FACETS
-- Intent as a COMPOSITION of orthogonal facets, for every search term that has run in ads.
-- Grain: one row per distinct FACT_AMAZON_ADS.search_term.
--
-- WHY THIS REPLACES THE SINGLE-THEME MODEL
-- V_ADS_SEARCH_TERM_INTENT picks ONE winning theme per term by specificity then priority.
-- That forces a choice between facts that are all true at once. "gifts for girls 8-12 deals"
-- is a tween query AND a gift query AND a deal-seeker query; the winner-takes-all model had to
-- discard two of the three. It also could not express "cheap birthday gifts for a 10 year old"
-- at all — tween-birthday-gift won on specificity and the price signal, the single strongest
-- CVR predictor in the account, was silently dropped.
--
-- Facets are read from the shopper's own words and kept side by side:
--   gender / age_group / occasion / holiday  FN_EXTRACT_SEGMENTS — the canonical extractor,
--                                            shared with the Research page. Do not duplicate
--                                            its regexes; DE_INTENT_THEMES.match_ads_age_regex
--                                            does, and should converge onto this.
--   product_type                             DE_PRODUCT_TYPE_KEYWORDS (priority, then longest
--                                            keyword, then product_type/keyword alphabetically)
--                                            — same join V_RESEARCH_RANKED uses.
--   budget_tier / price_ceiling              FN_EXTRACT_BUDGET. NOT the same as
--                                            FACT_RESEARCH_RANKED.price_bucket, which is OUR
--                                            price vs the market. This is what the CUSTOMER
--                                            said: DEAL_SEEKER (1.47% CVR, 0.90 GP-ROAS)
--                                            vs no budget language (3.99%, 1.33).
--   is_gift                                  gift/present/regalo — the single most common
--                                            qualifier, worth its own boolean.
--
-- term_kind separates queries from placements. Product- and auto-targeting arrive in
-- search_term as bare ASINs or '~unattributed'; nobody typed them, so no facet applies and
-- reading intent from the string would be fiction.
--
-- intent_key is a DERIVED slug, not a stored choice — budget, age, occasion/holiday,
-- product_type, gift, in that fixed order. It exists so the composition is legible and
-- joinable; the facets are the truth and downstream should prefer them.
--
-- Dependencies: FACT_AMAZON_ADS, FN_EXTRACT_SEGMENTS, FN_EXTRACT_BUDGET,
--               DE_PRODUCT_TYPE_KEYWORDS, DE_INTENT_THEMES
-- SOP: docs/superpowers/specs/2026-07-24-intent-coverage-phase0-design.md
-- Project: onyga-482313 / Dataset: OI
-- =============================================

CREATE OR REPLACE VIEW `onyga-482313.OI.V_ADS_SEARCH_TERM_FACETS` AS

WITH terms AS (
  SELECT DISTINCT search_term, LOWER(search_term) AS term_lc
  FROM `onyga-482313.OI.FACT_AMAZON_ADS`
  WHERE search_term IS NOT NULL AND search_term != ''
),

-- Placement vs query, and own-brand vs rival. Read from DE_INTENT_THEMES so the patterns stay
-- in one editable place rather than being re-typed here.
kinds AS (
  SELECT intent_key, match_ads_regex
  FROM `onyga-482313.OI.DE_INTENT_THEMES`
  WHERE is_active AND intent_key IN ('asin-target', 'auto-target', 'brand', 'competitor')
),

term_kind AS (
  SELECT t.search_term,
    COALESCE(MAX(CASE
      WHEN k.intent_key = 'asin-target' AND REGEXP_CONTAINS(t.term_lc, k.match_ads_regex) THEN 'ASIN_TARGET'
      WHEN k.intent_key = 'auto-target' AND REGEXP_CONTAINS(t.term_lc, k.match_ads_regex) THEN 'AUTO_TARGET'
      WHEN k.intent_key = 'brand'       AND REGEXP_CONTAINS(t.term_lc, k.match_ads_regex) THEN 'BRAND'
      WHEN k.intent_key = 'competitor'  AND REGEXP_CONTAINS(t.term_lc, k.match_ads_regex) THEN 'COMPETITOR'
    END), 'KEYWORD') AS term_kind
  FROM terms t
  LEFT JOIN kinds k ON TRUE
  GROUP BY t.search_term
),

-- Same join V_RESEARCH_RANKED uses: lowest priority wins, longest keyword breaks the tie.
--
-- The alphabetical tail is NOT cosmetic. (priority, LENGTH(keyword)) is not a total order:
-- DE_PRODUCT_TYPE_KEYWORDS has 44 (priority, length) groups spanning more than one
-- product_type, and 858 real search terms match >=2 of them tied. Without a final tiebreak
-- ARRAY_AGG picked arbitrarily and the winner could change between runs — product_type feeds
-- intent_key, so V_INTENT_CVR_CURVE was observed returning 10,440 then 10,441 product x intent
-- cells on back-to-back runs, i.e. a bid appearing and vanishing with no change in ads data.
-- Same defect class as the ANY_VALUE pairing bug fixed in v27.46: any pick-one aggregate needs
-- an ordering that cannot tie. Alphabetical is arbitrary-but-stable; the real cure for those 44
-- groups is priority hygiene in DE_PRODUCT_TYPE_KEYWORDS, which this does not attempt.
ptype AS (
  SELECT t.search_term,
    ARRAY_AGG(ptk.product_type ORDER BY ptk.priority ASC, LENGTH(ptk.keyword) DESC, ptk.product_type ASC, ptk.keyword ASC LIMIT 1)[OFFSET(0)] AS product_type
  FROM terms t
  CROSS JOIN `onyga-482313.OI.DE_PRODUCT_TYPE_KEYWORDS` ptk
  WHERE REGEXP_CONTAINS(t.term_lc, CONCAT(r'(?:^|\W)', ptk.keyword, r'(?:\W|$)'))
  GROUP BY t.search_term
),

facets AS (
  SELECT
    t.search_term,
    tk.term_kind,
    -- Only PLACEMENTS get no facets — there is no shopper and no words to read. BRAND and
    -- COMPETITOR are still real queries typed by real people: "happy lolli journal for girls"
    -- is brand AND journal AND girls, and gating those out would discard the facets of the
    -- highest-converting traffic in the account (brand runs 10.73% CVR).
    IF(tk.term_kind NOT IN ('ASIN_TARGET', 'AUTO_TARGET'), `onyga-482313`.OI.FN_EXTRACT_SEGMENTS(t.search_term).gender,     NULL) AS gender,
    IF(tk.term_kind NOT IN ('ASIN_TARGET', 'AUTO_TARGET'), `onyga-482313`.OI.FN_EXTRACT_SEGMENTS(t.search_term).age_group,  NULL) AS age_group,
    IF(tk.term_kind NOT IN ('ASIN_TARGET', 'AUTO_TARGET'), `onyga-482313`.OI.FN_EXTRACT_SEGMENTS(t.search_term).occasion,   NULL) AS occasion,
    IF(tk.term_kind NOT IN ('ASIN_TARGET', 'AUTO_TARGET'), `onyga-482313`.OI.FN_EXTRACT_SEGMENTS(t.search_term).holiday,    NULL) AS holiday,
    IF(tk.term_kind NOT IN ('ASIN_TARGET', 'AUTO_TARGET'), p.product_type, NULL)                                                  AS product_type,
    IF(tk.term_kind NOT IN ('ASIN_TARGET', 'AUTO_TARGET'), `onyga-482313`.OI.FN_EXTRACT_BUDGET(t.search_term).budget_tier,   NULL) AS budget_tier,
    IF(tk.term_kind NOT IN ('ASIN_TARGET', 'AUTO_TARGET'), `onyga-482313`.OI.FN_EXTRACT_BUDGET(t.search_term).price_ceiling, NULL) AS price_ceiling,
    IF(tk.term_kind NOT IN ('ASIN_TARGET', 'AUTO_TARGET'),
       REGEXP_CONTAINS(t.term_lc, r'\b(gifts?|presents?|regalos?)\b'), FALSE)                            AS is_gift
  FROM terms t
  JOIN term_kind tk ON tk.search_term = t.search_term
  LEFT JOIN ptype p ON p.search_term = t.search_term
)

SELECT
  f.search_term,
  f.term_kind,
  NULLIF(f.gender, '')       AS gender,
  NULLIF(f.age_group, '')    AS age_group,
  NULLIF(f.occasion, '')     AS occasion,
  NULLIF(f.holiday, '')      AS holiday,
  f.product_type,
  f.budget_tier,
  f.price_ceiling,
  f.is_gift,

  -- Derived composite. Fixed order so the same facet set always yields the same slug.
  CASE
    WHEN f.term_kind != 'KEYWORD' THEN LOWER(f.term_kind)
    -- ARRAY_TO_STRING skips NULL elements but NOT empty strings, so absent facets must be
    -- NULL or the slug fills with '--' gaps.
    ELSE NULLIF(ARRAY_TO_STRING([
      LOWER(f.budget_tier),
      -- Gender belongs in the slug: Ori 2026-07-24 on "gifts for teen girls" — the intent is
      -- teen GIRL gifts, and who it is for is as much a part of the intent as how old they are.
      CASE f.age_group
        WHEN '5-7 (Kid)'     THEN 'kid'
        WHEN '8-12 (Tween)'  THEN 'tween'
        WHEN '13-17 (Teen)'  THEN 'teen'
        WHEN '8-14'          THEN 'age8-14'
        WHEN '18+ (Adult)'   THEN 'adult'
        WHEN '0-2 (Baby)'    THEN 'baby'
        WHEN '2-4 (Toddler)' THEN 'toddler'
        ELSE NULL END,
      -- Gender belongs in the slug: Ori 2026-07-24 on "gifts for teen girls" — the intent is
      -- teen GIRL gifts. Who it is for is as much a part of the intent as how old they are.
      CASE f.gender WHEN 'Female' THEN 'girl' WHEN 'Male' THEN 'boy' ELSE NULL END,
      LOWER(REPLACE(NULLIF(f.holiday, ''), ' ', '-')),
      LOWER(REPLACE(NULLIF(f.occasion, ''), ' ', '-')),
      LOWER(REPLACE(REPLACE(NULLIF(f.product_type, ''), ' & ', '-'), ' ', '-')),
      IF(f.is_gift, 'gift', NULL)
    ], '-'), '')
  END AS intent_key,

  -- How many facets the term actually carries. The honest replacement for the old
  -- specificity tie-break: more facets = a more precisely understood shopper, and it is a
  -- readable confidence signal rather than an artefact of rule ordering.
  (IF(NULLIF(f.gender, '')     IS NOT NULL, 1, 0)
 + IF(NULLIF(f.age_group, '')  IS NOT NULL, 1, 0)
 + IF(NULLIF(f.occasion, '')   IS NOT NULL, 1, 0)
 + IF(NULLIF(f.holiday, '')    IS NOT NULL, 1, 0)
 + IF(f.product_type           IS NOT NULL, 1, 0)
 + IF(f.budget_tier            IS NOT NULL, 1, 0)
 + IF(f.is_gift, 1, 0))       AS facet_count
FROM facets f;
