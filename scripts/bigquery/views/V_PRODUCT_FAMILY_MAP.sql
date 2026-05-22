-- =============================================
-- OI Database Project - V_PRODUCT_FAMILY_MAP
-- =============================================
--
-- Purpose: Single source of truth for product family mapping (asin → family) and UI color mapping
-- Used by: Cube schema (WeeklyTrends, MonthlyTrends, WeeklyTrendsByAsin, MonthlyTrendsByAsin, Summary)
-- Project: onyga-482313
-- Dataset: OI
--
-- =============================================

CREATE OR REPLACE VIEW `onyga-482313.OI.V_PRODUCT_FAMILY_MAP` AS
WITH base AS (
  SELECT
    asin,
    COALESCE(parent_name, product_short_name) AS family,
    product_short_name
  FROM `onyga-482313.OI.DIM_PRODUCT`
  WHERE asin IS NOT NULL AND asin != 'UNKNOWN' AND is_active = TRUE AND oi_is_active = TRUE
),
extracted_colors AS (
  SELECT 
    b.*,
    -- Extract known color keywords from product name
    -- e.g. "Fresh in Pink" -> "Pink", "Pink Lollibox" -> "Pink"
    -- For Bunny variants like "Cheer Bunny" -> "Cheer"
    COALESCE(
      REGEXP_EXTRACT(b.product_short_name, r'(?i)(Pink|Blue|Purple|Mint|Beige|White|Truth)'),
      REGEXP_EXTRACT(b.product_short_name, r'^(\w+)\s')
    ) AS extracted_prod_color,
    REGEXP_EXTRACT(b.family, r'(?i)(Bottle|Fresh|Lollibox|LolliME|Bunny|Truth)') AS extracted_fam_color
  FROM base b
)
SELECT
  e.asin,
  e.family,
  e.product_short_name,
  COALESCE(c1.color_hex, c2.color_hex, '#666666') AS product_color_hex,
  COALESCE(c2.color_hex, '#666666') AS family_color_hex
FROM extracted_colors e
LEFT JOIN `onyga-482313.OI.DE_COLOR_MAP` c1 ON LOWER(e.extracted_prod_color) = LOWER(c1.color_name)
LEFT JOIN `onyga-482313.OI.DE_COLOR_MAP` c2 ON LOWER(e.extracted_fam_color) = LOWER(c2.color_name);
