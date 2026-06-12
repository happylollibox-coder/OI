-- Decision-card weekly $ target, graded by V_PPC_ACTION_OUTCOMES (owner ask 2026-06-12).
ALTER TABLE `onyga-482313.OI.FACT_PPC_CHANGE_LOG`
  ADD COLUMN IF NOT EXISTS expected_impact_weekly FLOAT64,
  ADD COLUMN IF NOT EXISTS expected_impact_kind STRING;
