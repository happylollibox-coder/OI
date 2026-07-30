-- DE_COMPETITOR_PRODUCT — competitor ASIN -> product name, so an intent can be derived.
--
-- WHY: Ori wants competitor campaigns split by intent (<=10 ASINs each), and intent is extracted from
-- the competitor PRODUCT NAME. Amazon's ads feeds never return competitor titles — the targeting
-- report gives `asin="B0..."` and nothing else — and DIM_PRODUCT only holds our own catalogue. So the
-- names have to be sourced separately and land here (Ori 2026-07-23).
--
-- DE_ prefix: user/tool-entered, not Fivetran-synced. Populate via tools/fetch_competitor_titles.py,
-- which supports a manual CSV today and a product-data API once credentials exist.
CREATE TABLE IF NOT EXISTS `onyga-482313.OI.DE_COMPETITOR_PRODUCT` (
  asin          STRING NOT NULL,   -- competitor ASIN (upper-case)
  product_name  STRING,            -- title as shown on Amazon; the text intent is derived from
  brand         STRING,
  source        STRING,            -- 'manual' | 'paapi' | 'keepa' | 'rainforest'
  updated_at    TIMESTAMP,
  updated_by    STRING
);
