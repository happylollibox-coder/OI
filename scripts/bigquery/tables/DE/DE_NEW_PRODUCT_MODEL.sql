-- DE_NEW_PRODUCT_MODEL — User-assigned launch model for new products
-- Maps a new product (no/limited history) to an existing product whose
-- first-year sales pattern and seasonality will drive the forecast.
--
-- Used by: V_FORECAST_DEMAND (Phase 1 & Phase 2 forecasting)
--
-- Multiple new products can share the same model_product.
-- Example: all Bunnies follow "Truth Or Dare" pattern.
CREATE TABLE IF NOT EXISTS `onyga-482313.OI.DE_NEW_PRODUCT_MODEL` (
  id              STRING NOT NULL,
  family          STRING NOT NULL,   -- new product's family
  model_product   STRING NOT NULL,   -- existing product whose pattern to follow
  created_at      DATETIME DEFAULT CURRENT_DATETIME(),
  updated_at      DATETIME DEFAULT CURRENT_DATETIME(),
  updated_by      STRING
);
