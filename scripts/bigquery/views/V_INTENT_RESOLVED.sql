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

  -- INTENT_TYPE IS A PROPERTY OF THE KEY, NOT OF THE FACETS (fixed 2026-09-01).
  -- It used to read `IF(j.holiday IS NOT NULL, ...)` straight off the facet, which contradicted
  -- the key for every non-KEYWORD term: V_ADS_SEARCH_TERM_FACETS collapses those to
  -- LOWER(term_kind), so "happy lolli christmas gift" and "happy lolli bracelet" BOTH become
  -- intent_key 'brand' — the key throws the holiday away while the type still remembered it.
  -- Result: intent_keys 'brand' and 'competitor' each carried BOTH GENERIC and TIME_BASED, so
  -- every consumer that groups by intent_key and picks one type was picking arbitrarily.
  -- V_INTENT_CVR_CURVE:108 and _SHADOW:204 use ANY_VALUE, which flapped between runs — and in
  -- the SHADOW intent_type is a JOIN KEY into the seasonal month index (:324), not just a label,
  -- so a flipped type selected a different season index. With the type derived from the key,
  -- any pick-one over it is now a no-op. (V_INTENT_INDEX_SCORECARD:140 also guards this with
  -- MIN(), but it reads V_ADS_SEARCH_TERM_INTENT, where intent_type comes from DE_INTENT_THEMES
  -- keyed by intent_key and is 1:1 already — measured 2026-09-01, zero keys carry two types
  -- there. Its comment claiming "the same shape exists here" is not true of its own source; the
  -- MIN is harmless but was never load-bearing.)
  --
  -- term_kind = 'KEYWORD' is exactly the condition under which the key is a COMPOSITE (and so
  -- carries the holiday); every other kind is a collapsed placeholder that cannot be seasonal.
  -- holiday_name is nulled on the same condition so the two columns can never disagree — the
  -- holiday FACET is still emitted above, so no evidence is lost, only the false season lookup.
  --
  -- LIMITATION, deliberate: for a human override (verified_intent_key) this describes the
  -- COMPOSED key, not the typed one. Zero overrides currently differ from the machine
  -- suggestion, so nothing is wrong today. The tempting fix — matching the key text against a
  -- holiday vocabulary — is a trap: DIM_US_HOLIDAYS says 'Valentines Day' where the facets say
  -- 'Valentines', so the slugs do not line up and Valentines keys would silently read GENERIC.
  -- Align those names first if that path is ever taken.
  --
  -- NULL key => NULL type. A REJECTED term has no key, so it has no type to report.
  CASE
    WHEN j.verification_status = 'REJECTED'                     THEN NULL
    WHEN j.holiday IS NOT NULL AND j.term_kind = 'KEYWORD'      THEN 'TIME_BASED'
    ELSE 'GENERIC'
  END AS intent_type,
  IF(j.term_kind = 'KEYWORD', j.holiday, NULL)       AS holiday_name,

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
