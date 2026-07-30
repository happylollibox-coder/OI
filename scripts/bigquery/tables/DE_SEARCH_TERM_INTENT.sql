-- DE_SEARCH_TERM_INTENT: the supervised keyword -> intent theme mapping.
--
-- WHY A TABLE AND NOT A VIEW
-- V_ADS_SEARCH_TERM_INTENT recomputes the regex match every time it runs, so a human decision
-- has nowhere to live and any rule edit silently rewrites history. This table persists the
-- machine's SUGGESTION and the human's VERDICT side by side, so the two can disagree and the
-- disagreement is visible.
--
-- THE CONTRACT
--   suggested_*  belongs to the automation. SP_REFRESH_SEARCH_TERM_INTENT overwrites it freely.
--   verified_*   belongs to the reviewer. The SP NEVER overwrites it.
--   When the automation changes its mind about a row that was already verified, the SP does not
--   silently defer to either side — it flips verification_status to RECHECK and leaves both
--   values in place for a human to settle.
--
-- verification_status:
--   PENDING   never reviewed. resolved intent falls back to the suggestion.
--   VERIFIED  reviewed, the suggestion was right.
--   CORRECTED reviewed, the reviewer chose a different intent than suggested.
--   REJECTED  reviewed, this term has NO valid intent (verified_intent_key IS NULL on purpose —
--             distinct from PENDING, where NULL just means nobody has looked).
--   RECHECK   was reviewed, but the suggestion has changed since. Needs a second look.
--
-- Read through V_INTENT_RESOLVED, never directly — it applies the precedence.
-- Review through V_INTENT_REVIEW_QUEUE, which ranks by spend so the biggest money is settled
-- first. 201,139 distinct terms exist and 42,445 are needed to cover 80% of clicks, so full
-- manual review is not the goal; covering the money is.
--
-- SOP: docs/superpowers/specs/2026-07-24-intent-coverage-phase0-design.md
-- Created: 2026-07-24

CREATE TABLE IF NOT EXISTS `onyga-482313.OI.DE_SEARCH_TERM_INTENT` (
  search_term STRING NOT NULL,              -- PK. Raw, as it appears in FACT_AMAZON_ADS.

  -- ---- machine suggestion (SP-owned, freely overwritten) ----
  suggested_intent_key STRING,              -- NULL = no theme matched
  suggested_specificity INT64,              -- how many conditions the winning theme required
  suggested_priority INT64,                 -- winning theme's DE_INTENT_THEMES.priority
  candidate_theme_count INT64,              -- how many themes matched at all; >1 = ambiguous,
                                            -- worth a closer look during review
  suggested_at TIMESTAMP,

  -- ---- human verdict (reviewer-owned, never overwritten by the SP) ----
  verified_intent_key STRING,               -- the decision. NULL + REJECTED = "no intent".
  verification_status STRING NOT NULL,      -- PENDING | VERIFIED | CORRECTED | REJECTED | RECHECK
  verified_by STRING,
  verified_at TIMESTAMP,
  verified_note STRING,                     -- why, when it is not obvious
  suggestion_at_verification STRING,        -- what the machine said at verification time.
                                            -- Drift detection compares this to suggested_intent_key.

  -- ---- impact, for review prioritisation (SP-owned) ----
  clicks_365d INT64,
  orders_365d INT64,
  cost_365d FLOAT64,
  first_seen DATE,
  last_seen DATE,

  created_at TIMESTAMP,
  updated_at TIMESTAMP
)
OPTIONS (
  description = "Supervised search-term -> intent theme mapping. Machine suggestion and human verdict stored side by side; the refresh SP never overwrites verified_*. Read via V_INTENT_RESOLVED, review via V_INTENT_REVIEW_QUEUE."
);
