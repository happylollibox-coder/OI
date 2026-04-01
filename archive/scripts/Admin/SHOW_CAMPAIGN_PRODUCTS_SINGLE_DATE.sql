-- =============================================
-- Show Per Campaign Products for ONE Specific Date
-- =============================================
-- Change the date in the WHERE clause to see different dates
-- Example: '2026-01-29', '2026-01-28', etc.

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
  WHERE date = '2026-01-29'  -- CHANGE THIS DATE
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
  WHERE st.date = '2026-01-29'  -- CHANGE THIS DATE
  GROUP BY st.campaign_id, st.date
)
SELECT 
  st.date,
  st.campaign_id,
  c.campaign_name,
  c.campaign_type,
  
  -- Search Terms Performance
  st.search_term_count,
  st.unique_search_terms,
  st.total_clicks,
  st.total_impressions,
  ROUND(st.total_cost, 2) as total_cost,
  st.total_orders_from_search,
  ROUND(st.total_sales_from_search, 2) as total_sales_from_search,
  
  -- Product (ASIN) Information
  pp.primary_advertised_asin as advertised_asin,
  pp.all_advertised_asins as all_advertised_asins,
  pp.num_unique_advertised_asins as num_products,
  pp.total_orders as product_orders,
  ROUND(pp.total_sales, 2) as product_sales,
  
  -- Match Status
  CASE 
    WHEN pp.primary_advertised_asin IS NOT NULL THEN '✅ Matched'
    ELSE '❌ No Match'
  END as match_status

FROM search_terms_summary st
LEFT JOIN purchased_product_aggregated pp
  ON st.campaign_id = pp.campaign_id
  AND st.date = pp.date
LEFT JOIN `onyga-482313.OI.V_SRC_AmazonAds_campaign_history` c
  ON st.campaign_id = c.campaign_id
  AND TIMESTAMP(st.date) BETWEEN c.OI_start_date AND c.OI_end_date
ORDER BY 
  CASE WHEN pp.primary_advertised_asin IS NOT NULL THEN 0 ELSE 1 END,  -- Matched first
  st.total_clicks DESC;
