-- =============================================
-- Week 51 Comparison: STG_SCD_WEEKLY vs Module #1
-- Week: Dec 14-20, 2025
-- =============================================

-- STG_SCD_WEEKLY: All Search Traffic (Organic + Paid)
-- V_SRC_AmazonAds_SearchTerms Module #1: Paid Search Only

-- RESULTS:
-- ✅ Impressions: Module #1 is SMALLER (42.41% of STG)
-- ❌ Clicks: Module #1 is LARGER (222.29% of STG) 
-- ❌ Sales: Module #1 is LARGER (366.89% of STG)

-- This suggests data quality issues or scope differences
-- =============================================

SELECT 
  'Week 51: Dec 14-20, 2025' as week_info,
  'STG_SCD_WEEKLY (All Search Traffic)' as source,
  'Organic + Paid Search' as scope,
  SUM(impression_data_impression_count) as impressions,
  SUM(click_data_click_count) as clicks,
  SUM(purchase_data_search_traffic_sales_amount) as sales
FROM `onyga-482313.OI.STG_SCD_WEEKLY`
WHERE week_start_date = '2025-12-14'

UNION ALL

SELECT 
  'Week 51: Dec 14-20, 2025' as week_info,
  'V_SRC_AmazonAds_SearchTerms' as source,
  'Module #1 - Paid Search Only' as scope,
  SUM(impressions) as impressions,
  SUM(clicks) as clicks,
  SUM(sales) as sales
FROM `onyga-482313.OI.V_SRC_AmazonAds_SearchTerms`
WHERE inferred_sales_module = 'Module #1 - Paid Search (Text Search Term)'
  AND date >= '2025-12-14' 
  AND date <= '2025-12-20'
  AND DATE_TRUNC(DATE(date), WEEK(MONDAY)) = '2025-12-15';
