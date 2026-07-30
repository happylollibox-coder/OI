-- =============================================
-- V_INTENT_REVIEW_QUEUE
-- What to review next, hardest-money-first. Grain: one row per search_term needing attention.
--
-- 201,139 distinct ads search terms exist and 42,445 are needed to cover 80% of clicks, so
-- reviewing everything is not the goal — covering the money is. 1,662 terms cover 50%.
-- The queue is ordered by 365-day spend so an hour of review settles as much money as possible.
--
-- review_reason, in priority order:
--   RECHECK        a rule edit changed the machine's mind about something already settled.
--                  Always first: it means a human decision and the current rules disagree.
--   UNMATCHED      real spend, no theme matched at all. Each one is a rule gap.
--   AMBIGUOUS      more than one theme matched. The winner was chosen by specificity then
--                  priority — worth confirming that tie-break was right.
--   HIGH_SPEND     unambiguous single match, but enough money rides on it to be worth a look.
--   ROUTINE        everything else still pending.
--
-- Only terms with real spend appear. A term with two clicks and no orders is not worth a
-- human minute; it stays PENDING and rides on the machine suggestion, which is fine.
--
-- Dependencies: DE_SEARCH_TERM_INTENT, DE_INTENT_THEMES
-- SOP: docs/superpowers/specs/2026-07-24-intent-coverage-phase0-design.md
-- Project: onyga-482313 / Dataset: OI
-- =============================================

CREATE OR REPLACE VIEW `onyga-482313.OI.V_INTENT_REVIEW_QUEUE` AS

WITH candidates AS (
  SELECT
    d.search_term,
    d.suggested_intent_key,
    d.candidate_theme_count,
    d.suggested_specificity,
    d.verification_status,
    d.verified_intent_key,
    d.suggestion_at_verification,
    d.clicks_365d,
    d.orders_365d,
    d.cost_365d,
    ROUND(SAFE_DIVIDE(d.orders_365d, d.clicks_365d) * 100, 2) AS cvr_pct
  FROM `onyga-482313.OI.DE_SEARCH_TERM_INTENT` d
  WHERE d.verification_status IN ('PENDING', 'RECHECK')
    AND d.clicks_365d >= 5
    -- Product- and auto-targeting placements are matched deterministically from the string
    -- shape, not interpreted. There is no judgement for a reviewer to add, and at $61k of
    -- spend they would otherwise sit permanently at the top of the queue.
    AND IFNULL(d.suggested_intent_key, '') NOT IN ('asin-target', 'auto-target')
)
SELECT
  search_term,
  CASE
    WHEN verification_status = 'RECHECK'          THEN 'RECHECK'
    WHEN suggested_intent_key IS NULL             THEN 'UNMATCHED'
    WHEN candidate_theme_count > 1                THEN 'AMBIGUOUS'
    WHEN cost_365d >= 20                          THEN 'HIGH_SPEND'
    ELSE 'ROUTINE'
  END AS review_reason,
  suggested_intent_key,
  verified_intent_key,
  suggestion_at_verification,
  candidate_theme_count,
  suggested_specificity,
  clicks_365d,
  orders_365d,
  ROUND(cost_365d, 2) AS cost_365d,
  cvr_pct,
  verification_status,
  ROW_NUMBER() OVER (
    ORDER BY
      CASE
        WHEN verification_status = 'RECHECK' THEN 1
        WHEN suggested_intent_key IS NULL    THEN 2
        WHEN candidate_theme_count > 1       THEN 3
        ELSE 4
      END,
      cost_365d DESC, clicks_365d DESC, search_term
  ) AS queue_position
FROM candidates;
