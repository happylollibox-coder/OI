-- =============================================
-- Test Matching Strategies: Advertised Product to Search Terms
-- =============================================
-- Purpose: Investigate which matching strategy works best
-- Tests: campaign+date, campaign+ad_group+date, campaign+ad_group+ad_id+date

-- =============================================
-- 1. Basic Statistics
-- =============================================
SELECT 
  'AdvertisedProduct Total Records' as metric,
  COUNT(*) as count
FROM `onyga-482313.OI.V_SRC_AmazonAds_advertised_product`

UNION ALL

SELECT 
  'SearchTerms Total Records' as metric,
  COUNT(*) as count
FROM `onyga-482313.OI.V_SRC_AmazonAds_SearchTerms`

UNION ALL

SELECT 
  'AdvertisedProduct with Non-NULL campaign_id' as metric,
  COUNT(*) as count
FROM `onyga-482313.OI.V_SRC_AmazonAds_advertised_product`
WHERE campaign_id IS NOT NULL

UNION ALL

SELECT 
  'SearchTerms with Non-NULL campaign_id' as metric,
  COUNT(*) as count
FROM `onyga-482313.OI.V_SRC_AmazonAds_SearchTerms`
WHERE campaign_id IS NOT NULL;

-- =============================================
-- 2. Strategy A: campaign_id + date
-- =============================================
SELECT 
  'Strategy A: campaign + date' as match_type,
  COUNT(DISTINCT ap.campaign_id || '|' || CAST(ap.date AS STRING)) as advertised_combinations,
  COUNT(DISTINCT st.campaign_id || '|' || CAST(st.date AS STRING)) as searchterm_combinations,
  COUNT(DISTINCT CASE WHEN st.campaign_id IS NOT NULL THEN ap.campaign_id || '|' || CAST(ap.date AS STRING) END) as matched_combinations,
  ROUND(COUNT(DISTINCT CASE WHEN st.campaign_id IS NOT NULL THEN ap.campaign_id || '|' || CAST(ap.date AS STRING) END) * 100.0 / 
        NULLIF(COUNT(DISTINCT ap.campaign_id || '|' || CAST(ap.date AS STRING)), 0), 2) as match_percentage,
  COUNT(*) as total_searchterm_records,
  COUNT(CASE WHEN st.campaign_id IS NOT NULL THEN 1 END) as matched_searchterm_records,
  ROUND(COUNT(CASE WHEN st.campaign_id IS NOT NULL THEN 1 END) * 100.0 / NULLIF(COUNT(*), 0), 2) as record_match_percentage
FROM `onyga-482313.OI.V_SRC_AmazonAds_advertised_product` ap
LEFT JOIN `onyga-482313.OI.V_SRC_AmazonAds_SearchTerms` st
  ON ap.campaign_id = st.campaign_id
  AND ap.date = st.date;

-- =============================================
-- 3. Strategy B: campaign_id + ad_group_id + date
-- =============================================
SELECT 
  'Strategy B: campaign + ad_group + date' as match_type,
  COUNT(DISTINCT ap.campaign_id || '|' || ap.ad_group_id || '|' || CAST(ap.date AS STRING)) as advertised_combinations,
  COUNT(DISTINCT st.campaign_id || '|' || st.ad_group_id || '|' || CAST(st.date AS STRING)) as searchterm_combinations,
  COUNT(DISTINCT CASE WHEN st.campaign_id IS NOT NULL THEN ap.campaign_id || '|' || ap.ad_group_id || '|' || CAST(ap.date AS STRING) END) as matched_combinations,
  ROUND(COUNT(DISTINCT CASE WHEN st.campaign_id IS NOT NULL THEN ap.campaign_id || '|' || ap.ad_group_id || '|' || CAST(ap.date AS STRING) END) * 100.0 / 
        NULLIF(COUNT(DISTINCT ap.campaign_id || '|' || ap.ad_group_id || '|' || CAST(ap.date AS STRING)), 0), 2) as match_percentage,
  COUNT(*) as total_searchterm_records,
  COUNT(CASE WHEN st.campaign_id IS NOT NULL THEN 1 END) as matched_searchterm_records,
  ROUND(COUNT(CASE WHEN st.campaign_id IS NOT NULL THEN 1 END) * 100.0 / NULLIF(COUNT(*), 0), 2) as record_match_percentage
FROM `onyga-482313.OI.V_SRC_AmazonAds_advertised_product` ap
LEFT JOIN `onyga-482313.OI.V_SRC_AmazonAds_SearchTerms` st
  ON ap.campaign_id = st.campaign_id
  AND ap.ad_group_id = st.ad_group_id
  AND ap.date = st.date;

-- =============================================
-- 4. Strategy C: campaign_id + ad_group_id + ad_id + date
-- =============================================
-- Note: SearchTerms doesn't have ad_id, so this will likely have 0% match
-- But we'll test it to confirm
SELECT 
  'Strategy C: campaign + ad_group + ad_id + date' as match_type,
  COUNT(DISTINCT ap.campaign_id || '|' || ap.ad_group_id || '|' || ap.ad_id || '|' || CAST(ap.date AS STRING)) as advertised_combinations,
  COUNT(DISTINCT st.campaign_id || '|' || st.ad_group_id || '|' || CAST(st.date AS STRING)) as searchterm_combinations,
  COUNT(DISTINCT CASE WHEN st.campaign_id IS NOT NULL THEN ap.campaign_id || '|' || ap.ad_group_id || '|' || ap.ad_id || '|' || CAST(ap.date AS STRING) END) as matched_combinations,
  ROUND(COUNT(DISTINCT CASE WHEN st.campaign_id IS NOT NULL THEN ap.campaign_id || '|' || ap.ad_group_id || '|' || ap.ad_id || '|' || CAST(ap.date AS STRING) END) * 100.0 / 
        NULLIF(COUNT(DISTINCT ap.campaign_id || '|' || ap.ad_group_id || '|' || ap.ad_id || '|' || CAST(ap.date AS STRING)), 0), 2) as match_percentage,
  COUNT(*) as total_searchterm_records,
  COUNT(CASE WHEN st.campaign_id IS NOT NULL THEN 1 END) as matched_searchterm_records,
  ROUND(COUNT(CASE WHEN st.campaign_id IS NOT NULL THEN 1 END) * 100.0 / NULLIF(COUNT(*), 0), 2) as record_match_percentage
FROM `onyga-482313.OI.V_SRC_AmazonAds_advertised_product` ap
LEFT JOIN `onyga-482313.OI.V_SRC_AmazonAds_SearchTerms` st
  ON ap.campaign_id = st.campaign_id
  AND ap.ad_group_id = st.ad_group_id
  AND ap.date = st.date
  -- Note: SearchTerms doesn't have ad_id, so this join will never match on ad_id
  -- This is just to show that ad_id matching is not possible;

-- =============================================
-- 5. Combined Analysis: All Strategies with ASIN Details
-- =============================================
WITH advertised_product_aggregated AS (
  SELECT 
    campaign_id,
    ad_group_id,
    date,
    -- Aggregate ASINs per campaign/ad_group/date
    MAX(advertised_asin) as primary_advertised_asin,
    STRING_AGG(DISTINCT advertised_asin, ', ') as all_advertised_asins,
    COUNT(DISTINCT advertised_asin) as num_unique_asins,
    SUM(impressions) as total_impressions,
    SUM(clicks) as total_clicks,
    SUM(cost) as total_cost,
    SUM(purchases_30_d) as total_orders_30d,
    SUM(sales_30_d) as total_sales_30d
  FROM `onyga-482313.OI.V_SRC_AmazonAds_advertised_product`
  GROUP BY campaign_id, ad_group_id, date
)
SELECT 
  'Combined Matching Analysis' as analysis_type,
  COUNT(*) as total_searchterm_records,
  
  -- Strategy A: campaign + date
  COUNT(CASE WHEN ap1.primary_advertised_asin IS NOT NULL THEN 1 END) as matched_via_campaign_date,
  ROUND(COUNT(CASE WHEN ap1.primary_advertised_asin IS NOT NULL THEN 1 END) * 100.0 / NULLIF(COUNT(*), 0), 2) as campaign_date_match_pct,
  
  -- Strategy B: campaign + ad_group + date
  COUNT(CASE WHEN ap2.primary_advertised_asin IS NOT NULL THEN 1 END) as matched_via_campaign_adgroup_date,
  ROUND(COUNT(CASE WHEN ap2.primary_advertised_asin IS NOT NULL THEN 1 END) * 100.0 / NULLIF(COUNT(*), 0), 2) as campaign_adgroup_date_match_pct,
  
  -- Both strategies
  COUNT(CASE WHEN ap1.primary_advertised_asin IS NOT NULL AND ap2.primary_advertised_asin IS NOT NULL THEN 1 END) as matched_via_both,
  
  -- Total matched (either strategy)
  COUNT(CASE WHEN ap1.primary_advertised_asin IS NOT NULL OR ap2.primary_advertised_asin IS NOT NULL THEN 1 END) as total_matched,
  ROUND(COUNT(CASE WHEN ap1.primary_advertised_asin IS NOT NULL OR ap2.primary_advertised_asin IS NOT NULL THEN 1 END) * 100.0 / NULLIF(COUNT(*), 0), 2) as total_match_percentage,
  
  -- Unmatched
  COUNT(CASE WHEN ap1.primary_advertised_asin IS NULL AND ap2.primary_advertised_asin IS NULL THEN 1 END) as unmatched,
  ROUND(COUNT(CASE WHEN ap1.primary_advertised_asin IS NULL AND ap2.primary_advertised_asin IS NULL THEN 1 END) * 100.0 / NULLIF(COUNT(*), 0), 2) as unmatched_percentage

FROM `onyga-482313.OI.V_SRC_AmazonAds_SearchTerms` st
LEFT JOIN advertised_product_aggregated ap1
  ON st.campaign_id = ap1.campaign_id
  AND st.date = ap1.date
LEFT JOIN advertised_product_aggregated ap2
  ON st.campaign_id = ap2.campaign_id
  AND st.ad_group_id = ap2.ad_group_id
  AND st.date = ap2.date;

-- =============================================
-- 6. Sample Matched Records for Validation
-- =============================================
WITH advertised_product_aggregated AS (
  SELECT 
    campaign_id,
    ad_group_id,
    date,
    MAX(advertised_asin) as primary_advertised_asin,
    STRING_AGG(DISTINCT advertised_asin, ', ') as all_advertised_asins,
    COUNT(DISTINCT advertised_asin) as num_unique_asins,
    SUM(impressions) as total_impressions,
    SUM(clicks) as total_clicks,
    SUM(cost) as total_cost
  FROM `onyga-482313.OI.V_SRC_AmazonAds_advertised_product`
  GROUP BY campaign_id, ad_group_id, date
)
SELECT 
  st.date,
  st.campaign_id,
  c.campaign_name,
  st.ad_group_id,
  st.keyword_id,
  st.search_term,
  st.clicks as searchterm_clicks,
  st.impressions as searchterm_impressions,
  st.cost as searchterm_cost,
  
  -- Strategy A: campaign + date
  ap1.primary_advertised_asin as asin_campaign_date,
  ap1.all_advertised_asins as all_asins_campaign_date,
  ap1.num_unique_asins as num_asins_campaign_date,
  
  -- Strategy B: campaign + ad_group + date
  ap2.primary_advertised_asin as asin_campaign_adgroup_date,
  ap2.all_advertised_asins as all_asins_campaign_adgroup_date,
  ap2.num_unique_asins as num_asins_campaign_adgroup_date,
  
  -- Match Status
  CASE 
    WHEN ap1.primary_advertised_asin IS NOT NULL AND ap2.primary_advertised_asin IS NOT NULL 
      AND ap1.primary_advertised_asin = ap2.primary_advertised_asin THEN 'Both Match (Same ASIN)'
    WHEN ap1.primary_advertised_asin IS NOT NULL AND ap2.primary_advertised_asin IS NOT NULL 
      AND ap1.primary_advertised_asin != ap2.primary_advertised_asin THEN 'Both Match (Different ASINs)'
    WHEN ap1.primary_advertised_asin IS NOT NULL THEN 'Campaign+Date Only'
    WHEN ap2.primary_advertised_asin IS NOT NULL THEN 'Campaign+AdGroup+Date Only'
    ELSE 'No Match'
  END as match_status

FROM `onyga-482313.OI.V_SRC_AmazonAds_SearchTerms` st
LEFT JOIN advertised_product_aggregated ap1
  ON st.campaign_id = ap1.campaign_id
  AND st.date = ap1.date
LEFT JOIN advertised_product_aggregated ap2
  ON st.campaign_id = ap2.campaign_id
  AND st.ad_group_id = ap2.ad_group_id
  AND st.date = ap2.date
LEFT JOIN `onyga-482313.OI.V_SRC_AmazonAds_campaign_history` c
  ON st.campaign_id = c.campaign_id
  AND TIMESTAMP(st.date) BETWEEN c.OI_start_date AND c.OI_end_date
WHERE ap1.primary_advertised_asin IS NOT NULL OR ap2.primary_advertised_asin IS NOT NULL
ORDER BY st.date DESC, st.clicks DESC
LIMIT 100;

-- =============================================
-- 7. Compare with Purchased Product Matching
-- =============================================
WITH advertised_product_aggregated AS (
  SELECT 
    campaign_id,
    ad_group_id,
    date,
    MAX(advertised_asin) as primary_advertised_asin,
    STRING_AGG(DISTINCT advertised_asin, ', ') as all_advertised_asins
  FROM `onyga-482313.OI.V_SRC_AmazonAds_advertised_product`
  GROUP BY campaign_id, ad_group_id, date
),
purchased_product_aggregated AS (
  SELECT 
    campaign_id,
    date,
    MAX(CASE WHEN advertised_asin IS NOT NULL AND advertised_asin != 'Unknown' 
        THEN advertised_asin END) as primary_advertised_asin,
    STRING_AGG(DISTINCT CASE WHEN advertised_asin IS NOT NULL AND advertised_asin != 'Unknown' 
             THEN advertised_asin END, ', ') as all_advertised_asins
  FROM `onyga-482313.OI.V_SRC_AmazonAds_purchased_product`
  GROUP BY campaign_id, date
)
SELECT 
  'Comparison: Advertised Product vs Purchased Product' as comparison,
  COUNT(*) as total_searchterm_records,
  
  -- Advertised Product matching
  COUNT(CASE WHEN ap.primary_advertised_asin IS NOT NULL THEN 1 END) as matched_via_advertised_product,
  ROUND(COUNT(CASE WHEN ap.primary_advertised_asin IS NOT NULL THEN 1 END) * 100.0 / NULLIF(COUNT(*), 0), 2) as advertised_product_match_pct,
  
  -- Purchased Product matching
  COUNT(CASE WHEN pp.primary_advertised_asin IS NOT NULL THEN 1 END) as matched_via_purchased_product,
  ROUND(COUNT(CASE WHEN pp.primary_advertised_asin IS NOT NULL THEN 1 END) * 100.0 / NULLIF(COUNT(*), 0), 2) as purchased_product_match_pct,
  
  -- Both match
  COUNT(CASE WHEN ap.primary_advertised_asin IS NOT NULL AND pp.primary_advertised_asin IS NOT NULL THEN 1 END) as matched_via_both,
  
  -- When both match, do ASINs agree?
  COUNT(CASE WHEN ap.primary_advertised_asin IS NOT NULL 
             AND pp.primary_advertised_asin IS NOT NULL 
             AND ap.primary_advertised_asin = pp.primary_advertised_asin THEN 1 END) as both_match_same_asin,
  COUNT(CASE WHEN ap.primary_advertised_asin IS NOT NULL 
             AND pp.primary_advertised_asin IS NOT NULL 
             AND ap.primary_advertised_asin != pp.primary_advertised_asin THEN 1 END) as both_match_different_asin,
  
  -- Total matched (either method)
  COUNT(CASE WHEN ap.primary_advertised_asin IS NOT NULL OR pp.primary_advertised_asin IS NOT NULL THEN 1 END) as total_matched,
  ROUND(COUNT(CASE WHEN ap.primary_advertised_asin IS NOT NULL OR pp.primary_advertised_asin IS NOT NULL THEN 1 END) * 100.0 / NULLIF(COUNT(*), 0), 2) as total_match_percentage

FROM `onyga-482313.OI.V_SRC_AmazonAds_SearchTerms` st
LEFT JOIN advertised_product_aggregated ap
  ON st.campaign_id = ap.campaign_id
  AND st.date = ap.date
LEFT JOIN purchased_product_aggregated pp
  ON st.campaign_id = pp.campaign_id
  AND st.date = pp.date;
