-- =============================================
-- Analyze ASIN Counts per campaign + ad_group + date
-- Strategy B: campaign + ad_group + date
-- =============================================
-- Purpose: Find how many ASINs exist per combination
-- Focus: One-way matching from advertised_product to search_terms

-- =============================================
-- 1. Count ASINs per campaign + ad_group + date
-- =============================================
WITH advertised_product_asin_counts AS (
  SELECT 
    campaign_id,
    ad_group_id,
    date,
    COUNT(DISTINCT advertised_asin) as num_asins,
    STRING_AGG(DISTINCT advertised_asin, ', ' ORDER BY advertised_asin) as all_asins,
    SUM(impressions) as total_impressions,
    SUM(clicks) as total_clicks,
    SUM(cost) as total_cost
  FROM `onyga-482313.OI.V_SRC_AmazonAds_advertised_product`
  WHERE campaign_id IS NOT NULL
    AND ad_group_id IS NOT NULL
    AND date IS NOT NULL
  GROUP BY campaign_id, ad_group_id, date
)
SELECT 
  ap.campaign_id,
  c.campaign_name,
  ap.ad_group_id,
  ag.ad_group_name,
  ap.date,
  ap.num_asins,
  ap.all_asins,
  ap.total_impressions,
  ap.total_clicks,
  ap.total_cost,
  -- Count how many search term records would match this combination
  COUNT(DISTINCT st.search_term) as matching_search_terms_count,
  SUM(st.clicks) as matching_searchterm_clicks,
  SUM(st.impressions) as matching_searchterm_impressions,
  SUM(st.cost) as matching_searchterm_cost
FROM advertised_product_asin_counts ap
LEFT JOIN `onyga-482313.OI.V_SRC_AmazonAds_SearchTerms` st
  ON ap.campaign_id = st.campaign_id
  AND ap.ad_group_id = st.ad_group_id
  AND ap.date = st.date
LEFT JOIN `onyga-482313.OI.V_SRC_AmazonAds_campaign_history` c
  ON ap.campaign_id = c.campaign_id
  AND TIMESTAMP(ap.date) BETWEEN c.OI_start_date AND c.OI_end_date
LEFT JOIN `onyga-482313.OI.V_SRC_AmazonAds_ad_group_history` ag
  ON ap.ad_group_id = ag.ad_group_id
  AND TIMESTAMP(ap.date) BETWEEN ag.OI_start_date AND ag.OI_end_date
GROUP BY 
  ap.campaign_id,
  c.campaign_name,
  ap.ad_group_id,
  ag.ad_group_name,
  ap.date,
  ap.num_asins,
  ap.all_asins,
  ap.total_impressions,
  ap.total_clicks,
  ap.total_cost
ORDER BY ap.num_asins DESC, ap.date DESC, ap.total_clicks DESC;

-- =============================================
-- 2. Summary: Count combinations by number of ASINs
-- =============================================
SELECT 
  COUNT(DISTINCT campaign_id || '|' || ad_group_id || '|' || CAST(date AS STRING)) as total_combinations,
  COUNT(DISTINCT CASE WHEN num_asins = 1 THEN campaign_id || '|' || ad_group_id || '|' || CAST(date AS STRING) END) as combinations_with_1_asin,
  COUNT(DISTINCT CASE WHEN num_asins = 2 THEN campaign_id || '|' || ad_group_id || '|' || CAST(date AS STRING) END) as combinations_with_2_asins,
  COUNT(DISTINCT CASE WHEN num_asins = 3 THEN campaign_id || '|' || ad_group_id || '|' || CAST(date AS STRING) END) as combinations_with_3_asins,
  COUNT(DISTINCT CASE WHEN num_asins >= 4 THEN campaign_id || '|' || ad_group_id || '|' || CAST(date AS STRING) END) as combinations_with_4plus_asins,
  COUNT(DISTINCT CASE WHEN num_asins > 1 THEN campaign_id || '|' || ad_group_id || '|' || CAST(date AS STRING) END) as combinations_with_multiple_asins,
  ROUND(COUNT(DISTINCT CASE WHEN num_asins > 1 THEN campaign_id || '|' || ad_group_id || '|' || CAST(date AS STRING) END) * 100.0 / 
        NULLIF(COUNT(DISTINCT campaign_id || '|' || ad_group_id || '|' || CAST(date AS STRING)), 0), 2) as pct_multiple_asins
FROM (
  SELECT 
    campaign_id,
    ad_group_id,
    date,
    COUNT(DISTINCT advertised_asin) as num_asins
  FROM `onyga-482313.OI.V_SRC_AmazonAds_advertised_product`
  WHERE campaign_id IS NOT NULL
    AND ad_group_id IS NOT NULL
    AND date IS NOT NULL
  GROUP BY campaign_id, ad_group_id, date
);

-- =============================================
-- 3. Campaigns with multiple ASINs (detailed)
-- =============================================
WITH advertised_product_asin_counts AS (
  SELECT 
    campaign_id,
    ad_group_id,
    date,
    COUNT(DISTINCT advertised_asin) as num_asins,
    STRING_AGG(DISTINCT advertised_asin, ', ' ORDER BY advertised_asin) as all_asins
  FROM `onyga-482313.OI.V_SRC_AmazonAds_advertised_product`
  WHERE campaign_id IS NOT NULL
    AND ad_group_id IS NOT NULL
    AND date IS NOT NULL
  GROUP BY campaign_id, ad_group_id, date
  HAVING COUNT(DISTINCT advertised_asin) > 1
)
SELECT DISTINCT
  ap.campaign_id,
  c.campaign_name,
  COUNT(DISTINCT ap.ad_group_id || '|' || CAST(ap.date AS STRING)) as num_adgroup_date_combinations,
  MAX(ap.num_asins) as max_asins_per_combination,
  MIN(ap.num_asins) as min_asins_per_combination,
  ROUND(AVG(ap.num_asins), 2) as avg_asins_per_combination
FROM advertised_product_asin_counts ap
LEFT JOIN `onyga-482313.OI.V_SRC_AmazonAds_campaign_history` c
  ON ap.campaign_id = c.campaign_id
  AND TIMESTAMP(ap.date) BETWEEN c.OI_start_date AND c.OI_end_date
GROUP BY ap.campaign_id, c.campaign_name
ORDER BY num_adgroup_date_combinations DESC, max_asins_per_combination DESC;

-- =============================================
-- 4. All combinations with multiple ASINs (with campaign names)
-- =============================================
WITH advertised_product_asin_counts AS (
  SELECT 
    campaign_id,
    ad_group_id,
    date,
    COUNT(DISTINCT advertised_asin) as num_asins,
    STRING_AGG(DISTINCT advertised_asin, ', ' ORDER BY advertised_asin) as all_asins,
    SUM(impressions) as total_impressions,
    SUM(clicks) as total_clicks
  FROM `onyga-482313.OI.V_SRC_AmazonAds_advertised_product`
  WHERE campaign_id IS NOT NULL
    AND ad_group_id IS NOT NULL
    AND date IS NOT NULL
  GROUP BY campaign_id, ad_group_id, date
  HAVING COUNT(DISTINCT advertised_asin) > 1
)
SELECT 
  ap.campaign_id,
  c.campaign_name,
  ap.ad_group_id,
  ag.ad_group_name,
  ap.date,
  ap.num_asins,
  ap.all_asins,
  ap.total_impressions,
  ap.total_clicks
FROM advertised_product_asin_counts ap
LEFT JOIN `onyga-482313.OI.V_SRC_AmazonAds_campaign_history` c
  ON ap.campaign_id = c.campaign_id
  AND TIMESTAMP(ap.date) BETWEEN c.OI_start_date AND c.OI_end_date
LEFT JOIN `onyga-482313.OI.V_SRC_AmazonAds_ad_group_history` ag
  ON ap.ad_group_id = ag.ad_group_id
  AND TIMESTAMP(ap.date) BETWEEN ag.OI_start_date AND ag.OI_end_date
ORDER BY ap.num_asins DESC, ap.date DESC, ap.total_clicks DESC;
