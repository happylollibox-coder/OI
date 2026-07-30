-- SP_REFRESH_SEARCH_TERM_INTENT
-- Keeps DE_SEARCH_TERM_INTENT in step with the ads term universe and the current rule set,
-- WITHOUT ever destroying a human verdict.
--
-- Three things happen, in this order:
--   1. New terms are inserted as PENDING with the machine's current suggestion.
--   2. Existing rows get refreshed suggestions and impact counters.
--      - PENDING / RECHECK rows: suggestion updated in place.
--      - VERIFIED / CORRECTED / REJECTED rows: suggestion updated, verdict untouched.
--   3. Any VERIFIED or CORRECTED row whose suggestion no longer matches what it was at
--      verification time is flipped to RECHECK. This is the drift alarm: it fires when a
--      DE_INTENT_THEMES rule edit changes the machine's mind about something a human already
--      settled. Nothing is silently overwritten in either direction.
--
-- REJECTED rows are deliberately NOT re-flagged on drift — "this term has no intent" is a
-- statement about the term, not about the rule that happened to match it.
--
-- Idempotent. Safe to run on a schedule.
-- SOP: docs/superpowers/specs/2026-07-24-intent-coverage-phase0-design.md

CREATE OR REPLACE PROCEDURE `onyga-482313.OI.SP_REFRESH_SEARCH_TERM_INTENT`()
OPTIONS (description = "Refresh machine suggestions + impact counters in DE_SEARCH_TERM_INTENT. Never overwrites verified_*; flips drifted VERIFIED/CORRECTED rows to RECHECK.")
BEGIN
  DECLARE inserted_count INT64 DEFAULT 0;
  DECLARE recheck_count INT64 DEFAULT 0;

  -- 2026-07-24: reads V_ADS_SEARCH_TERM_FACETS, not the single-theme view. The suggestion is
  -- now a composed key (budget-age-gender-holiday-occasion-ptype-gift) and suggested_specificity
  -- carries facet_count. suggested_priority / candidate_theme_count belonged to the theme
  -- tie-break and no longer apply — held NULL rather than dropped so verdicts recorded before
  -- the migration keep their history.
  CREATE TEMP TABLE _current AS
  SELECT
    i.search_term,
    i.intent_key            AS suggested_intent_key,
    i.facet_count           AS suggested_specificity,
    CAST(NULL AS INT64)     AS suggested_priority,
    CAST(NULL AS INT64)     AS candidate_theme_count,
    ARRAY_TO_STRING([
      i.budget_tier, i.age_group, i.gender, i.holiday, i.occasion, i.product_type,
      IF(i.is_gift, 'gift', NULL)
    ], ' · ')               AS suggested_facets,
    IFNULL(m.clicks, 0)     AS clicks_365d,
    IFNULL(m.orders, 0)     AS orders_365d,
    IFNULL(m.cost, 0.0)     AS cost_365d,
    m.first_seen,
    m.last_seen
  FROM `onyga-482313.OI.V_ADS_SEARCH_TERM_FACETS` i
  LEFT JOIN (
    SELECT search_term,
      SUM(Ads_clicks) AS clicks, SUM(Ads_orders) AS orders, SUM(Ads_cost) AS cost,
      MIN(date) AS first_seen, MAX(date) AS last_seen
    FROM `onyga-482313.OI.FACT_AMAZON_ADS`
    WHERE date >= DATE_SUB(CURRENT_DATE(), INTERVAL 365 DAY)
    GROUP BY 1
  ) m ON m.search_term = i.search_term;

  -- 1 + 2. Insert new terms, refresh suggestions and impact on existing ones.
  MERGE `onyga-482313.OI.DE_SEARCH_TERM_INTENT` T
  USING _current S
  ON T.search_term = S.search_term
  WHEN MATCHED THEN UPDATE SET
    suggested_intent_key  = S.suggested_intent_key,
    suggested_specificity = S.suggested_specificity,
    suggested_priority    = S.suggested_priority,
    candidate_theme_count = S.candidate_theme_count,
    suggested_facets      = S.suggested_facets,
    suggested_at          = CURRENT_TIMESTAMP(),
    clicks_365d           = S.clicks_365d,
    orders_365d           = S.orders_365d,
    cost_365d             = S.cost_365d,
    first_seen            = LEAST(IFNULL(T.first_seen, S.first_seen), IFNULL(S.first_seen, T.first_seen)),
    last_seen             = S.last_seen,
    updated_at            = CURRENT_TIMESTAMP()
  WHEN NOT MATCHED THEN INSERT (
    search_term, suggested_intent_key, suggested_specificity, suggested_priority,
    candidate_theme_count, suggested_facets, suggested_at, verification_status,
    clicks_365d, orders_365d, cost_365d, first_seen, last_seen, created_at, updated_at
  ) VALUES (
    S.search_term, S.suggested_intent_key, S.suggested_specificity, S.suggested_priority,
    S.candidate_theme_count, S.suggested_facets, CURRENT_TIMESTAMP(), 'PENDING',
    S.clicks_365d, S.orders_365d, S.cost_365d, S.first_seen, S.last_seen,
    CURRENT_TIMESTAMP(), CURRENT_TIMESTAMP()
  );

  SET inserted_count = (
    SELECT COUNT(*) FROM `onyga-482313.OI.DE_SEARCH_TERM_INTENT`
    WHERE verification_status = 'PENDING'
  );

  -- 3. Drift alarm. IS DISTINCT FROM so a NULL on either side counts as a change.
  UPDATE `onyga-482313.OI.DE_SEARCH_TERM_INTENT`
  SET verification_status = 'RECHECK', updated_at = CURRENT_TIMESTAMP()
  WHERE verification_status IN ('VERIFIED', 'CORRECTED')
    AND suggested_intent_key IS DISTINCT FROM suggestion_at_verification;

  SET recheck_count = (
    SELECT COUNT(*) FROM `onyga-482313.OI.DE_SEARCH_TERM_INTENT`
    WHERE verification_status = 'RECHECK'
  );

  -- Phase 0.3 (grid plan 2026-07-25): materialize the intent model. The bid view costs
  -- ~27k CPU-seconds per scan (regex over 337k terms via the facets chain) — one scan here,
  -- then every consumer (popup endpoint, month-plan generator, Tier-A builder) reads the
  -- T_ tables for pennies. Cube also only reads T_ tables by convention.
  CREATE OR REPLACE TABLE `onyga-482313.OI.T_INTENT_CVR_CURVE` AS
  SELECT * FROM `onyga-482313.OI.V_INTENT_CVR_CURVE`;

  CREATE OR REPLACE TABLE `onyga-482313.OI.T_INTENT_BID_BASE` AS
  SELECT * FROM `onyga-482313.OI.V_INTENT_BID_BASE`;

  SELECT FORMAT(
    'SP_REFRESH_SEARCH_TERM_INTENT: %d rows total, %d pending, %d flagged RECHECK, T_INTENT_CVR_CURVE %d rows, T_INTENT_BID_BASE %d rows',
    (SELECT COUNT(*) FROM `onyga-482313.OI.DE_SEARCH_TERM_INTENT`),
    inserted_count, recheck_count,
    (SELECT COUNT(*) FROM `onyga-482313.OI.T_INTENT_CVR_CURVE`),
    (SELECT COUNT(*) FROM `onyga-482313.OI.T_INTENT_BID_BASE`)) AS operation_summary;
END;
