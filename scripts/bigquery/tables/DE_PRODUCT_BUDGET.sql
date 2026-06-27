-- DE_PRODUCT_BUDGET — per-product weekly spend ceiling (risk envelope). Coacher D.
CREATE TABLE IF NOT EXISTS `onyga-482313.OI.DE_PRODUCT_BUDGET` (
  parent_name    STRING NOT NULL,
  week_start     DATE NOT NULL,
  weekly_budget  FLOAT64,
  source         STRING,          -- MANUAL | BUSINESS_PLAN | BOOTSTRAP
  updated_at     TIMESTAMP,
  updated_by     STRING
);
