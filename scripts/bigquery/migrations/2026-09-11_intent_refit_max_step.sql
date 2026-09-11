-- 2026-09-11 — self-maintenance of the intent CVR index registry: the band inside which
-- SP_SCORE_INTENT_INDEXES may move INTENT_CVR_CALIBRATION on its own.
--
-- WHY A BAND. Spec section 4.4 says the calibration constant "will drift -- the account's CVR
-- and AOV both moved more than 30% this year" and "is a threshold row with a refit query, never
-- a literal in SQL". V_INTENT_BASE_TUNING already publishes implied_calibration (= 1 / bias)
-- for the shipped shape and prior on every run, and ten days after the seed it read 1.1717
-- against a stored 1.151: a 1.8% drift that nothing applied. Left alone, the level error this
-- whole change exists to remove creeps back in one refresh at a time.
--
-- WHY NOT JUST APPLY IT. The tuning grid is walk-forward over ~1,150 predictions, so a small move
-- is measurement and a large move is an event -- a partial month, a broken upstream, a data
-- restatement -- that a human should look at before the catalog reprices every bid off it. So:
-- a step inside the band is APPLIED (threshold_value moves, the log records it); a step outside
-- is SUGGESTED (suggested_value / suggestion_reason are written, threshold_value is NOT touched,
-- the log records it, and acceptance R21 stays green because the drift was reported). Same
-- automation-proposes / human-disposes contract the registry itself uses for is_active.
--
-- WHY 0.10. Ten days of new clicks moved the implied value 1.8%; the 2026-08-31 seed already sat
-- 2.2% under the same view's reading on the day it was seeded (1.1761). A month of ordinary
-- drift is therefore a few percent, and a 10% step is roughly the swing a real regime change
-- produces (the 2026 AOV collapse moved GP-per-order ~35%). Not measured against an error
-- criterion -- there is no history of refits yet to measure against; T_INTENT_REFIT_LOG is that
-- history from today, and this constant is the first thing to re-derive from it.
--
-- Re-runnable: DELETE/INSERT.
-- Spec: docs/superpowers/specs/2026-08-31-intent-cvr-index-registry-design.md section 9.

DELETE FROM `onyga-482313.OI.DE_COACH_THRESHOLDS`
WHERE strategy_id = 'INTENT' AND threshold_key = 'INTENT_CVR_REFIT_MAX_STEP';

-- coach_mode = GUARDIAN and product_family = NULL are load-bearing: SP_SCORE_INTENT_INDEXES reads
-- strategy_id = 'INTENT' AND coach_mode = 'GUARDIAN' AND product_family IS NULL, and a row landing
-- under any other mode resolves NULL there, which the procedure treats as "band unknown" and
-- RAISEs rather than guessing.
INSERT INTO `onyga-482313.OI.DE_COACH_THRESHOLDS`
  (threshold_key, strategy_id, threshold_value, description, peak_multiplier,
   boost_peak_multiplier, source, updated_at, updated_by, coach_mode)
VALUES
  ('INTENT_CVR_REFIT_MAX_STEP', 'INTENT', 0.10,
   'Maximum relative step SP_SCORE_INTENT_INDEXES may apply to INTENT_CVR_CALIBRATION on its own: ABS(implied / current - 1) <= this and the constant is moved (action APPLIED in T_INTENT_REFIT_LOG); above it the new value is written to suggested_value with an OUT OF BAND reason and threshold_value is left for a human (action SUGGESTED). implied comes from T_INTENT_BASE_TUNING for the shipped shape (nested_1_2_3_6_12) at k_base = INTENT_CVR_BASE_PRIOR_CLICKS and needs >= 200 predictions, else SKIPPED. A RATIO, not a percentage: 0.10 = ten percent. Chosen 2026-09-11 as roughly the swing of a real regime change against a few percent of monthly drift; re-derive from T_INTENT_REFIT_LOG once it holds a season of refits.',
   1.0, 1.0, 'SEED', CURRENT_DATETIME(), 'claude-intent-registry', 'GUARDIAN');
