-- =============================================
-- Show Per Campaign Products Matching for January 2026
-- =============================================
-- Purpose: Display which advertised_asins match per campaign for specific dates

-- =============================================
-- 1. Available Dates in January 2026
-- =============================================
SELECT DISTINCT 
  date,
  COUNT(*) as search_term_records,
  COUNT(DISTINCT campaign_id) as unique_campaigns
FROM `onyga-482313.OI.V_SRC_AmazonAds_SearchTerms`
WHERE date >= '2026-01-01' AND date < '2026-02-01'
GROUP BY date
ORDER BY date DESC;

-- =============================================
-- 2. Per Campaign Products for a Specific Date
-- =============================================
-- Change the date in the WHERE clause to see different dates
WITH purchased_product_aggregated AS (
  SELECT 
    campaign_id,
    date,
    MAX(CASE WHEN advertised_asin IS NOT NULL AND advertised_asin != 'Unknown' 
        THEN advertised_asin END) as primary_advertised_asin,
    STRING_AGG(DISTINCT CASE WHEN advertised_asin IS NOT NULL AND advertised_asin != 'Unknown' 
             THEN advertised_asin END, ', ') as all_advertised_asins,
    COUNT(DISTINCT CASE WHEN advertised_asin IS NOT NULL AND advertised_asin != 'Unknown' 
          THEN advertised_asin END) as num_unique_advertised_asins,
    SUM(orders) as total_orders,
    SUM(sales) as total_sales
  FROM `onyga-482313.OI.V_SRC_AmazonAds_purchased_product`
  WHERE date >= '2026-01-01' AND date < '2026-02-01'
  GROUP BY campaign_id, date
),
search_terms_summary AS (
  SELECT 
    st.campaign_id,
    st.date,
    COUNT(*) as search_term_count,
    COUNT(DISTINCT st.search_term) as unique_search_terms,
    SUM(st.clicks) as total_clicks,
    SUM(st.impressions) as total_impressions,
    SUM(st.cost) as total_cost,
    SUM(st.orders) as total_orders_from_search,
    SUM(st.sales) as total_sales_from_search
  FROM `onyga-482313.OI.V_SRC_AmazonAds_SearchTerms` st
  WHERE st.date >= '2026-01-01' AND st.date < '2026-02-01'
  GROUP BY st.campaign_id, st.date
)
SELECT 
  st.date,
  st.campaign_id,
  c.campaign_name,
  c.campaign_type,
  
  -- Search Terms Stats
  st.search_term_count,
  st.unique_search_terms,
  st.total_clicks,
  st.total_impressions,
  st.total_cost,
  st.total_orders_from_search,
  st.total_sales_from_search,
  
  -- Product (ASIN) Information
  pp.primary_advertised_asin,
  pp.all_advertised_asins,
  pp.num_unique_advertised_asins,
  pp.total_orders as product_orders,
  pp.total_sales as product_sales,
  
  -- Match Status
  CASE 
    WHEN pp.primary_advertised_asin IS NOT NULL THEN 'Matched'
    ELSE 'No Match'
  END as match_status

FROM search_terms_summary st
LEFT JOIN purchased_product_aggregated pp
  ON st.campaign_id = pp.campaign_id
  AND st.date = pp.date
LEFT JOIN `onyga-482313.OI.V_SRC_AmazonAds_campaign_history` c
  ON st.campaign_id = c.campaign_id
  AND TIMESTAMP(st.date) BETWEEN c.OI_start_date AND c.OI_end_date
ORDER BY st.date DESC, st.total_clicks DESC;

-- =============================================
-- 3. Detailed View: Search Terms with Products for Specific Date
-- =============================================
-- Shows individual search terms and their matched products
-- Change the date filter to see different dates
WITH purchased_product_aggregated AS (
  SELECT 
    campaign_id,
    date,
    MAX(CASE WHEN advertised_asin IS NOT NULL AND advertised_asin != 'Unknown' 
        THEN advertised_asin END) as primary_advertised_asin,
    STRING_AGG(DISTINCT CASE WHEN advertised_asin IS NOT NULL AND advertised_asin != 'Unknown' 
             THEN advertised_asin END, ', ') as all_advertised_asins,
    COUNT(DISTINCT CASE WHEN advertised_asin IS NOT NULL AND advertised_asin != 'Unknown' 
          THEN advertised_asin END) as num_unique_advertised_asins
  FROM `onyga-482313.OI.V_SRC_AmazonAds_purchased_product`
  WHERE date >= '2026-01-01' AND date < '2026-02-01'
  GROUP BY campaign_id, date
)
SELECT 
  st.date,
  st.campaign_id,
  c.campaign_name,
  st.ad_group_id,
  st.keyword_id,
  st.search_term,
  st.clicks,
  st.impressions,
  st.cost,
  st.orders,
  st.sales,
  
  -- Matched Products
  pp.primary_advertised_asin,
  pp.all_advertised_asins,
  pp.num_unique_advertised_asins,
  
  CASE 
    WHEN pp.primary_advertised_asin IS NOT NULL THEN 'Matched'
    ELSE 'No Match'
  END as match_status

FROM `onyga-482313.OI.V_SRC_AmazonAds_SearchTerms` st
LEFT JOIN purchased_product_aggregated pp
  ON st.campaign_id = pp.campaign_id
  AND st.date = pp.date
LEFT JOIN `onyga-482313.OI.V_SRC_AmazonAds_campaign_history` c
  ON st.campaign_id = c.campaign_id
  AND TIMESTAMP(st.date) BETWEEN c.OI_start_date AND c.OI_end_date
WHERE st.date >= '2026-01-01' AND st.date < '2026-02-01'
  AND pp.primary_advertised_asin IS NOT NULL  -- Only show matched records
ORDER BY st.date DESC, st.clicks DESC
LIMIT 100;

-- =============================================
-- 4. Campaign Summary: Products per Campaign for January 2026
-- =============================================
WITH purchased_product_aggregated AS (
  SELECT 
    campaign_id,
    date,
    MAX(CASE WHEN advertised_asin IS NOT NULL AND advertised_asin != 'Unknown' 
        THEN advertised_asin END) as primary_advertised_asin,
    STRING_AGG(DISTINCT CASE WHEN advertised_asin IS NOT NULL AND advertised_asin != 'Unknown' 
             THEN advertised_asin END, ', ') as all_advertised_asins,
    COUNT(DISTINCT CASE WHEN advertised_asin IS NOT NULL AND advertised_asin != 'Unknown' 
          THEN advertised_asin END) as num_unique_advertised_asins
  FROM `onyga-482313.OI.V_SRC_AmazonAds_purchased_product`
  WHERE date >= '2026-01-01' AND date < '2026-02-01'
  GROUP BY campaign_id, date
),
campaign_products AS (
  SELECT 
    st.campaign_id,
    st.date,
    pp.all_advertised_asins,
    pp.num_unique_advertised_asins
  FROM `onyga-482313.OI.V_SRC_AmazonAds_SearchTerms` st
  INNER JOIN purchased_product_aggregated pp
    ON st.campaign_id = pp.campaign_id
    AND st.date = pp.date
  WHERE st.date >= '2026-01-01' AND st.date < '2026-02-01'
  GROUP BY st.campaign_id, st.date, pp.all_advertised_asins, pp.num_unique_advertised_asins
)
SELECT 
  cp.date,
  cp.campaign_id,
  c.campaign_name,
  c.campaign_type,
  cp.all_advertised_asins as products_advertised,
  cp.num_unique_advertised_asins as num_products,
  COUNT(DISTINCT st.search_term) as unique_search_terms,
  SUM(st.clicks) as total_clicks,
  SUM(st.impressions) as total_impressions,
  SUM(st.cost) as total_cost
FROM campaign_products cp
LEFT JOIN `onyga-482313.OI.V_SRC_AmazonAds_SearchTerms` st
  ON cp.campaign_id = st.campaign_id
  AND cp.date = st.date
LEFT JOIN `onyga-482313.OI.V_SRC_AmazonAds_campaign_history` c
  ON cp.campaign_id = c.campaign_id
  AND TIMESTAMP(cp.date) BETWEEN c.OI_start_date AND c.OI_end_date
GROUP BY cp.date, cp.campaign_id, c.campaign_name, c.campaign_type, 
         cp.all_advertised_asins, cp.num_unique_advertised_asins
ORDER BY cp.date DESC, total_clicks DESC;
