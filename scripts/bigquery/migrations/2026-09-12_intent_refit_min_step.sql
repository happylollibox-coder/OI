-- 2026-09-12 — dead-band for the bounded calibration refit (SP_SCORE_INTENT_INDEXES step 4).
--
-- WHY. The refit shipped 2026-09-11 treated a step as UNCHANGED only when the implied value
-- rounded to the current one at four decimals. Every orchestrator run adds a few hours of clicks,
-- so the implied value moved by about 0.0001 per run and the procedure logged APPLIED three times
-- a day for +0.01% moves, rewriting updated_at on the threshold row each time. Observed on the
-- first scheduled run (16:12 UTC, 2026-09-11): APPLIED 1.1717 -> 1.1718, +0.01%. Harmless to the
-- number, ruinous to the record: updated_at stopped meaning "when the constant last moved" and
-- T_INTENT_REFIT_LOG became a list of noise.
--
-- WHAT. A step whose magnitude is below INTENT_CVR_REFIT_MIN_STEP is UNCHANGED: logged, nothing
-- written to the threshold row. The band is a RATIO like INTENT_CVR_REFIT_MAX_STEP: 0.0025 = a
-- quarter of one percent. Chosen as roughly ten runs' worth of ordinary click accumulation, so a
-- genuine week of drift still applies and a day of jitter does not. Not measured against an error
-- criterion; re-derive from T_INTENT_REFIT_LOG once it holds a month of decisions.
--
-- The three bands read together: |step| < MIN_STEP -> UNCHANGED; MIN_STEP <= |step| <= MAX_STEP
-- -> APPLIED; |step| > MAX_STEP -> SUGGESTED.
--
-- Re-runnable: DELETE/INSERT.
-- Spec: docs/superpowers/specs/2026-08-31-intent-cvr-index-registry-design.md section 9.3.

DELETE FROM `onyga-482313.OI.DE_COACH_THRESHOLDS`
WHERE strategy_id = 'INTENT' AND threshold_key = 'INTENT_CVR_REFIT_MIN_STEP';

-- coach_mode = GUARDIAN and product_family = NULL are load-bearing: the procedure reads
-- strategy_id = 'INTENT' AND coach_mode = 'GUARDIAN' AND product_family IS NULL and RAISEs on NULL.
INSERT INTO `onyga-482313.OI.DE_COACH_THRESHOLDS`
  (threshold_key, strategy_id, threshold_value, description, peak_multiplier,
   boost_peak_multiplier, source, updated_at, updated_by, coach_mode)
VALUES
  ('INTENT_CVR_REFIT_MIN_STEP', 'INTENT', 0.0025,
   'Dead-band for the bounded refit of INTENT_CVR_CALIBRATION in SP_SCORE_INTENT_INDEXES step 4: a step with ABS(implied / current - 1) below this is logged UNCHANGED and nothing is written to the threshold row, so updated_at keeps meaning when the constant last moved. A RATIO: 0.0025 = a quarter percent, about ten orchestrator runs of ordinary click accumulation. Reads with INTENT_CVR_REFIT_MAX_STEP (0.10): below MIN -> UNCHANGED, between -> APPLIED, above MAX -> SUGGESTED. Added 2026-09-12 after the first scheduled run applied a +0.01% move.',
   1.0, 1.0, 'SEED', CURRENT_DATETIME(), 'claude-intent-registry', 'GUARDIAN');
