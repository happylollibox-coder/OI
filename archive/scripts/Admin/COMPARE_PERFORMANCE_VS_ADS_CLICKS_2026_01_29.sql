-- =============================================
-- Comparison: STG_AMAZON_PERFORMANCE vs STG_AMAZON_ADS
-- Date: 2026-01-29
-- =============================================
--
-- Purpose: Compare CLICKS from STG_AMAZON_PERFORMANCE (per child_asin) 
--          with clicks from STG_AMAZON_ADS (per most_advertised_asin_clicks)
--
-- =============================================

-- SUMMARY COMPARISON
SELECT 
  'STG_AMAZON_PERFORMANCE' as source,
  COUNT(DISTINCT child_asin) as unique_asins,
  SUM(CLICKS) as total_clicks
FROM `onyga-482313.OI.STG_AMAZON_PERFORMANCE`
WHERE date = '2026-01-29'

UNION ALL

SELECT 
  'STG_AMAZON_ADS (most_advertised_asin_clicks)' as source,
  COUNT(DISTINCT most_advertised_asin_clicks) as unique_asins,
  SUM(clicks) as total_clicks
FROM `onyga-482313.OI.STG_AMAZON_ADS`
WHERE date = '2026-01-29'
  AND most_advertised_asin_clicks IS NOT NULL;

-- =============================================
-- DETAILED COMPARISON BY ASIN
-- =============================================

WITH 
performance_by_asin AS (
  SELECT 
    child_asin,
    SUM(CLICKS) as total_clicks
  FROM `onyga-482313.OI.STG_AMAZON_PERFORMANCE`
  WHERE date = '2026-01-29'
  GROUP BY child_asin
),
ads_by_most_asin AS (
  SELECT 
    most_advertised_asin_clicks AS asin,
    SUM(clicks) as total_clicks
  FROM `onyga-482313.OI.STG_AMAZON_ADS`
  WHERE date = '2026-01-29'
    AND most_advertised_asin_clicks IS NOT NULL
  GROUP BY most_advertised_asin_clicks
)
SELECT 
  COALESCE(p.child_asin, a.asin) AS asin,
  p.total_clicks AS performance_clicks,
  a.total_clicks AS ads_clicks,
  COALESCE(p.total_clicks, 0) - COALESCE(a.total_clicks, 0) AS clicks_difference,
  CASE 
    WHEN p.child_asin IS NULL THEN 'Ads Only' 
    WHEN a.asin IS NULL THEN 'Performance Only'
    ELSE 'Both' 
  END AS data_source,
  CASE 
    WHEN a.total_clicks > 0 
    THEN ROUND(p.total_clicks * 100.0 / NULLIF(a.total_clicks, 0), 2)
    ELSE NULL 
  END AS performance_clicks_pct_of_ads
FROM performance_by_asin p
FULL OUTER JOIN ads_by_most_asin a
  ON p.child_asin = a.asin
ORDER BY COALESCE(p.total_clicks, a.total_clicks) DESC;

-- =============================================
-- DETAILED RECORD-LEVEL COMPARISON
-- =============================================

SELECT 
  p.child_asin,
  p.CLICKS as performance_clicks,
  a.most_advertised_asin_clicks,
  a.clicks as ads_clicks,
  a.campaign_name,
  a.search_term,
  a.campaign_type,
  a.ad_group_id
FROM `onyga-482313.OI.STG_AMAZON_PERFORMANCE` p
INNER JOIN `onyga-482313.OI.STG_AMAZON_ADS` a
  ON p.child_asin = a.most_advertised_asin_clicks
  AND p.date = a.date
WHERE p.date = '2026-01-29'
ORDER BY p.CLICKS DESC;
