-- 2026-08-31 — Task 3 of the intent CVR index registry: the phase index's own shrink prior.
--
-- WHY A SECOND PRIOR RATHER THAN REUSING THE SEASON ONE. A prior belongs to a GRAIN, not to a
-- system. INTENT_CVR_SEASON_PRIOR_CLICKS = 4038 was derived in Task 2 for intent_type x month,
-- where a cell holds 100k+ clicks and the median is 7,163. V_INTENT_IDX_SEASON_PHASE keys on
-- intent_key x phase, measured at 99 cells with p25 13, median 123, max 15,465 — a grain 33x
-- smaller. Applied there, 4038 swamped every cell: easter's real 4.0x PEAK/BOOST swing arrived
-- as 1.85x and the published index was 76.6% flat inside [0.95,1.05], which is the same inertness
-- as the hardcoded season_index this project exists to replace. Reusing another index's constant
-- is the same class of error as the k_season = 500 defect that started all of this.
--
-- Re-runnable: DELETE/INSERT.
-- Spec: docs/superpowers/specs/2026-08-31-intent-cvr-index-registry-design.md section 4.5
--       (AMENDMENT 2026-08-31, Error 2).

DELETE FROM `onyga-482313.OI.DE_COACH_THRESHOLDS`
WHERE strategy_id = 'INTENT' AND threshold_key = 'INTENT_PHASE_PRIOR_CLICKS';

-- coach_mode = GUARDIAN and product_family = NULL are load-bearing, not decorative: thresholds
-- resolve strategy_id+coach_mode -> GLOBAL+coach_mode -> strategy_id+GUARDIAN -> GLOBAL+GUARDIAN
-- (see DE_COACH_THRESHOLDS.sql and the four-way join in V_ADS_COACH). A row written under the
-- wrong mode is invisible to the view's params CTE, which then resolves NULL, nulls every
-- phase_index and empties the whole index.
INSERT INTO `onyga-482313.OI.DE_COACH_THRESHOLDS`
  (threshold_key, strategy_id, threshold_value, description, peak_multiplier,
   boost_peak_multiplier, source, updated_at, updated_by, coach_mode)
VALUES
  ('INTENT_PHASE_PRIOR_CLICKS', 'INTENT', 123.0,
   'Beta-binomial prior strength k for V_INTENT_IDX_SEASON_PHASE only, at the intent_key x phase grain. GRAIN-SPECIFIC BY DESIGN — do not substitute INTENT_CVR_SEASON_PRIOR_CLICKS (4038), which belongs to the 33x larger intent_type x month grain and flattens this one to inertness. Set to the MEDIAN cell size of this grain (99 cells: p25 13, median 123, max 15,465), NOT to the p25 rule used for the season prior: p25 here is 13, too little shrinkage for a 13-click cell to be believed. Thin cells do not need this prior to protect them because INTENT_IDX_MIN_SUPPORT = 100 already pins any cell under 100 support clicks to neutral in the shadow curve, so the prior only has to handle the middle of the distribution and the median does that.',
   1.0, 1.0, 'SEED', CURRENT_DATETIME(), 'claude-intent-registry', 'GUARDIAN');

-- ---------------------------------------------------------------------------------------------
-- ALSO RECORDED HERE: the Task 2 re-derivation of the SEASON prior, 500 -> 4038.
-- Task 2 changed this value in BigQuery but landed no migration for it (commit 6594da0 touched
-- only config.yaml, the view and the acceptance file), and the Task 1 migration's closing comment
-- still says the value is "deliberately left at its current 500 here". Replaying the repo's
-- migrations onto a fresh dataset would therefore rebuild V_INTENT_IDX_SEASON_MONTH against 500 —
-- the exact defect Task 2 existed to fix — while acceptance R02b, which pins only the base prior
-- and the calibration, stayed green. This UPDATE is a no-op against the live table today; it is
-- here so the repo can reproduce the state it describes.
UPDATE `onyga-482313.OI.DE_COACH_THRESHOLDS`
SET threshold_value = 4038.0,
    description = 'Beta-binomial prior strength k for V_INTENT_IDX_SEASON_MONTH, at the intent_type x month grain. Re-derived 2026-08-31 from 500 to the 25th percentile of measured pooled cell size, 4038, so three quarters of cells are driven mainly by their own evidence. At 500 the index was applied at intent_key x month where only 0.9% of 45,168 cells cleared it and 85.3% of published values sat inside [0.95,1.05]. NOT the prior for V_INTENT_IDX_SEASON_PHASE — that grain has its own, INTENT_PHASE_PRIOR_CLICKS.',
    updated_at = CURRENT_DATETIME(),
    updated_by = 'claude-intent-registry'
WHERE strategy_id = 'INTENT' AND coach_mode = 'GUARDIAN'
  AND threshold_key = 'INTENT_CVR_SEASON_PRIOR_CLICKS';
