-- =============================================
-- Verification Query: FACT_SEARCH_QUERY vs STG_SCP_WEEKLY
-- =============================================
-- Purpose: Verify that FACT_SEARCH_QUERY totals match STG_SCP_WEEKLY
--          when aggregated by ASIN, Year, Week
-- Project: onyga-482313
-- Dataset: OI
--
-- Expected Result: All differences should be 0 (or very close to 0 for sales_amount due to rounding)
-- =============================================

-- Detailed Comparison: Show all ASIN+Year+Week combinations with differences
WITH fact_totals AS (
  SELECT 
    ASIN,
    Year,
    Week,
    SUM(impressions) as fact_impressions,
    SUM(clicks) as fact_clicks,
    SUM(cart_adds) as fact_cart_adds,
    SUM(conversions) as fact_conversions,
    SUM(sales_amount) as fact_sales_amount
  FROM `onyga-482313.OI.FACT_SEARCH_QUERY`
  GROUP BY ASIN, Year, Week
),
scp_totals AS (
  SELECT 
    ASIN,
    Year,
    Week,
    impressions as scp_impressions,
    clicks as scp_clicks,
    cart_adds as scp_cart_adds,
    conversions as scp_conversions,
    sales_amount as scp_sales_amount
  FROM `onyga-482313.OI.STG_SCP_WEEKLY`
)
SELECT 
  COALESCE(f.ASIN, s.ASIN) as ASIN,
  COALESCE(f.Year, s.Year) as Year,
  COALESCE(f.Week, s.Week) as Week,
  
  -- Impressions comparison
  COALESCE(f.fact_impressions, 0) as fact_impressions,
  COALESCE(s.scp_impressions, 0) as scp_impressions,
  COALESCE(f.fact_impressions, 0) - COALESCE(s.scp_impressions, 0) as impressions_diff,
  
  -- Clicks comparison
  COALESCE(f.fact_clicks, 0) as fact_clicks,
  COALESCE(s.scp_clicks, 0) as scp_clicks,
  COALESCE(f.fact_clicks, 0) - COALESCE(s.scp_clicks, 0) as clicks_diff,
  
  -- Cart Adds comparison
  COALESCE(f.fact_cart_adds, 0) as fact_cart_adds,
  COALESCE(s.scp_cart_adds, 0) as scp_cart_adds,
  COALESCE(f.fact_cart_adds, 0) - COALESCE(s.scp_cart_adds, 0) as cart_adds_diff,
  
  -- Conversions comparison
  COALESCE(f.fact_conversions, 0) as fact_conversions,
  COALESCE(s.scp_conversions, 0) as scp_conversions,
  COALESCE(f.fact_conversions, 0) - COALESCE(s.scp_conversions, 0) as conversions_diff,
  
  -- Sales Amount comparison
  COALESCE(f.fact_sales_amount, 0) as fact_sales_amount,
  COALESCE(s.scp_sales_amount, 0) as scp_sales_amount,
  COALESCE(f.fact_sales_amount, 0) - COALESCE(s.scp_sales_amount, 0) as sales_amount_diff,
  
  -- Status indicator
  CASE 
    WHEN COALESCE(f.fact_impressions, 0) = COALESCE(s.scp_impressions, 0)
      AND COALESCE(f.fact_clicks, 0) = COALESCE(s.scp_clicks, 0)
      AND COALESCE(f.fact_cart_adds, 0) = COALESCE(s.scp_cart_adds, 0)
      AND COALESCE(f.fact_conversions, 0) = COALESCE(s.scp_conversions, 0)
      AND ABS(COALESCE(f.fact_sales_amount, 0) - COALESCE(s.scp_sales_amount, 0)) < 0.01
    THEN 'MATCH'
    ELSE 'MISMATCH'
  END as match_status
  
FROM fact_totals f
FULL OUTER JOIN scp_totals s
  ON f.ASIN = s.ASIN
  AND f.Year = s.Year
  AND f.Week = s.Week
ORDER BY 
  match_status DESC,
  COALESCE(f.Year, s.Year) DESC,
  COALESCE(f.Week, s.Week) DESC,
  COALESCE(f.ASIN, s.ASIN);

-- =============================================
-- Summary Statistics
-- =============================================

SELECT 
  'Summary' as check_type,
  COUNT(*) as total_asin_week_combinations,
  COUNTIF(
    impressions_diff = 0 
    AND clicks_diff = 0 
    AND cart_adds_diff = 0 
    AND conversions_diff = 0 
    AND ABS(sales_amount_diff) < 0.01
  ) as perfect_matches,
  COUNTIF(
    impressions_diff != 0 
    OR clicks_diff != 0 
    OR cart_adds_diff != 0 
    OR conversions_diff != 0 
    OR ABS(sales_amount_diff) >= 0.01
  ) as mismatches,
  SUM(ABS(impressions_diff)) as total_impressions_diff,
  SUM(ABS(clicks_diff)) as total_clicks_diff,
  SUM(ABS(cart_adds_diff)) as total_cart_adds_diff,
  SUM(ABS(conversions_diff)) as total_conversions_diff,
  SUM(ABS(sales_amount_diff)) as total_sales_amount_diff,
  -- Percentage match
  ROUND(
    COUNTIF(
      impressions_diff = 0 
      AND clicks_diff = 0 
      AND cart_adds_diff = 0 
      AND conversions_diff = 0 
      AND ABS(sales_amount_diff) < 0.01
    ) * 100.0 / NULLIF(COUNT(*), 0),
    2
  ) as match_percentage
FROM (
  WITH fact_totals AS (
    SELECT 
      ASIN,
      Year,
      Week,
      SUM(impressions) as fact_impressions,
      SUM(clicks) as fact_clicks,
      SUM(cart_adds) as fact_cart_adds,
      SUM(conversions) as fact_conversions,
      SUM(sales_amount) as fact_sales_amount
    FROM `onyga-482313.OI.FACT_SEARCH_QUERY`
    GROUP BY ASIN, Year, Week
  ),
  scp_totals AS (
    SELECT 
      ASIN,
      Year,
      Week,
      impressions as scp_impressions,
      clicks as scp_clicks,
      cart_adds as scp_cart_adds,
      conversions as scp_conversions,
      sales_amount as scp_sales_amount
    FROM `onyga-482313.OI.STG_SCP_WEEKLY`
  )
  SELECT 
    COALESCE(f.fact_impressions, 0) - COALESCE(s.scp_impressions, 0) as impressions_diff,
    COALESCE(f.fact_clicks, 0) - COALESCE(s.scp_clicks, 0) as clicks_diff,
    COALESCE(f.fact_cart_adds, 0) - COALESCE(s.scp_cart_adds, 0) as cart_adds_diff,
    COALESCE(f.fact_conversions, 0) - COALESCE(s.scp_conversions, 0) as conversions_diff,
    COALESCE(f.fact_sales_amount, 0) - COALESCE(s.scp_sales_amount, 0) as sales_amount_diff
  FROM fact_totals f
  FULL OUTER JOIN scp_totals s
    ON f.ASIN = s.ASIN
    AND f.Year = s.Year
    AND f.Week = s.Week
);

-- =============================================
-- Data Source Breakdown
-- =============================================

SELECT 
  data_source,
  COUNT(*) as record_count,
  COUNT(DISTINCT ASIN) as unique_asins,
  COUNT(DISTINCT CONCAT(CAST(Year AS STRING), '-', CAST(Week AS STRING))) as unique_weeks,
  SUM(impressions) as total_impressions,
  SUM(clicks) as total_clicks,
  SUM(cart_adds) as total_cart_adds,
  SUM(conversions) as total_conversions,
  SUM(sales_amount) as total_sales_amount
FROM `onyga-482313.OI.FACT_SEARCH_QUERY`
GROUP BY data_source
ORDER BY data_source;
