-- =============================================
-- Test Best Approach to Get advertised_asin for Search Terms
-- =============================================
-- Purpose: Find the most effective way to match search terms to advertised_asin

-- =============================================
-- 1. Check advertised_asin availability in purchased_product
-- =============================================
SELECT 
  'advertised_asin Statistics' as metric,
  COUNT(*) as total_records,
  COUNT(advertised_asin) as records_with_advertised_asin,
  COUNT(CASE WHEN advertised_asin IS NOT NULL AND advertised_asin != 'Unknown' THEN 1 END) as valid_advertised_asin,
  COUNT(DISTINCT advertised_asin) as unique_advertised_asins,
  ROUND(COUNT(CASE WHEN advertised_asin IS NOT NULL AND advertised_asin != 'Unknown' THEN 1 END) * 100.0 / NULLIF(COUNT(*), 0), 2) as valid_percentage
FROM `onyga-482313.OI.V_SRC_AmazonAds_purchased_product`;

-- =============================================
-- 2. Test Matching Strategies for advertised_asin
-- =============================================

-- Strategy A: campaign + ad_group + date (without keyword_id)
WITH purchased_product_aggregated AS (
  SELECT 
    campaign_id,
    ad_group_id,
    date,
    -- Get primary advertised_asin (most common or first)
    MAX(CASE WHEN advertised_asin IS NOT NULL AND advertised_asin != 'Unknown' THEN advertised_asin END) as primary_advertised_asin,
    -- Get all unique advertised_asins
    STRING_AGG(DISTINCT CASE WHEN advertised_asin IS NOT NULL AND advertised_asin != 'Unknown' THEN advertised_asin END, ',') as all_advertised_asins,
    COUNT(DISTINCT CASE WHEN advertised_asin IS NOT NULL AND advertised_asin != 'Unknown' THEN advertised_asin END) as num_unique_advertised_asins
  FROM `onyga-482313.OI.V_SRC_AmazonAds_purchased_product`
  GROUP BY campaign_id, ad_group_id, date
)
SELECT 
  'Strategy A: campaign + ad_group + date' as strategy,
  COUNT(*) as total_search_terms,
  COUNT(CASE WHEN pp.primary_advertised_asin IS NOT NULL THEN 1 END) as matched_count,
  ROUND(COUNT(CASE WHEN pp.primary_advertised_asin IS NOT NULL THEN 1 END) * 100.0 / NULLIF(COUNT(*), 0), 2) as match_percentage,
  COUNT(CASE WHEN pp.num_unique_advertised_asins > 1 THEN 1 END) as cases_with_multiple_asins,
  AVG(pp.num_unique_advertised_asins) as avg_asins_per_match
FROM `onyga-482313.OI.V_SRC_AmazonAds_SearchTerms` st
LEFT JOIN purchased_product_aggregated pp
  ON st.campaign_id = pp.campaign_id
  AND st.ad_group_id = pp.ad_group_id
  AND st.date = pp.date;

-- Strategy B: campaign + date only (broader match)
WITH purchased_product_aggregated AS (
  SELECT 
    campaign_id,
    date,
    MAX(CASE WHEN advertised_asin IS NOT NULL AND advertised_asin != 'Unknown' THEN advertised_asin END) as primary_advertised_asin,
    STRING_AGG(DISTINCT CASE WHEN advertised_asin IS NOT NULL AND advertised_asin != 'Unknown' THEN advertised_asin END, ',') as all_advertised_asins,
    COUNT(DISTINCT CASE WHEN advertised_asin IS NOT NULL AND advertised_asin != 'Unknown' THEN advertised_asin END) as num_unique_advertised_asins
  FROM `onyga-482313.OI.V_SRC_AmazonAds_purchased_product`
  GROUP BY campaign_id, date
)
SELECT 
  'Strategy B: campaign + date only' as strategy,
  COUNT(*) as total_search_terms,
  COUNT(CASE WHEN pp.primary_advertised_asin IS NOT NULL THEN 1 END) as matched_count,
  ROUND(COUNT(CASE WHEN pp.primary_advertised_asin IS NOT NULL THEN 1 END) * 100.0 / NULLIF(COUNT(*), 0), 2) as match_percentage,
  COUNT(CASE WHEN pp.num_unique_advertised_asins > 1 THEN 1 END) as cases_with_multiple_asins,
  AVG(pp.num_unique_advertised_asins) as avg_asins_per_match
FROM `onyga-482313.OI.V_SRC_AmazonAds_SearchTerms` st
LEFT JOIN purchased_product_aggregated pp
  ON st.campaign_id = pp.campaign_id
  AND st.date = pp.date;

-- Strategy C: campaign + ad_group + keyword + date (exact match)
WITH purchased_product_aggregated AS (
  SELECT 
    campaign_id,
    ad_group_id,
    keyword_id,
    date,
    MAX(CASE WHEN advertised_asin IS NOT NULL AND advertised_asin != 'Unknown' THEN advertised_asin END) as primary_advertised_asin,
    STRING_AGG(DISTINCT CASE WHEN advertised_asin IS NOT NULL AND advertised_asin != 'Unknown' THEN advertised_asin END, ',') as all_advertised_asins,
    COUNT(DISTINCT CASE WHEN advertised_asin IS NOT NULL AND advertised_asin != 'Unknown' THEN advertised_asin END) as num_unique_advertised_asins
  FROM `onyga-482313.OI.V_SRC_AmazonAds_purchased_product`
  GROUP BY campaign_id, ad_group_id, keyword_id, date
)
SELECT 
  'Strategy C: campaign + ad_group + keyword + date' as strategy,
  COUNT(*) as total_search_terms,
  COUNT(CASE WHEN pp.primary_advertised_asin IS NOT NULL THEN 1 END) as matched_count,
  ROUND(COUNT(CASE WHEN pp.primary_advertised_asin IS NOT NULL THEN 1 END) * 100.0 / NULLIF(COUNT(*), 0), 2) as match_percentage,
  COUNT(CASE WHEN pp.num_unique_advertised_asins > 1 THEN 1 END) as cases_with_multiple_asins,
  AVG(pp.num_unique_advertised_asins) as avg_asins_per_match
FROM `onyga-482313.OI.V_SRC_AmazonAds_SearchTerms` st
LEFT JOIN purchased_product_aggregated pp
  ON st.campaign_id = pp.campaign_id
  AND st.ad_group_id = pp.ad_group_id
  AND COALESCE(st.keyword_id, '-1') = COALESCE(pp.keyword_id, '-1')
  AND st.date = pp.date;

-- =============================================
-- 3. Analyze Multiple advertised_asins per Match
-- =============================================
WITH purchased_product_aggregated AS (
  SELECT 
    campaign_id,
    ad_group_id,
    date,
    MAX(CASE WHEN advertised_asin IS NOT NULL AND advertised_asin != 'Unknown' THEN advertised_asin END) as primary_advertised_asin,
    STRING_AGG(DISTINCT CASE WHEN advertised_asin IS NOT NULL AND advertised_asin != 'Unknown' THEN advertised_asin END, ',') as all_advertised_asins,
    COUNT(DISTINCT CASE WHEN advertised_asin IS NOT NULL AND advertised_asin != 'Unknown' THEN advertised_asin END) as num_unique_advertised_asins
  FROM `onyga-482313.OI.V_SRC_AmazonAds_purchased_product`
  GROUP BY campaign_id, ad_group_id, date
)
SELECT 
  pp.num_unique_advertised_asins,
  COUNT(*) as number_of_matches,
  ROUND(COUNT(*) * 100.0 / NULLIF(SUM(COUNT(*)) OVER (), 0), 2) as percentage_of_matches
FROM `onyga-482313.OI.V_SRC_AmazonAds_SearchTerms` st
INNER JOIN purchased_product_aggregated pp
  ON st.campaign_id = pp.campaign_id
  AND st.ad_group_id = pp.ad_group_id
  AND st.date = pp.date
WHERE pp.primary_advertised_asin IS NOT NULL
GROUP BY pp.num_unique_advertised_asins
ORDER BY pp.num_unique_advertised_asins;

-- =============================================
-- 4. Sample Records with advertised_asin
-- =============================================
WITH purchased_product_aggregated AS (
  SELECT 
    campaign_id,
    ad_group_id,
    date,
    MAX(CASE WHEN advertised_asin IS NOT NULL AND advertised_asin != 'Unknown' THEN advertised_asin END) as primary_advertised_asin,
    STRING_AGG(DISTINCT CASE WHEN advertised_asin IS NOT NULL AND advertised_asin != 'Unknown' THEN advertised_asin END, ',') as all_advertised_asins,
    COUNT(DISTINCT CASE WHEN advertised_asin IS NOT NULL AND advertised_asin != 'Unknown' THEN advertised_asin END) as num_unique_advertised_asins
  FROM `onyga-482313.OI.V_SRC_AmazonAds_purchased_product`
  GROUP BY campaign_id, ad_group_id, date
)
SELECT 
  st.date,
  st.campaign_id,
  st.ad_group_id,
  st.keyword_id,
  st.search_term,
  st.clicks,
  st.impressions,
  st.cost,
  pp.primary_advertised_asin,
  pp.all_advertised_asins,
  pp.num_unique_advertised_asins,
  CASE 
    WHEN pp.num_unique_advertised_asins = 1 THEN 'Single ASIN'
    WHEN pp.num_unique_advertised_asins > 1 AND pp.num_unique_advertised_asins <= 3 THEN '2-3 ASINs'
    WHEN pp.num_unique_advertised_asins > 3 THEN '4+ ASINs'
    ELSE 'No ASIN'
  END as asin_complexity
FROM `onyga-482313.OI.V_SRC_AmazonAds_SearchTerms` st
LEFT JOIN purchased_product_aggregated pp
  ON st.campaign_id = pp.campaign_id
  AND st.ad_group_id = pp.ad_group_id
  AND st.date = pp.date
WHERE pp.primary_advertised_asin IS NOT NULL
ORDER BY st.date DESC, st.clicks DESC, pp.num_unique_advertised_asins DESC
LIMIT 50;

-- =============================================
-- 5. Compare advertised_asin vs purchased_asin
-- =============================================
SELECT 
  'ASIN Type Comparison' as metric,
  COUNT(*) as total_records,
  COUNT(advertised_asin) as has_advertised_asin,
  COUNT(purchased_asin) as has_purchased_asin,
  COUNT(CASE WHEN advertised_asin IS NOT NULL AND advertised_asin != 'Unknown' THEN 1 END) as valid_advertised_asin,
  COUNT(CASE WHEN purchased_asin IS NOT NULL THEN 1 END) as valid_purchased_asin,
  COUNT(CASE WHEN advertised_asin = purchased_asin AND advertised_asin != 'Unknown' THEN 1 END) as asins_match,
  COUNT(CASE WHEN advertised_asin != purchased_asin 
             AND advertised_asin IS NOT NULL 
             AND advertised_asin != 'Unknown'
             AND purchased_asin IS NOT NULL THEN 1 END) as asins_differ
FROM `onyga-482313.OI.V_SRC_AmazonAds_purchased_product`;
