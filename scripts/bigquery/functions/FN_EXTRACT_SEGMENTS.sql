-- =============================================
-- FN_EXTRACT_SEGMENTS
-- =============================================
-- Single source of truth for search-term segment extraction
-- (gender, age_group, occasion, holiday).
--
-- Consumed by: V_SQP_QUERY_WEEKLY, V_RESEARCH_RANKED (ads-only terms),
--              SP_DERIVE_PRODUCT_SEGMENTS, /api/research/segment-reasoning.
--
-- NOT here by design:
--   product_type → DE_PRODUCT_TYPE_KEYWORDS lookup join
--   brand        → needs DIM_PRODUCT (table refs don't belong in a scalar UDF)
--
-- Regexes are the canonical set (formerly V_SQP_QUERY_WEEKLY lines 52-101),
-- including the `girls → 8-14` default. Edit ONLY here.
-- SOP: architecture/RESEARCH_PAGE.md
-- =============================================
CREATE OR REPLACE FUNCTION `onyga-482313`.OI.FN_EXTRACT_SEGMENTS(query_text STRING)
RETURNS STRUCT<gender STRING, age_group STRING, occasion STRING, holiday STRING>
AS (STRUCT(
  -- gender
  CASE
    WHEN REGEXP_CONTAINS(LOWER(query_text), r'\b(girl|girls|daughter|her|women|woman|granddaughter|niece|sister|female)\b') THEN 'Female'
    WHEN REGEXP_CONTAINS(LOWER(query_text), r'\b(boy|boys|son|him|men|man|grandson|nephew|brother|male)\b') THEN 'Male'
    ELSE NULL
  END,
  -- age_group (order matters: specific ranges before generic kid words)
  CASE
    WHEN REGEXP_CONTAINS(LOWER(query_text), r'\b(baby|infant|newborn)\b') THEN '0-2 (Baby)'
    WHEN REGEXP_CONTAINS(LOWER(query_text), r'\b(toddler)\b') THEN '2-4 (Toddler)'
    WHEN REGEXP_CONTAINS(LOWER(query_text), r'(\b1[0-2]\s*(?:year|yr|yo|th|old|\+)|1[0-2]-1[0-4]|\b[89]-1[0-2]\b|\b10-1[0-3]\b|\b8-12\b|\b9-12\b|\b10-12\b|\b10-13\b|\btween\b|\btweens\b|\bpreteen\b|\bages?\s*1[0-2]\b|gift.{0,15}\b1[0-2]\b|\b1[0-2]\b.{0,5}girl|\b1[0-2]\b.{0,5}boy)') THEN '10-12 (Tween)'
    WHEN REGEXP_CONTAINS(LOWER(query_text), r'(\b1[3-7]\s*(?:year|yr|yo|th|old|\+)|1[3-7]-1[4-9]|\bteen\b|\bteens\b|\bteenage\b|\bteenager\b|\bteenagers\b|\bages?\s*1[3-7]\b|\bsweet 16\b|\bsweet sixteen\b|\bquinceanera\b)') THEN '13-17 (Teen)'
    WHEN REGEXP_CONTAINS(LOWER(query_text), r'(\b18\s*(?:year|yr|th|old|\+)|\badult\b|\bwomen\b|\bwoman\b|\bmen\b|\bman\b|\bcollege\b|\bfor her\b|\bfor him\b|\bmom\b|\bdad\b|\bwife\b|\bhusband\b|\bgirlfriend\b|\bboyfriend\b|\bmadre\b|\bmama\b|\bpapa\b)') THEN '18+ (Adult)'
    WHEN REGEXP_CONTAINS(LOWER(query_text), r'(\b[3-9]\s*(?:year|yr|yo|th|old|\+)|\b[3-9]-[5-9]\b|\b[5-9]-1[0-2]\b|\bages?\s*[3-9]\b|\bkid\b|\bkids\b|\bchild\b|\bchildren\b)') THEN '5-9 (Kid)'
    WHEN REGEXP_CONTAINS(LOWER(query_text), r'\bgirls?\b') THEN '8-14'
    ELSE NULL
  END,
  -- occasion (year-round reasons)
  CASE
    WHEN REGEXP_CONTAINS(LOWER(query_text), r'(birthday|bday)') THEN 'Birthday'
    WHEN REGEXP_CONTAINS(LOWER(query_text), r'(graduat)') THEN 'Graduation'
    WHEN REGEXP_CONTAINS(LOWER(query_text), r'(back to school|first day of school)') THEN 'Back to School'
    WHEN REGEXP_CONTAINS(LOWER(query_text), r'(recital|cheerleader|competition|dance )') THEN 'Performance'
    WHEN REGEXP_CONTAINS(LOWER(query_text), r'(get well|hospital|surgery)') THEN 'Get Well'
    WHEN REGEXP_CONTAINS(LOWER(query_text), r'(encouragement|cheer up|comfort|thinking of you)') THEN 'Encouragement'
    WHEN REGEXP_CONTAINS(LOWER(query_text), r'(wedding|bride|bridal)') THEN 'Wedding'
    WHEN REGEXP_CONTAINS(LOWER(query_text), r'(sleepover|slumber party|pajama party|pj party)') THEN 'Sleepover'
    WHEN REGEXP_CONTAINS(LOWER(query_text), r'(\bcamp\b|sleep away camp|summer camp)') THEN 'Camp'
    WHEN REGEXP_CONTAINS(LOWER(query_text), r'(sweet 16|sweet sixteen)') THEN 'Sweet 16'
    ELSE NULL
  END,
  -- holiday (seasonal; rank = 0 when out of window)
  CASE
    WHEN REGEXP_CONTAINS(LOWER(query_text), r'(christmas|xmas|stocking stuffer|advent|\bholiday\b|hanukkah|chanukah)') THEN 'Christmas'
    WHEN REGEXP_CONTAINS(LOWER(query_text), r'(easter)') THEN 'Easter'
    WHEN REGEXP_CONTAINS(LOWER(query_text), r'(valentine)') THEN 'Valentines'
    WHEN REGEXP_CONTAINS(LOWER(query_text), r'(halloween|trick or treat)') THEN 'Halloween'
    WHEN REGEXP_CONTAINS(LOWER(query_text), r'(new year|nye\b)') THEN 'New Years'
    WHEN REGEXP_CONTAINS(LOWER(query_text), r'(mother.?s?.?day|mothers day|for mom|for mama)') THEN 'Mothers Day'
    WHEN REGEXP_CONTAINS(LOWER(query_text), r'(father.s day|for dad|for papa)') THEN 'Fathers Day'
    ELSE NULL
  END
));
