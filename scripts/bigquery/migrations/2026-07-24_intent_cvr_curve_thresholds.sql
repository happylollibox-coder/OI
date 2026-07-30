-- 2026-07-24 — Phase 1 of the intent-CVR work: tunable knobs for the curve and the base bid.
-- Scope strategy_id = 'INTENT', matching the existing intent thresholds.
-- SOP: docs/superpowers/specs/2026-07-24-intent-coverage-phase0-design.md

DELETE FROM `onyga-482313.OI.DE_COACH_THRESHOLDS`
WHERE strategy_id = 'INTENT'
  AND threshold_key IN ('INTENT_BID_PROFIT_SHARE', 'INTENT_CVR_BASE_PRIOR_CLICKS',
                        'INTENT_CVR_SEASON_PRIOR_CLICKS', 'INTENT_BID_CEILING',
                        'INTENT_BID_FLOOR');

INSERT INTO `onyga-482313.OI.DE_COACH_THRESHOLDS`
  (threshold_key, strategy_id, threshold_value, description, peak_multiplier,
   boost_peak_multiplier, source, updated_at, updated_by, coach_mode)
VALUES
  ('INTENT_BID_PROFIT_SHARE', 'INTENT', 0.70,
   "Share of a click's expected gross margin we are willing to pay. base_bid = cvr_hat x gp_per_order x this. 0.70 banks 30% as profit. 1.0 = bid to breakeven.",
   1.0, 1.0, 'SEED', CURRENT_DATETIME(), 'claude-phase1', 'GUARDIAN'),

  ('INTENT_CVR_BASE_PRIOR_CLICKS', 'INTENT', 200.0,
   "Beta-binomial prior strength k for base CVR. A product x intent cell with 200 clicks sits halfway between its own rate and its family's. Raise to trust thin cells less.",
   1.0, 1.0, 'SEED', CURRENT_DATETIME(), 'claude-phase1', 'GUARDIAN'),

  ('INTENT_CVR_SEASON_PRIOR_CLICKS', 'INTENT', 500.0,
   "Prior strength for the seasonal index. Higher than the base prior on purpose — a month is a strong claim and there are at most 2 observations of each calendar month in the ads history (starts 2024-09-05).",
   1.0, 1.0, 'SEED', CURRENT_DATETIME(), 'claude-phase1', 'GUARDIAN'),

  ('INTENT_BID_CEILING', 'INTENT', 2.00,
   'Hard cap on a computed base bid, matching the GUARDIAN $2 bid ceiling.',
   1.0, 1.0, 'SEED', CURRENT_DATETIME(), 'claude-phase1', 'GUARDIAN'),

  ('INTENT_BID_FLOOR', 'INTENT', 0.15,
   'Below this a computed bid is not worth placing — the intent should be OFF for that month rather than bid down into irrelevance.',
   1.0, 1.0, 'SEED', CURRENT_DATETIME(), 'claude-phase1', 'GUARDIAN');
