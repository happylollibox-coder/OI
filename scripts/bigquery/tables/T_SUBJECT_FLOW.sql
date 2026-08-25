-- =============================================================================================
-- T_SUBJECT_FLOW — every forecastable subject and the TEN nested flows it belongs to.
-- v27.150 (2026-08-25). §2.0.2 / §2.0.3, forecast chain step 0.
--
-- TEN LEVELS, GENERIC TO DETAILED (Ori, 2026-08-25): "flow should have 10 levels between 1 level
-- (generic) and 10 levels (detailed)... 1 level should return a generic result to any keyword."
-- Every subject belongs to a flow at EVERY level it has the facets for. Level 1 matches everything,
-- so no subject is ever without an answer.
--
-- THE LADDER IS ORDERED BY COVERAGE, NOT BY INTEREST. Measured on the 849 live subjects before it
-- was fixed: channel / subject_kind / intent_type / family / term_kind are present on 100 %,
-- is_gift on 378 (44.5 %), age_group on 300 (35 %), gender on 291 (34 %), product_type on 121
-- (14 %) — and budget_tier on 7 and holiday on 6, which is why neither is in the ladder at all. A
-- level placed above its coverage would strand most subjects at a depth they cannot reach.
--
-- A SUBJECT STOPS WHERE ITS FACETS STOP. If a keyword has no age_group, it simply has no level 8+;
-- that is not a failure, it is the honest depth of what is known about it. Which level is actually
-- USED is decided by evidence and accuracy, in V_CUSTOMER_PURCHASE_FLOW / the choice view — not here.
--
-- REBUILT, NEVER ACCUMULATED. A derived lookup, not a record of what was said (cf. violation 6).
-- =============================================================================================
CREATE OR REPLACE TABLE `onyga-482313.OI.T_SUBJECT_FLOW`
OPTIONS (description = "Every forecastable subject and the TEN nested customer purchase flows it belongs to (THREE_LAYERS.md §2.0.2/§2.0.3, forecast chain step 0). Level 1 is universal and matches any keyword, so no subject is ever without a flow; each level adds one dimension. THE LADDER IS ORDERED BY COVERAGE rather than by interest, measured on the 849 live subjects: channel/subject_kind/intent_type/family/term_kind are present on 100%, is_gift on 44.5%, age_group on 35%, gender on 34%, product_type on 14% — budget_tier (7 subjects) and holiday (6) are excluded entirely because a level above its coverage strands most subjects at a depth they cannot reach. A subject STOPS where its facets stop, which is the honest depth of what is known about it rather than a failure. Which level is actually USED is decided by evidence and accuracy downstream, never here. MATERIALISED because V_INTENT_RESOLVED classifies ~350k terms and is CPU-heavy: joining it on LOWER(TRIM(...)) inside the flow view and again inside its acceptance exceeded the on-demand CPU limit (42,184 CPU seconds against a 37,300 ceiling on 146 MB). Rebuilt from source, never accumulated. Read by V_CUSTOMER_PURCHASE_FLOW.")
AS
WITH base AS (
  SELECT
    CAST(s.campaign_id AS STRING) AS campaign_id,
    CAST(s.keyword_id AS STRING)  AS keyword_id,
    LOWER(TRIM(s.target_text))    AS target_text,
    COALESCE(s.family, 'UNMAPPED') AS family,
    UPPER(COALESCE(s.channel, 'SP')) AS channel,
    CASE
      WHEN s.is_pt                        THEN 'PRODUCT_TARGET'
      WHEN s.is_auto                      THEN 'AUTO_CLAUSE'
      WHEN UPPER(s.match_type) = 'EXACT'  THEN 'EXACT_KEYWORD'
      WHEN UPPER(s.match_type) = 'PHRASE' THEN 'PHRASE_KEYWORD'
      WHEN UPPER(s.match_type) = 'BROAD'  THEN 'BROAD_KEYWORD'
      ELSE 'OTHER'
    END AS subject_kind,
    COALESCE(i.intent_type, 'UNSPECIFIED') AS intent_type,
    COALESCE(i.term_kind,   'UNSPECIFIED') AS term_kind,
    i.is_gift, i.age_group, i.gender, i.product_type
  FROM `onyga-482313.OI.FACT_KEYWORD_STATE` s
  LEFT JOIN (
    SELECT LOWER(TRIM(search_term)) AS t,
           ANY_VALUE(intent_type) AS intent_type, ANY_VALUE(term_kind) AS term_kind,
           ANY_VALUE(is_gift) AS is_gift, ANY_VALUE(age_group) AS age_group,
           ANY_VALUE(gender) AS gender, ANY_VALUE(product_type) AS product_type
    FROM `onyga-482313.OI.V_INTENT_RESOLVED`
    WHERE LOWER(TRIM(search_term)) IN (
      SELECT DISTINCT LOWER(TRIM(target_text)) FROM `onyga-482313.OI.FACT_KEYWORD_STATE`)
    GROUP BY 1
  ) i ON i.t = LOWER(TRIM(s.target_text))
)
SELECT
  campaign_id, keyword_id, target_text, family, channel, subject_kind, intent_type, term_kind,
  is_gift, age_group, gender, product_type,
  -- THE LADDER. Each level is the one above it plus one dimension, so the flows nest exactly and a
  -- member of a level-7 flow is necessarily a member of its level-6 parent.
  [
    STRUCT(1  AS level, 'ALL' AS flow_key, 'every subject' AS adds),
    STRUCT(2, FORMAT('%s', channel), 'channel'),
    STRUCT(3, FORMAT('%s|%s', channel, subject_kind), 'subject kind'),
    STRUCT(4, FORMAT('%s|%s|%s', channel, subject_kind, intent_type), 'intent type'),
    STRUCT(5, FORMAT('%s|%s|%s|%s', channel, subject_kind, intent_type, family), 'family'),
    STRUCT(6, FORMAT('%s|%s|%s|%s|%s', channel, subject_kind, intent_type, family, term_kind), 'term kind'),
    STRUCT(7, IF(is_gift IS NULL, NULL,
             FORMAT('%s|%s|%s|%s|%s|gift=%t', channel, subject_kind, intent_type, family, term_kind, is_gift)), 'is gift'),
    STRUCT(8, IF(is_gift IS NULL OR age_group IS NULL, NULL,
             FORMAT('%s|%s|%s|%s|%s|gift=%t|%s', channel, subject_kind, intent_type, family, term_kind, is_gift, age_group)), 'age group'),
    STRUCT(9, IF(is_gift IS NULL OR age_group IS NULL OR gender IS NULL, NULL,
             FORMAT('%s|%s|%s|%s|%s|gift=%t|%s|%s', channel, subject_kind, intent_type, family, term_kind, is_gift, age_group, gender)), 'gender'),
    STRUCT(10, IF(is_gift IS NULL OR age_group IS NULL OR gender IS NULL OR product_type IS NULL, NULL,
             FORMAT('%s|%s|%s|%s|%s|gift=%t|%s|%s|%s', channel, subject_kind, intent_type, family, term_kind, is_gift, age_group, gender, product_type)), 'product type')
  ] AS flow_ladder,
  CURRENT_TIMESTAMP() AS built_at
FROM base;
