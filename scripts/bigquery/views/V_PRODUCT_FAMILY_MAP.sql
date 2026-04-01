-- =============================================
-- OI Database Project - V_PRODUCT_FAMILY_MAP
-- =============================================
--
-- Purpose: Single source of truth for product family mapping (asin → family)
-- Used by: Cube schema (WeeklyTrends, MonthlyTrends, WeeklyTrendsByAsin, MonthlyTrendsByAsin, Summary)
-- Project: onyga-482313
-- Dataset: OI
--
-- =============================================

CREATE OR REPLACE VIEW `onyga-482313.OI.V_PRODUCT_FAMILY_MAP` AS
SELECT
  asin,
  CASE
    WHEN product_short_name LIKE '%Lollibox%' OR product_short_name LIKE '%Lolli Box%' THEN 'Lollibox'
    WHEN product_short_name LIKE '%LolliME%' OR product_short_name LIKE '%Lolli ME%' THEN 'LolliME'
    WHEN product_short_name LIKE '%Fresh%' THEN 'Fresh'
    WHEN product_short_name LIKE '%Truth%' OR product_short_name LIKE '%Bottle%' THEN 'Bottle'
    ELSE product_short_name
  END AS family,
  product_short_name
FROM `onyga-482313.OI.DIM_PRODUCT`
WHERE asin IS NOT NULL AND asin != 'UNKNOWN';
