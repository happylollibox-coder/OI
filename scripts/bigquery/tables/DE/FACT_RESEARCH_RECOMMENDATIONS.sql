-- FACT_RESEARCH_RECOMMENDATIONS
-- Weekly net-new keyword recommendations per family × type (rate-limited to 5 new
-- per type/family/week). Written by SP_REFRESH_RESEARCH_RECOMMENDATIONS; read by the
-- Research page and the coacher. SOP: architecture/RESEARCH_PAGE.md
CREATE TABLE IF NOT EXISTS `onyga-482313.OI.FACT_RESEARCH_RECOMMENDATIONS` (
  rec_id STRING NOT NULL,          -- TO_HEX(MD5(parent_name|rec_type|keyword)) — stable identity
  week_start DATE NOT NULL,        -- ISO Monday first emitted
  parent_name STRING NOT NULL,
  rec_type STRING NOT NULL,        -- EXACT | PHRASE | BROAD | BRAND
  match_type STRING NOT NULL,      -- EXACT | PHRASE | BROAD
  keyword STRING NOT NULL,         -- suggested keyword (seed term)
  query_text STRING NOT NULL,      -- source term
  rank FLOAT64,
  overall_fit FLOAT64,
  market_sales INT64,              -- cluster sales (BROAD) or term market purchases
  market_volume INT64,             -- weekly_market_impressions (BRAND ordering/display)
  coverage_count INT64,            -- PHRASE reach (NULL otherwise)
  cluster_size INT64,              -- BROAD cluster size (NULL otherwise)
  status STRING NOT NULL,          -- NEW | ADVERTISED | DISMISSED
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP()
);
