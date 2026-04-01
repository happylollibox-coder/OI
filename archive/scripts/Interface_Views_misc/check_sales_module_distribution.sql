-- =============================================
-- Count New Field Rows Per Value
-- =============================================
-- Purpose: Validate sales module classification distribution
-- Checks: inferred_sales_module and placement_type value counts
-- =============================================

-- Count by inferred_sales_module
SELECT 
  inferred_sales_module,
  COUNT(*) AS row_count,
  COUNT(DISTINCT campaign_id) AS unique_campaigns,
  COUNT(DISTINCT date) AS unique_dates,
  SUM(sales) AS total_sales,
  SUM(cost) AS total_cost,
  ROUND(SUM(sales) / NULLIF(SUM(cost), 0), 2) AS ROAS
FROM `onyga-482313.OI.V_SRC_AmazonAds_SearchTerms`
GROUP BY inferred_sales_module
ORDER BY row_count DESC;

-- Count by placement_type
SELECT 
  placement_type,
  COUNT(*) AS row_count,
  COUNT(DISTINCT campaign_id) AS unique_campaigns,
  COUNT(DISTINCT date) AS unique_dates,
  SUM(sales) AS total_sales,
  SUM(cost) AS total_cost,
  ROUND(SUM(sales) / NULLIF(SUM(cost), 0), 2) AS ROAS
FROM `onyga-482313.OI.V_SRC_AmazonAds_SearchTerms`
GROUP BY placement_type
ORDER BY row_count DESC;

-- Combined breakdown by both fields
SELECT 
  inferred_sales_module,
  placement_type,
  campaign_type,
  COUNT(*) AS row_count,
  SUM(sales) AS total_sales,
  SUM(cost) AS total_cost
FROM `onyga-482313.OI.V_SRC_AmazonAds_SearchTerms`
GROUP BY inferred_sales_module, placement_type, campaign_type
ORDER BY row_count DESC;

-- Sample of search_term values by classification
SELECT 
  inferred_sales_module,
  placement_type,
  search_term,
  COUNT(*) AS occurrences,
  SUM(sales) AS total_sales
FROM `onyga-482313.OI.V_SRC_AmazonAds_SearchTerms`
GROUP BY inferred_sales_module, placement_type, search_term
ORDER BY occurrences DESC
LIMIT 50;
