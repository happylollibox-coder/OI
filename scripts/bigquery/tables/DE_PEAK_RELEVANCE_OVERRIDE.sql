-- DE_PEAK_RELEVANCE_OVERRIDE — manual override of V_PEAK_RELEVANCE.is_relevant_peak per (family, holiday).
-- Forces peak relevance where the data-driven check drops it — e.g. a product whose ads launched near
-- the last-year peak gets excluded by V_PEAK_RELEVANCE's 90-day pre-peak maturity gate, so its real
-- gift-season peak is mislabeled off-season (LolliME/Bottle Christmas). Feeds the OFF/PEAK season split
-- (V_WEEKLY_CELL_NET) and the coach's BLITZ timing.
CREATE TABLE IF NOT EXISTS `onyga-482313.OI.DE_PEAK_RELEVANCE_OVERRIDE` (
  family           STRING NOT NULL,
  holiday_name     STRING NOT NULL,          -- must match DIM_US_HOLIDAYS.holiday_name
  is_relevant_peak BOOL NOT NULL,
  note             STRING,
  updated_at       TIMESTAMP,
  updated_by       STRING
)
OPTIONS (description = 'Manual override of V_PEAK_RELEVANCE.is_relevant_peak per (family, holiday). Injects/overrides so the OFF/PEAK season split recognises peaks the data-driven maturity gate drops.');
