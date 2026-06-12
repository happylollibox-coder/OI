-- DE_SEARCH_TERM_SEGMENTS
-- Manual overrides for search term segmentation
-- Used by the Research page to fix auto-detected segments
CREATE TABLE IF NOT EXISTS `onyga-482313.OI.DE_SEARCH_TERM_SEGMENTS` (
  query_text STRING NOT NULL,
  gender STRING,
  age_group STRING,
  occasion STRING,
  cost_tier STRING,
  product_type STRING,
  brand STRING,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP()
);
