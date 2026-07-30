-- 2026-07-25 — Phase 0.2 of the intent campaign grid: band boundaries as threshold rows.
-- Spec: docs/superpowers/specs/2026-07-25-intent-campaign-grid-design.md §3.
-- Bands: RUN >= PROFITABLE_ROAS (1.1, existing row) / VELOCITY 0.7-1.1 / MARGINAL 0.5-0.7
-- (OFF unless PROBE) / OFF < 0.5. None hard-coded.

DELETE FROM `onyga-482313.OI.DE_COACH_THRESHOLDS`
WHERE strategy_id = 'INTENT'
  AND threshold_key IN ('VELOCITY_ROAS', 'INTENT_HOPELESS_ROAS', 'VELOCITY_PACE_PCT');

INSERT INTO `onyga-482313.OI.DE_COACH_THRESHOLDS`
  (threshold_key, strategy_id, threshold_value, description, peak_multiplier,
   boost_peak_multiplier, source, updated_at, updated_by, coach_mode)
VALUES
  ('VELOCITY_ROAS', 'INTENT', 0.7,
   "Lower bound of the VELOCITY band. Between here and PROFITABLE_ROAS a cell runs ONLY while its product is below velocity pace (badge/plan floor), at max CPC = value/0.7. Mirrors the SEASONAL_PUSH floor - Ori accepts 0.7 pre-peak for the same strategic reason.",
   1.0, 1.0, 'SEED', CURRENT_DATETIME(), 'claude-grid-p0', 'GUARDIAN'),

  ('INTENT_HOPELESS_ROAS', 'INTENT', 0.5,
   "Unconditional OFF below this - velocity never justifies dead traffic. 0.5-0.7 is the MARGINAL band: OFF unless the cell is in a PROBE window (launch traverses this zone). Matches the account-wide HOPELESS kill line.",
   1.0, 1.0, 'SEED', CURRENT_DATETIME(), 'claude-grid-p0', 'GUARDIAN'),

  ('VELOCITY_PACE_PCT', 'INTENT', 0.85,
   "Velocity floor = GREATEST(badge tier held last month, plan units x this). 0.85 = defend 85% of planned pace before marginal cells may pause.",
   1.0, 1.0, 'SEED', CURRENT_DATETIME(), 'claude-grid-p0', 'GUARDIAN');
