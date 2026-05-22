-- ════════════════════════════════════════════════════════════════════
-- DIM_US_HOLIDAYS_PRODUCT_FAMILY
-- Maps which holidays are relevant for each product family.
-- Only holidays in this table will be used for seasonal ROAS forecasting.
-- ════════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS `onyga-482313.OI.DIM_US_HOLIDAYS_PRODUCT_FAMILY` (
  holiday_name STRING NOT NULL,
  product_family STRING NOT NULL
);
