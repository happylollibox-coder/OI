-- =============================================================================================
-- T_INTENT_REFIT_LOG — every decision SP_SCORE_INTENT_INDEXES has made about INTENT_CVR_CALIBRATION.
--
-- WHY IT EXISTS. The calibration constant is now moved by a procedure, inside a band
-- (INTENT_CVR_REFIT_MAX_STEP). A constant that moves on its own needs a record a human can read
-- of every time it moved, every time it wanted to and was not allowed to, and every time it could
-- not tell. DE_COACH_THRESHOLDS holds only the current state (threshold_value, suggested_value,
-- suggestion_reason); this table is the history behind it. Acceptance R21 reads it to decide
-- whether an out-of-band drift has been REPORTED, and R22 to prove the refit step actually ran
-- as part of the last scoring.
--
-- ONE ROW PER PROCEDURE RUN, whatever the outcome. The orchestrator runs three times a day, so
-- expect up to three rows a day, most of them UNCHANGED.
--
-- action is one of:
--   APPLIED    threshold_value was moved to implied_value (rounded to 4 dp); step within the band.
--   SUGGESTED  step outside the band; suggested_value / suggestion_reason written on the threshold
--              row, threshold_value NOT touched. A human decides.
--   UNCHANGED  implied_value rounds to the current value; nothing written to the threshold row,
--              so its updated_at keeps meaning "when the constant last moved".
--   SKIPPED    no usable tuning row (shape/k missing from T_INTENT_BASE_TUNING, or fewer than 200
--              predictions); suggestion_reason on the threshold row says why, nothing else moves.
--
-- ACCUMULATES. CREATE TABLE IF NOT EXISTS, never replaced.
--
-- Written by:  SP_SCORE_INTENT_INDEXES step 4
-- Read by:     acceptance R21, R22; humans
-- Migration:   scripts/bigquery/migrations/2026-09-11_intent_refit_max_step.sql (the band)
-- Spec:        docs/superpowers/specs/2026-08-31-intent-cvr-index-registry-design.md section 9
-- Created:     2026-09-11
-- =============================================================================================

CREATE TABLE IF NOT EXISTS `onyga-482313.OI.T_INTENT_REFIT_LOG` (
  refit_at        TIMESTAMP NOT NULL,  -- when the decision was made (UTC)
  shape           STRING    NOT NULL,  -- tuning row read: the shadow curve's recency shape
  k_base          FLOAT64,             -- tuning row read: INTENT_CVR_BASE_PRIOR_CLICKS at the time
  previous_value  FLOAT64,             -- INTENT_CVR_CALIBRATION before this run
  implied_value   FLOAT64,             -- T_INTENT_BASE_TUNING.implied_calibration (NULL if SKIPPED for a missing row)
  new_value       FLOAT64,             -- INTENT_CVR_CALIBRATION after this run (= previous unless APPLIED)
  step_pct        FLOAT64,             -- (implied / previous - 1) * 100, NULL if SKIPPED
  max_step        FLOAT64,             -- INTENT_CVR_REFIT_MAX_STEP at the time, a ratio
  n_predictions   INT64,               -- evidence behind implied_value
  action          STRING    NOT NULL,  -- APPLIED | SUGGESTED | UNCHANGED | SKIPPED
  reason          STRING    NOT NULL   -- the sentence also written to suggestion_reason, or why nothing was
)
OPTIONS (description = "Audit trail of SP_SCORE_INTENT_INDEXES step 4, the bounded refit of INTENT_CVR_CALIBRATION: one row per procedure run with the value before, the tuning view's implied value, the step, the band (INTENT_CVR_REFIT_MAX_STEP) and the action taken -- APPLIED (moved, inside the band), SUGGESTED (outside the band: suggested_value written on the threshold row, threshold_value untouched, a human decides), UNCHANGED (implied rounds to current, nothing written), SKIPPED (no usable tuning row or < 200 predictions). Acceptance R21 reads it to tell reported drift from silent drift; R22 proves the step ran with the last scoring. ACCUMULATES, never replaced. Up to three rows a day from the orchestrator.");
