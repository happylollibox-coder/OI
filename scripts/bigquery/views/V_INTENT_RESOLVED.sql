-- =============================================
-- V_INTENT_RESOLVED
-- THE read model for search-term -> intent. Everything downstream reads this, never
-- DE_SEARCH_TERM_INTENT directly and never the facet/theme views directly.
-- Grain: one row per search_term.
--
-- 2026-07-24 MIGRATED to the facet model. The machine suggestion now comes from
-- V_ADS_SEARCH_TERM_FACETS (intent composed from gender / age / occasion / holiday /
-- product_type / budget / gift) instead of V_ADS_SEARCH_TERM_INTENT (one winning theme).
-- Ori's corrections drove this: age ("should be tween birthday gift"), budget ("deals means
-- cheap"), and gender ("teen girl gifts") were each a facet the winner-takes-all model could
-- not represent, because it had to discard facts that were all simultaneously true.
-- The facets travel alongside the resolved key so downstream can group at whatever grain it
-- needs — the CVR curve can learn "tween-gift, price-sensitive" as distinct from "tween-gift".
--
-- PRECEDENCE — a human decision always beats the machine:
--   REJECTED             -> NULL. The reviewer said this term has no intent, and that is a
--                           decision, not an absence. Distinct from PENDING with no match.
--   VERIFIED / CORRECTED -> verified_intent_key.
--   RECHECK              -> verified_intent_key still wins. The suggestion changed under a
--                           settled decision; until someone re-reviews, the human's last word
--                           stands. is_stale flags it so nobody mistakes it for current.
--   PENDING              -> the composed suggestion. Unreviewed but usable.
--
-- Terms absent from DE_SEARCH_TERM_INTENT (new since the last SP run) fall through to the live
-- composition, so a term is never invisible just because the refresh has not caught up.
--
-- NOTE: facets always describe the TERM, not the verdict. When a human overrides the composed
-- key the facets still report what the words say — the override is visible as a disagreement
-- between intent_key and machine_suggestion rather than by rewriting the evidence.
--
-- Dependencies: V_ADS_SEARCH_TERM_FACETS, DE_SEARCH_TERM_INTENT
-- SOP: docs/superpowers/specs/2026-07-24-intent-coverage-phase0-design.md
-- Project: onyga-482313 / Dataset: OI
-- =============================================

CREATE OR REPLACE VIEW `onyga-482313.OI.V_INTENT_RESOLVED` AS

WITH joined AS (
  SELECT
    live.search_term,
    live.intent_key   AS live_intent_key,
    live.term_kind,
    live.gender, live.age_group, live.occasion, live.holiday,
    live.product_type, live.budget_tier, live.price_ceiling, live.is_gift,
    live.facet_count,
    d.suggested_intent_key,
    d.verified_intent_key,
    d.verification_status,
    d.verified_by,
    d.verified_at,
    d.clicks_365d,
    d.cost_365d
  FROM `onyga-482313.OI.V_ADS_SEARCH_TERM_FACETS` live
  LEFT JOIN `onyga-482313.OI.DE_SEARCH_TERM_INTENT` d
    ON d.search_term = live.search_term
)

SELECT
  j.search_term,
  CASE
    WHEN j.verification_status = 'REJECTED' THEN NULL
    WHEN j.verification_status IN ('VERIFIED', 'CORRECTED', 'RECHECK')
      THEN j.verified_intent_key
    ELSE COALESCE(j.suggested_intent_key, j.live_intent_key)
  END AS intent_key,

  -- The facets: the evidence behind the key, and the grain downstream should prefer.
  j.term_kind,
  j.gender,
  j.age_group,
  j.occasion,
  j.holiday,
  j.product_type,
  j.budget_tier,
  j.price_ceiling,
  j.is_gift,
  j.facet_count,

  -- TIME_BASED is now a property of the holiday facet rather than a theme attribute: a term
  -- carrying a holiday IS seasonal, and its window comes from DIM_US_HOLIDAYS by name.
  IF(j.holiday IS NOT NULL, 'TIME_BASED', 'GENERIC') AS intent_type,
  j.holiday                                          AS holiday_name,

  COALESCE(j.verification_status, 'PENDING')                        AS verification_status,
  COALESCE(j.verification_status IN ('VERIFIED','CORRECTED','REJECTED'), FALSE) AS is_human_verified,
  COALESCE(j.verification_status = 'RECHECK', FALSE)                AS is_stale,
  j.verified_by,
  j.verified_at,

  COALESCE(j.suggested_intent_key, j.live_intent_key)               AS machine_suggestion,
  j.verified_intent_key,
  j.facet_count                                                     AS ads_specificity,
  j.clicks_365d,
  j.cost_365d
FROM joined j;
