-- Peak-window evidence columns for the decision cards (owner ask 2026-06-12):
-- the live view computes these; they were never materialized.
ALTER TABLE `onyga-482313.OI.FACT_ADS_COACH_ACTIONS`
  ADD COLUMN IF NOT EXISTS ly_spend FLOAT64,
  ADD COLUMN IF NOT EXISTS ly_clicks INT64,
  ADD COLUMN IF NOT EXISTS ly_cpc FLOAT64,
  ADD COLUMN IF NOT EXISTS q4_peak_spend FLOAT64;
