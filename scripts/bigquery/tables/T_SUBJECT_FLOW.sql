-- =============================================================================================
-- T_SUBJECT_FLOW — one row per forecastable subject and the customer purchase flow it belongs to.
-- v27.149 (2026-08-25). §2.0.2, forecast chain step 0.
--
-- WHY A TABLE AND NOT A JOIN. V_INTENT_RESOLVED resolves ~350,000 search terms and is CPU-heavy
-- (cheap in bytes, expensive in work — it parses and classifies text). Joining it on
-- LOWER(TRIM(...)) = LOWER(TRIM(...)) defeats every join optimisation, and doing that once inside
-- the flow view and again inside the flow's acceptance suite blew the on-demand CPU limit outright:
-- 42,184 CPU seconds against a 37,300 ceiling, on 146 MB of data.
--
-- Only ~850 subjects need the answer. Resolving them once into a small table makes both the view and
-- its acceptance cheap, and it is the house idiom for an expensive view (the T_ tables).
--
-- REBUILT, NOT ACCUMULATED. This is a derived lookup, not a record of what was said — every row can
-- be recomputed from source at any time, so CREATE OR REPLACE is correct here and carries none of
-- the memory hazard that made violation 6. Nothing is lost by rebuilding it.
-- =============================================================================================
CREATE OR REPLACE TABLE `onyga-482313.OI.T_SUBJECT_FLOW`
OPTIONS (description = "One row per forecastable subject with the customer purchase flow it belongs to (§2.0.2). Membership is DECLARED from fields with full coverage — channel x subject_kind — refined by the supervised intent where it exists; V_INTENT_RESOLVED covers ~44% of subjects, so intent refines a flow and can never define one, or over half of all subjects would belong to nothing. Materialised because V_INTENT_RESOLVED is CPU-heavy over 350k terms and joining it on function-wrapped keys twice exceeded the on-demand CPU limit. Rebuilt from source, never accumulated: this is a derived lookup and not a record of what was said. Read by V_CUSTOMER_PURCHASE_FLOW. Spec: docs/superpowers/specs/2026-08-25-catalog-forecast-chain-design.md.")
AS
SELECT
  CAST(s.campaign_id AS STRING) AS campaign_id,
  CAST(s.keyword_id AS STRING)  AS keyword_id,
  LOWER(TRIM(s.target_text))    AS target_text,
  s.family,
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
  FORMAT('%s|%s|%s',
         UPPER(COALESCE(s.channel, 'SP')),
         CASE
           WHEN s.is_pt                        THEN 'PRODUCT_TARGET'
           WHEN s.is_auto                      THEN 'AUTO_CLAUSE'
           WHEN UPPER(s.match_type) = 'EXACT'  THEN 'EXACT_KEYWORD'
           WHEN UPPER(s.match_type) = 'PHRASE' THEN 'PHRASE_KEYWORD'
           WHEN UPPER(s.match_type) = 'BROAD'  THEN 'BROAD_KEYWORD'
           ELSE 'OTHER'
         END,
         COALESCE(i.intent_type, 'UNSPECIFIED')) AS flow_key,
  CURRENT_TIMESTAMP() AS built_at
FROM `onyga-482313.OI.FACT_KEYWORD_STATE` s
LEFT JOIN (
  -- resolved ONCE, and only for terms this account actually advertises
  SELECT LOWER(TRIM(search_term)) AS t, ANY_VALUE(intent_type) AS intent_type,
         ANY_VALUE(term_kind) AS term_kind
  FROM `onyga-482313.OI.V_INTENT_RESOLVED`
  WHERE LOWER(TRIM(search_term)) IN (
    SELECT DISTINCT LOWER(TRIM(target_text)) FROM `onyga-482313.OI.FACT_KEYWORD_STATE`)
  GROUP BY 1
) i ON i.t = LOWER(TRIM(s.target_text));
