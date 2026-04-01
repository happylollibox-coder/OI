-- =============================================
-- Test ASIN Matching Between SearchTerms and PurchasedProduct
-- =============================================
-- Purpose: Diagnostic query to measure matching potential
-- Tests multiple matching strategies to determine best approach

-- =============================================
-- 1. Basic Statistics
-- =============================================
SELECT 
  'SearchTerms Total Records' as metric,
  COUNT(*) as count
FROM `onyga-482313.OI.V_SRC_AmazonAds_SearchTerms`

UNION ALL

SELECT 
  'PurchasedProduct Total Records' as metric,
  COUNT(*) as count
FROM `onyga-482313.OI.V_SRC_AmazonAds_purchased_product`

UNION ALL

SELECT 
  'SearchTerms with Non-NULL campaign_id' as metric,
  COUNT(*) as count
FROM `onyga-482313.OI.V_SRC_AmazonAds_SearchTerms`
WHERE campaign_id IS NOT NULL

UNION ALL

SELECT 
  'PurchasedProduct with Non-NULL campaign_id' as metric,
  COUNT(*) as count
FROM `onyga-482313.OI.V_SRC_AmazonAds_purchased_product`
WHERE campaign_id IS NOT NULL;

-- =============================================
-- 2. Exact Match: campaign_id + ad_group_id + keyword_id + date
-- =============================================
SELECT 
  'Exact Match (campaign + ad_group + keyword + date)' as match_type,
  COUNT(DISTINCT st.campaign_id || '|' || st.ad_group_id || '|' || COALESCE(st.keyword_id, 'NULL') || '|' || CAST(st.date AS STRING)) as searchterm_combinations,
  COUNT(DISTINCT pp.campaign_id || '|' || pp.ad_group_id || '|' || COALESCE(pp.keyword_id, 'NULL') || '|' || CAST(pp.date AS STRING)) as purchased_combinations,
  COUNT(DISTINCT CASE WHEN pp.campaign_id IS NOT NULL THEN st.campaign_id || '|' || st.ad_group_id || '|' || COALESCE(st.keyword_id, 'NULL') || '|' || CAST(st.date AS STRING) END) as matched_combinations,
  ROUND(COUNT(DISTINCT CASE WHEN pp.campaign_id IS NOT NULL THEN st.campaign_id || '|' || st.ad_group_id || '|' || COALESCE(st.keyword_id, 'NULL') || '|' || CAST(st.date AS STRING) END) * 100.0 / 
        NULLIF(COUNT(DISTINCT st.campaign_id || '|' || st.ad_group_id || '|' || COALESCE(st.keyword_id, 'NULL') || '|' || CAST(st.date AS STRING)), 0), 2) as match_percentage
FROM `onyga-482313.OI.V_SRC_AmazonAds_SearchTerms` st
LEFT JOIN `onyga-482313.OI.V_SRC_AmazonAds_purchased_product` pp
  ON st.campaign_id = pp.campaign_id
  AND st.ad_group_id = pp.ad_group_id
  AND COALESCE(st.keyword_id, '-1') = COALESCE(pp.keyword_id, '-1')
  AND st.date = pp.date;

-- =============================================
-- 3. Match Without keyword_id (for targeting campaigns)
-- =============================================
SELECT 
  'Match Without keyword_id (campaign + ad_group + date)' as match_type,
  COUNT(DISTINCT st.campaign_id || '|' || st.ad_group_id || '|' || CAST(st.date AS STRING)) as searchterm_combinations,
  COUNT(DISTINCT pp.campaign_id || '|' || pp.ad_group_id || '|' || CAST(pp.date AS STRING)) as purchased_combinations,
  COUNT(DISTINCT CASE WHEN pp.campaign_id IS NOT NULL THEN st.campaign_id || '|' || st.ad_group_id || '|' || CAST(st.date AS STRING) END) as matched_combinations,
  ROUND(COUNT(DISTINCT CASE WHEN pp.campaign_id IS NOT NULL THEN st.campaign_id || '|' || st.ad_group_id || '|' || CAST(st.date AS STRING) END) * 100.0 / 
        NULLIF(COUNT(DISTINCT st.campaign_id || '|' || st.ad_group_id || '|' || CAST(st.date AS STRING)), 0), 2) as match_percentage
FROM `onyga-482313.OI.V_SRC_AmazonAds_SearchTerms` st
LEFT JOIN `onyga-482313.OI.V_SRC_AmazonAds_purchased_product` pp
  ON st.campaign_id = pp.campaign_id
  AND st.ad_group_id = pp.ad_group_id
  AND st.date = pp.date;

-- =============================================
-- 4. Match by campaign_id + date only
-- =============================================
SELECT 
  'Match by campaign + date only' as match_type,
  COUNT(DISTINCT st.campaign_id || '|' || CAST(st.date AS STRING)) as searchterm_combinations,
  COUNT(DISTINCT pp.campaign_id || '|' || CAST(pp.date AS STRING)) as purchased_combinations,
  COUNT(DISTINCT CASE WHEN pp.campaign_id IS NOT NULL THEN st.campaign_id || '|' || CAST(st.date AS STRING) END) as matched_combinations,
  ROUND(COUNT(DISTINCT CASE WHEN pp.campaign_id IS NOT NULL THEN st.campaign_id || '|' || CAST(st.date AS STRING) END) * 100.0 / 
        NULLIF(COUNT(DISTINCT st.campaign_id || '|' || CAST(st.date AS STRING)), 0), 2) as match_percentage
FROM `onyga-482313.OI.V_SRC_AmazonAds_SearchTerms` st
LEFT JOIN `onyga-482313.OI.V_SRC_AmazonAds_purchased_product` pp
  ON st.campaign_id = pp.campaign_id
  AND st.date = pp.date;

-- =============================================
-- 5. ASIN Extraction from search_term
-- =============================================
SELECT 
  'ASIN Extraction from search_term' as match_type,
  COUNT(*) as total_search_terms,
  COUNT(CASE WHEN REGEXP_CONTAINS(UPPER(search_term), r'^B[0-9A-Z]{9}$') THEN 1 END) as direct_asin_matches,
  COUNT(CASE WHEN REGEXP_CONTAINS(UPPER(search_term), r'^ASIN') THEN 1 END) as asin_prefix_matches,
  COUNT(CASE WHEN REGEXP_CONTAINS(UPPER(search_term), r'B[0-9A-Z]{9}') THEN 1 END) as asin_anywhere_in_term,
  ROUND(COUNT(CASE WHEN REGEXP_CONTAINS(UPPER(search_term), r'^B[0-9A-Z]{9}$') THEN 1 END) * 100.0 / NULLIF(COUNT(*), 0), 2) as direct_asin_percentage,
  ROUND(COUNT(CASE WHEN REGEXP_CONTAINS(UPPER(search_term), r'B[0-9A-Z]{9}') THEN 1 END) * 100.0 / NULLIF(COUNT(*), 0), 2) as any_asin_percentage
FROM `onyga-482313.OI.V_SRC_AmazonAds_SearchTerms`
WHERE search_term IS NOT NULL;

-- =============================================
-- 6. Combined Matching: Purchased Product + ASIN Extraction
-- =============================================
WITH searchterm_with_extracted_asin AS (
  SELECT 
    st.*,
    CASE 
      WHEN REGEXP_CONTAINS(UPPER(st.search_term), r'^B[0-9A-Z]{9}$') 
      THEN REGEXP_EXTRACT(UPPER(st.search_term), r'^(B[0-9A-Z]{9})$')
      WHEN REGEXP_CONTAINS(UPPER(st.search_term), r'^ASIN[:\s]*(B[0-9A-Z]{9})')
      THEN REGEXP_EXTRACT(UPPER(st.search_term), r'^ASIN[:\s]*(B[0-9A-Z]{9})')
      WHEN REGEXP_CONTAINS(UPPER(st.search_term), r'B[0-9A-Z]{9}')
      THEN REGEXP_EXTRACT(UPPER(st.search_term), r'(B[0-9A-Z]{9})')
      ELSE NULL
    END as extracted_asin
  FROM `onyga-482313.OI.V_SRC_AmazonAds_SearchTerms` st
),
purchased_product_aggregated AS (
  SELECT 
    campaign_id,
    ad_group_id,
    keyword_id,
    date,
    -- Prioritize advertised_asin over purchased_asin
    MAX(CASE WHEN advertised_asin IS NOT NULL AND advertised_asin != 'Unknown' THEN advertised_asin END) as primary_asin,
    STRING_AGG(DISTINCT CASE WHEN purchased_asin IS NOT NULL THEN purchased_asin END, ',') as all_purchased_asins,
    STRING_AGG(DISTINCT CASE WHEN advertised_asin IS NOT NULL AND advertised_asin != 'Unknown' THEN advertised_asin END, ',') as all_advertised_asins
  FROM `onyga-482313.OI.V_SRC_AmazonAds_purchased_product`
  GROUP BY campaign_id, ad_group_id, keyword_id, date
)
SELECT 
  'Combined Matching Results' as metric,
  COUNT(*) as total_searchterm_records,
  
  -- Match via purchased_product
  COUNT(CASE WHEN pp.primary_asin IS NOT NULL THEN 1 END) as matched_via_purchased_product,
  ROUND(COUNT(CASE WHEN pp.primary_asin IS NOT NULL THEN 1 END) * 100.0 / NULLIF(COUNT(*), 0), 2) as purchased_product_match_pct,
  
  -- Match via ASIN extraction
  COUNT(CASE WHEN sea.extracted_asin IS NOT NULL THEN 1 END) as matched_via_extraction,
  ROUND(COUNT(CASE WHEN sea.extracted_asin IS NOT NULL THEN 1 END) * 100.0 / NULLIF(COUNT(*), 0), 2) as extraction_match_pct,
  
  -- Match via both methods
  COUNT(CASE WHEN pp.primary_asin IS NOT NULL AND sea.extracted_asin IS NOT NULL THEN 1 END) as matched_via_both,
  
  -- Total matched (either method)
  COUNT(CASE WHEN pp.primary_asin IS NOT NULL OR sea.extracted_asin IS NOT NULL THEN 1 END) as total_matched,
  ROUND(COUNT(CASE WHEN pp.primary_asin IS NOT NULL OR sea.extracted_asin IS NOT NULL THEN 1 END) * 100.0 / NULLIF(COUNT(*), 0), 2) as total_match_percentage,
  
  -- Unmatched
  COUNT(CASE WHEN pp.primary_asin IS NULL AND sea.extracted_asin IS NULL THEN 1 END) as unmatched,
  ROUND(COUNT(CASE WHEN pp.primary_asin IS NULL AND sea.extracted_asin IS NULL THEN 1 END) * 100.0 / NULLIF(COUNT(*), 0), 2) as unmatched_percentage

FROM searchterm_with_extracted_asin sea
LEFT JOIN purchased_product_aggregated pp
  ON sea.campaign_id = pp.campaign_id
  AND sea.ad_group_id = pp.ad_group_id
  AND COALESCE(sea.keyword_id, '-1') = COALESCE(pp.keyword_id, '-1')
  AND sea.date = pp.date;

-- =============================================
-- 7. Sample Matched Records (for validation)
-- =============================================
WITH searchterm_with_extracted_asin AS (
  SELECT 
    st.*,
    CASE 
      WHEN REGEXP_CONTAINS(UPPER(st.search_term), r'^B[0-9A-Z]{9}$') 
      THEN REGEXP_EXTRACT(UPPER(st.search_term), r'^(B[0-9A-Z]{9})$')
      WHEN REGEXP_CONTAINS(UPPER(st.search_term), r'^ASIN[:\s]*(B[0-9A-Z]{9})')
      THEN REGEXP_EXTRACT(UPPER(st.search_term), r'^ASIN[:\s]*(B[0-9A-Z]{9})')
      WHEN REGEXP_CONTAINS(UPPER(st.search_term), r'B[0-9A-Z]{9}')
      THEN REGEXP_EXTRACT(UPPER(st.search_term), r'(B[0-9A-Z]{9})')
      ELSE NULL
    END as extracted_asin
  FROM `onyga-482313.OI.V_SRC_AmazonAds_SearchTerms` st
),
purchased_product_aggregated AS (
  SELECT 
    campaign_id,
    ad_group_id,
    keyword_id,
    date,
    MAX(CASE WHEN advertised_asin IS NOT NULL AND advertised_asin != 'Unknown' THEN advertised_asin END) as primary_asin,
    STRING_AGG(DISTINCT CASE WHEN purchased_asin IS NOT NULL THEN purchased_asin END, ',') as all_purchased_asins
  FROM `onyga-482313.OI.V_SRC_AmazonAds_purchased_product`
  GROUP BY campaign_id, ad_group_id, keyword_id, date
)
SELECT 
  sea.date,
  sea.campaign_id,
  sea.ad_group_id,
  sea.keyword_id,
  sea.search_term,
  sea.clicks,
  sea.impressions,
  sea.cost,
  sea.extracted_asin,
  pp.primary_asin as purchased_product_asin,
  pp.all_purchased_asins,
  CASE 
    WHEN sea.extracted_asin IS NOT NULL AND pp.primary_asin IS NOT NULL 
      AND sea.extracted_asin = pp.primary_asin THEN 'Both Match'
    WHEN sea.extracted_asin IS NOT NULL AND pp.primary_asin IS NOT NULL 
      AND sea.extracted_asin != pp.primary_asin THEN 'Both Different'
    WHEN sea.extracted_asin IS NOT NULL THEN 'Extraction Only'
    WHEN pp.primary_asin IS NOT NULL THEN 'Purchased Product Only'
    ELSE 'No Match'
  END as match_status
FROM searchterm_with_extracted_asin sea
LEFT JOIN purchased_product_aggregated pp
  ON sea.campaign_id = pp.campaign_id
  AND sea.ad_group_id = pp.ad_group_id
  AND COALESCE(sea.keyword_id, '-1') = COALESCE(pp.keyword_id, '-1')
  AND sea.date = pp.date
WHERE sea.extracted_asin IS NOT NULL OR pp.primary_asin IS NOT NULL
ORDER BY sea.date DESC, sea.clicks DESC
LIMIT 50;
