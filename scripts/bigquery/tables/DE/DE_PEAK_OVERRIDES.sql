-- =============================================
-- DE_PEAK_OVERRIDES — manual peak-relevance overrides
-- Forces a family into (or out of) BLITZ for a specific holiday when V_PEAK_RELEVANCE
-- cannot measure lift — e.g. a family that launched INTO the only completed occurrence
-- of that peak, so its launch ramp is indistinguishable from seasonal lift and the
-- 90-day pre-peak maturity gate drops it.
--
-- Consumed by V_ADS_COACH.family_holiday_relevance (UNION on force_relevant = TRUE).
-- holiday_name MUST match DIM_US_HOLIDAYS.holiday_name exactly (e.g. 'Prime Day').
-- This is a JUDGMENT override (no measured baseline) — BLITZ then runs on default
-- aggression with no historical peak anchor. Remove the row once the peak is over or
-- once the family has a clean prior-year baseline (it then qualifies automatically).
--
-- CREATE IF NOT EXISTS: never wipe user-entered overrides on redeploy.
-- =============================================
CREATE TABLE IF NOT EXISTS `onyga-482313.OI.DE_PEAK_OVERRIDES`
(
  family STRING NOT NULL,          -- parent_name / family (matched case-insensitively downstream)
  holiday_name STRING NOT NULL,    -- must equal DIM_US_HOLIDAYS.holiday_name, e.g. 'Prime Day'
  force_relevant BOOL NOT NULL,    -- TRUE → force into BLITZ; FALSE → reserved for force-exclude
  reason STRING,                   -- why this override exists
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP(),
  created_by STRING
);
