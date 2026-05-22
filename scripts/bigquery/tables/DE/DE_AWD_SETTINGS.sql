-- DE_AWD_SETTINGS: Stores manually approved AWD auto-replenishment targets
CREATE TABLE IF NOT EXISTS `onyga-482313.OI.DE_AWD_SETTINGS` (
  asin STRING NOT NULL,
  approved_min_units INT64,
  approved_max_units INT64,
  approved_at TIMESTAMP,
  approved_by STRING
)
OPTIONS (description = 'Manually approved AWD auto-replenishment targets per ASIN');
