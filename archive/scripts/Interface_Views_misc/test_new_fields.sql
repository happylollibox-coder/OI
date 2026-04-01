-- =============================================
-- Quick Test: New Field Distribution
-- =============================================
-- Run this in BigQuery console to test the new fields
-- =============================================

-- Test 1: Basic count by inferred_sales_module
SELECT 
  inferred_sales_module,
  COUNT(*) AS row_count,
  ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct_of_total
FROM `onyga-482313.OI.V_SRC_AmazonAds_SearchTerms`
GROUP BY inferred_sales_module
ORDER BY row_count DESC;

-- Test 2: Basic count by placement_type
SELECT 
  placement_type,
  COUNT(*) AS row_count,
  ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct_of_total
FROM `onyga-482313.OI.V_SRC_AmazonAds_SearchTerms`
GROUP BY placement_type
ORDER BY row_count DESC;

-- Test 3: Sample rows to see the new fields
SELECT 
  date,
  campaign_id,
  search_term,
  inferred_sales_module,
  placement_type,
  campaign_type,
  sales,
  cost
FROM `onyga-482313.OI.V_SRC_AmazonAds_SearchTerms`
ORDER BY date DESC
LIMIT 20;

-- Test 4: Verify field exists and check NULL counts
SELECT 
  COUNT(*) AS total_rows,
  COUNT(inferred_sales_module) AS non_null_inferred_module,
  COUNT(placement_type) AS non_null_placement_type,
  COUNT(campaign_type) AS non_null_campaign_type,
  COUNT(CASE WHEN inferred_sales_module IS NULL THEN 1 END) AS null_inferred_module,
  COUNT(CASE WHEN placement_type IS NULL THEN 1 END) AS null_placement_type
FROM `onyga-482313.OI.V_SRC_AmazonAds_SearchTerms`;
