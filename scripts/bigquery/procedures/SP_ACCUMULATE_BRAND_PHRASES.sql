-- =============================================
-- OI Database Project - SP_ACCUMULATE_BRAND_PHRASES
-- =============================================
--
-- Purpose: Auto-discovers brand/product phrases from search terms
--          in FACT_AMAZON_ADS. Inserts new phrases not already in
--          DIM_BRAND_PHRASES.
--
--          Classification Logic:
--          - BRAND: term contains a brand root (lolli, happy lolli)
--            BUT does NOT contain any physical product keywords
--            (e.g., 'happy lolli', 'happy lolli birthday').
--          - PRODUCT: term contains ANY product keyword
--            (e.g., 'lollime', 'lollibox', 'spa', 'kit', 'box').
--            Note: 'lollime' and 'lollibox' map directly to PRODUCT.
--
-- Project: onyga-482313
-- Dataset: OI
-- =============================================

CREATE OR REPLACE PROCEDURE `onyga-482313.OI.SP_ACCUMULATE_BRAND_PHRASES`()
BEGIN

  DECLARE brand_roots_arr ARRAY<STRING> DEFAULT ['lolli', 'happylolli', 'happy lolli'];

  -- ═══════════════════════════════════════════
  -- Step 1-5: Find, classify, and insert new brand phrases
  -- ═══════════════════════════════════════════
  INSERT INTO `onyga-482313.OI.DIM_BRAND_PHRASES` (
    phrase, phrase_type, word_count, requested_product, tag, occasion
  )
  WITH
  -- Get unique branded search terms (last 90 days)
  branded_terms AS (
    SELECT DISTINCT LOWER(search_term) as search_term
    FROM `onyga-482313.OI.FACT_AMAZON_ADS`
    WHERE search_term IS NOT NULL AND search_term != ''
      AND date >= DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY)
      -- At least one brand root or brand-product name appears
      AND (
        (SELECT COUNTIF(STRPOS(LOWER(search_term), root) > 0) FROM UNNEST(brand_roots_arr) root) > 0
        OR STRPOS(LOWER(search_term), 'lollime') > 0
        OR STRPOS(LOWER(search_term), 'lollibox') > 0
      )
  ),

  -- Split into words
  term_words AS (
    SELECT
      search_term,
      SPLIT(search_term, ' ') AS words,
      ARRAY_LENGTH(SPLIT(search_term, ' ')) AS wc
    FROM branded_terms
  ),

  -- Generate 1/2/3-grams
  all_ngrams AS (
    -- 1-grams
    SELECT words[SAFE_OFFSET(pos)] AS phrase, 1 AS word_count
    FROM term_words, UNNEST(GENERATE_ARRAY(0, wc - 1)) AS pos
    UNION ALL
    -- 2-grams
    SELECT CONCAT(words[SAFE_OFFSET(pos)], ' ', words[SAFE_OFFSET(pos+1)]), 2
    FROM term_words, UNNEST(GENERATE_ARRAY(0, wc - 2)) AS pos
    WHERE wc >= 2
    UNION ALL
    -- 3-grams
    SELECT CONCAT(words[SAFE_OFFSET(pos)], ' ', words[SAFE_OFFSET(pos+1)], ' ', words[SAFE_OFFSET(pos+2)]), 3
    FROM term_words, UNNEST(GENERATE_ARRAY(0, wc - 3)) AS pos
    WHERE wc >= 3
  ),

  -- Only n-grams containing a brand root or known product brand
  brand_ngrams AS (
    SELECT DISTINCT phrase, word_count
    FROM all_ngrams
    WHERE phrase IS NOT NULL
      AND LENGTH(phrase) > 2
      AND (
        (SELECT COUNTIF(STRPOS(phrase, root) > 0) FROM UNNEST(brand_roots_arr) root) > 0
        OR STRPOS(phrase, 'lollime') > 0
        OR STRPOS(phrase, 'lollibox') > 0
      )
      AND NOT REGEXP_CONTAINS(phrase, r'(lollipop|lollia|lollies)')
  ),

  -- Extract tags and classify
  classified AS (
    SELECT
      ng.phrase,
      ng.word_count,
      -- EXTRACT PRODUCTS: STRICT LOGIC - ONLY KNOWN NAMES AND COLLECTIONS
      CASE
        WHEN REGEXP_CONTAINS(ng.phrase, r'\b(truth|dare|game|cards)\b') THEN 'Truth Or Dare'
        
        -- Box variations (lollibox)
        WHEN REGEXP_CONTAINS(ng.phrase, r'\b(box|boxes|lollibox)\b') AND REGEXP_CONTAINS(ng.phrase, r'\b(pink)\b') THEN 'Pink Lollibox'
        WHEN REGEXP_CONTAINS(ng.phrase, r'\b(box|boxes|lollibox)\b') AND REGEXP_CONTAINS(ng.phrase, r'\b(purple)\b') THEN 'Purple Lollibox'
        WHEN REGEXP_CONTAINS(ng.phrase, r'\b(box|boxes|lollibox)\b') AND REGEXP_CONTAINS(ng.phrase, r'\b(blue)\b') THEN 'Blue Lollibox'
        WHEN REGEXP_CONTAINS(ng.phrase, r'\b(box|boxes|lollibox)\b') AND REGEXP_CONTAINS(ng.phrase, r'\b(white)\b') THEN 'White Lollibox'
        WHEN REGEXP_CONTAINS(ng.phrase, r'\b(box|boxes|lollibox)\b') THEN 'lollibox'
        
        -- Journal variations (LolliME)
        WHEN REGEXP_CONTAINS(ng.phrase, r'\b(lollime|journal|notebook|diary)\b') AND REGEXP_CONTAINS(ng.phrase, r'\b(mint)\b') THEN 'Mint LolliME'
        WHEN REGEXP_CONTAINS(ng.phrase, r'\b(lollime|journal|notebook|diary)\b') AND REGEXP_CONTAINS(ng.phrase, r'\b(pink)\b') THEN 'Pink LolliME'
        WHEN REGEXP_CONTAINS(ng.phrase, r'\b(lollime|journal|notebook|diary)\b') AND REGEXP_CONTAINS(ng.phrase, r'\b(purple)\b') THEN 'Purple LolliME'
        WHEN REGEXP_CONTAINS(ng.phrase, r'\b(lollime|journal|notebook|diary)\b') THEN 'LolliME'
        
        -- Fresh / Shower variations
        WHEN REGEXP_CONTAINS(ng.phrase, r'\b(fresh|shower|bath|power)\b') AND REGEXP_CONTAINS(ng.phrase, r'\b(pink)\b') THEN 'Fresh in Pink'
        WHEN REGEXP_CONTAINS(ng.phrase, r'\b(fresh|shower|bath|power)\b') THEN 'fresh'
        
        ELSE NULL -- Ambiguous descriptors drop to `tag`
      END AS requested_product,

      -- EXTRACT TAG: Ambiguous product attribute markers
      REGEXP_EXTRACT(ng.phrase, r'\b(mint|pink|purple|blue|white|spa|kit|gift|gifts|set)\b') AS tag,
      
      -- EXTRACT OCCASION
      CASE
        WHEN REGEXP_CONTAINS(ng.phrase, r'\b(birthday|bday|b-day)\b') THEN 'BIRTHDAY'
        WHEN REGEXP_CONTAINS(ng.phrase, r'\b(christmas|xmas)\b') THEN 'CHRISTMAS'
        WHEN REGEXP_CONTAINS(ng.phrase, r'\b(easter)\b') THEN 'EASTER'
        WHEN REGEXP_CONTAINS(ng.phrase, r'\b(valentine|vday|valentines)\b') THEN 'VALENTINES'
        WHEN REGEXP_CONTAINS(ng.phrase, r'\b(halloween)\b') THEN 'HALLOWEEN'
        WHEN REGEXP_CONTAINS(ng.phrase, r'\b(mother|mom|mothers)\b') THEN 'MOTHERS_DAY'
        WHEN REGEXP_CONTAINS(ng.phrase, r'\b(father|dad|fathers)\b') THEN 'FATHERS_DAY'
        WHEN REGEXP_CONTAINS(ng.phrase, r'\b(graduation|grad)\b') THEN 'GRADUATION'
        ELSE NULL
      END AS occasion,

      -- Count distinct search terms containing this phrase as a word boundary match
      (SELECT COUNT(DISTINCT bt.search_term)
       FROM branded_terms bt
       WHERE STRPOS(bt.search_term, ng.phrase) > 0
      ) AS term_count
    FROM brand_ngrams ng
  ),

  final_logic AS (
    SELECT
      phrase,
      word_count,
      requested_product,
      tag,
      occasion,
      term_count,
      -- CLASSIFY: If it contains ANY product exact mapping OR any general product tag, it's PRODUCT.
      CASE
        WHEN requested_product IS NOT NULL OR tag IS NOT NULL THEN 'PRODUCT'
        ELSE 'BRAND'
      END AS phrase_type
    FROM classified
  )

  SELECT phrase, phrase_type, word_count, requested_product, tag, occasion
  FROM final_logic
  WHERE term_count >= 2
    AND phrase NOT IN (SELECT phrase FROM `onyga-482313.OI.DIM_BRAND_PHRASES`);

END;
