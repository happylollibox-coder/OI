-- =============================================
-- OI Database Project - DIM_BRAND_PHRASES
-- =============================================
--
-- Purpose: Lookup table for brand/product phrase classification.
--          Used by coaches and views to classify search terms as
--          BRAND (pure brand name) or PRODUCT (brand + product).
--
--          Matching logic: start from the longest phrase (max word_count)
--          and work down. First match wins. This ensures "lollime spa kit"
--          (3 words, PRODUCT) matches before "lollime" (1 word, BRAND).
--
-- Grain: One row per phrase
--
-- Project: onyga-482313
-- Dataset: OI
-- =============================================

CREATE OR REPLACE TABLE `onyga-482313.OI.DIM_BRAND_PHRASES` (
  phrase            STRING    NOT NULL,   -- lowercase phrase to match (e.g. 'lollibox', 'lollime spa', 'happy lolli birthday')
  phrase_type       STRING    NOT NULL,   -- 'BRAND' or 'PRODUCT'
  word_count        INT64     NOT NULL,   -- number of words in phrase (for match priority ordering)
  requested_product STRING,               -- mapped product collection/short name if explicit (e.g., 'LolliME', 'Pink Lollibox')
  tag               STRING,               -- ambiguous product attribute (e.g., 'pink', 'spa', 'kit', 'gift')
  occasion          STRING,               -- extracted occasion (e.g., 'BIRTHDAY', 'EASTER')
  created_at        TIMESTAMP DEFAULT CURRENT_TIMESTAMP(),
  updated_at        TIMESTAMP DEFAULT CURRENT_TIMESTAMP()
)
OPTIONS (
  description = "Brand/product phrase lookup. Matching priority: longest phrase first (max word_count). First match wins."
);
