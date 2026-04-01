-- =============================================
-- FIND SEARCH TERMS: 5 Paid Clicks = 1 Order (Paid or Organic)
-- =============================================
-- Purpose: Identify search terms where 5 paid clicks result in 1 total order
--          (either from paid ads or organic search)
--          This enables creating campaigns with exact conversion rules
--
-- Target Ratio: 1 order per 5 paid clicks = 20% conversion rate
-- Project: onyga-482313
-- Dataset: OI
-- =============================================

WITH weekly_term_data AS (
  SELECT 
    COALESCE(org.Reporting_Date, paid.week_end_date) AS week_end_date,
    COALESCE(org.ASIN, paid.asin) AS asin,
    UPPER(TRIM(COALESCE(org.Search_Query, paid.search_term))) AS normalized_search_term,
    
    -- Paid metrics
    SUM(COALESCE(paid.clicks, 0)) AS paid_clicks,
    SUM(COALESCE(paid.orders, 0)) AS paid_orders,
    SUM(COALESCE(paid.impressions, 0)) AS paid_impressions,
    SUM(COALESCE(paid.units, 0)) AS paid_units,
    
    -- Organic metrics
    SUM(COALESCE(org.Clicks, 0)) AS organic_clicks,
    SUM(COALESCE(org.ORDERS, 0)) AS organic_orders,
    SUM(COALESCE(org.Impressions, 0)) AS organic_impressions,
    
    -- Campaign context
    MAX(paid.campaign_type) AS campaign_type,
    MAX(paid.inferred_sales_module) AS sales_module
    
  FROM `onyga-482313.OI.FACT_AMAZON_SEARCH_PERFORMANCE_WEEKLY` org
  FULL OUTER JOIN `onyga-482313.OI.V_AMAZON_ADS_TOP_SEARCH_QUERY_TERMS_WEEKLY` paid
    ON org.Reporting_Date = paid.week_end_date
    AND org.ASIN = paid.asin
    AND UPPER(TRIM(COALESCE(org.Search_Query, ''))) = UPPER(TRIM(COALESCE(paid.search_term, '')))
  WHERE 
    (org.Search_Query IS NOT NULL OR paid.search_term IS NOT NULL)
    AND (org.ASIN IS NOT NULL OR paid.asin IS NOT NULL)
    AND NOT REGEXP_CONTAINS(UPPER(TRIM(COALESCE(org.Search_Query, paid.search_term, ''))), r'^B[0-9A-Z]{9}$')
    AND NOT REGEXP_CONTAINS(UPPER(TRIM(COALESCE(org.Search_Query, paid.search_term, ''))), r'^ASIN')
  GROUP BY 1, 2, 3
),

term_aggregates AS (
  SELECT 
    asin,
    normalized_search_term AS search_term,
    campaign_type,
    sales_module,
    
    -- Total metrics
    SUM(paid_clicks) AS total_paid_clicks,
    SUM(paid_orders) AS total_paid_orders,
    SUM(organic_orders) AS total_organic_orders,
    SUM(paid_orders + organic_orders) AS total_combined_orders,
    SUM(paid_impressions) AS total_paid_impressions,
    SUM(organic_impressions) AS total_organic_impressions,
    SUM(paid_units) AS total_paid_units,
    
    -- Count weeks
    COUNT(DISTINCT week_end_date) AS weeks_active,
    
    -- KEY METRIC: Orders per Paid Click
    CASE 
      WHEN SUM(paid_clicks) > 0 
      THEN SUM(paid_orders + organic_orders) / SUM(paid_clicks)
      ELSE 0
    END AS orders_per_paid_click,
    
    -- Target ratio: 1 order per 5 clicks = 0.2
    CASE 
      WHEN SUM(paid_clicks) > 0 
      THEN SUM(paid_orders + organic_orders) / SUM(paid_clicks) >= 0.2
      ELSE FALSE
    END AS meets_5_to_1_ratio,
    
    -- Conversion rates
    CASE 
      WHEN SUM(paid_clicks) > 0 
      THEN SUM(paid_orders) / SUM(paid_clicks)
      ELSE 0
    END AS paid_cvr,
    
    CASE 
      WHEN SUM(organic_clicks) > 0 
      THEN SUM(organic_orders) / SUM(organic_clicks)
      ELSE 0
    END AS organic_cvr,
    
    -- Efficiency metrics
    CASE 
      WHEN SUM(paid_clicks) >= 5 
      THEN ROUND(SUM(paid_orders + organic_orders) / SUM(paid_clicks) * 100, 2)
      ELSE 0
    END AS combined_conversion_rate_pct,
    
    -- How many clicks needed for 1 order
    CASE 
      WHEN SUM(paid_orders + organic_orders) > 0 
      THEN ROUND(SUM(paid_clicks) / SUM(paid_orders + organic_orders), 2)
      ELSE NULL
    END AS clicks_per_order
    
  FROM weekly_term_data
  GROUP BY 1, 2, 3, 4
  HAVING 
    SUM(paid_clicks) >= 5  -- Minimum 5 paid clicks for meaningful analysis
    AND SUM(paid_orders + organic_orders) > 0  -- Must have at least 1 order
)

SELECT 
  asin,
  search_term,
  campaign_type,
  sales_module,
  
  -- Performance metrics
  total_paid_clicks,
  total_paid_orders,
  total_organic_orders,
  total_combined_orders,
  total_paid_impressions,
  total_paid_units,
  weeks_active,
  
  -- KEY METRICS FOR CAMPAIGN RULES
  ROUND(orders_per_paid_click, 4) AS orders_per_paid_click,
  ROUND(orders_per_paid_click * 100, 2) AS conversion_rate_pct,
  clicks_per_order,
  meets_5_to_1_ratio,
  
  -- Individual conversion rates
  ROUND(paid_cvr, 4) AS paid_conversion_rate,
  ROUND(organic_cvr, 4) AS organic_conversion_rate,
  
  -- Efficiency indicators
  CASE 
    WHEN orders_per_paid_click >= 0.2 THEN '✅ MEETS TARGET (5:1)'
    WHEN orders_per_paid_click >= 0.15 THEN '💡 CLOSE TO TARGET (6.7:1)'
    WHEN orders_per_paid_click >= 0.1 THEN '📊 MODERATE (10:1)'
    ELSE '❌ BELOW TARGET'
  END AS efficiency_status,
  
  -- Campaign rule recommendation
  CASE 
    WHEN orders_per_paid_click >= 0.2 AND total_paid_clicks >= 20 THEN 'INCREASE BID - Exceeds target'
    WHEN orders_per_paid_click >= 0.2 AND total_paid_clicks < 20 THEN 'MAINTAIN BID - Meets target, test scale'
    WHEN orders_per_paid_click >= 0.15 AND total_paid_clicks >= 15 THEN 'OPTIMIZE - Close to target'
    WHEN orders_per_paid_click >= 0.1 THEN 'MONITOR - Below target'
    ELSE 'PAUSE - Low efficiency'
  END AS campaign_action,
  
  -- Value score (higher = better for campaign rules)
  ROUND((
    orders_per_paid_click * 100 * 0.5 +  -- Conversion efficiency (most important)
    LEAST(total_combined_orders, 50) * 0.3 +  -- Total orders (capped at 50)
    LEAST(weeks_active, 10) * 0.2  -- Consistency (capped at 10)
  ), 2) AS campaign_rule_score,
  
  -- Organic contribution
  ROUND(total_organic_orders / NULLIF(total_combined_orders, 0) * 100, 2) AS pct_orders_from_organic,
  
  -- Insight
  CASE 
    WHEN orders_per_paid_click >= 0.2 AND total_organic_orders > total_paid_orders THEN '🔥 EXCELLENT - Paid clicks driving organic orders'
    WHEN orders_per_paid_click >= 0.2 THEN '✅ STRONG - Meets 5:1 ratio'
    WHEN orders_per_paid_click >= 0.15 THEN '💡 GOOD - Close to target'
    WHEN total_organic_orders > total_paid_orders * 2 THEN '💡 OPPORTUNITY - Strong organic lift'
    ELSE '📊 MONITOR'
  END AS insight
  
FROM term_aggregates
WHERE 
  total_paid_clicks >= 5  -- Minimum 5 clicks for analysis
ORDER BY 
  -- Prioritize terms that meet or exceed the 5:1 ratio
  CASE 
    WHEN orders_per_paid_click >= 0.2 THEN 0
    WHEN orders_per_paid_click >= 0.15 THEN 1
    WHEN orders_per_paid_click >= 0.1 THEN 2
    ELSE 3
  END,
  campaign_rule_score DESC,
  total_combined_orders DESC
LIMIT 500;

-- ==========================================
-- SUMMARY: Campaign Rules by Performance Tier
-- ==========================================

WITH term_performance AS (
  SELECT 
    asin,
    normalized_search_term AS search_term,
    SUM(paid_clicks) AS total_paid_clicks,
    SUM(paid_orders + organic_orders) AS total_combined_orders,
    CASE 
      WHEN SUM(paid_clicks) > 0 
      THEN SUM(paid_orders + organic_orders) / SUM(paid_clicks)
      ELSE 0
    END AS orders_per_paid_click,
    COUNT(DISTINCT week_end_date) AS weeks_active
  FROM (
    SELECT 
      COALESCE(org.Reporting_Date, paid.week_end_date) AS week_end_date,
      COALESCE(org.ASIN, paid.asin) AS asin,
      UPPER(TRIM(COALESCE(org.Search_Query, paid.search_term))) AS normalized_search_term,
      SUM(COALESCE(paid.clicks, 0)) AS paid_clicks,
      SUM(COALESCE(paid.orders, 0)) AS paid_orders,
      SUM(COALESCE(org.ORDERS, 0)) AS organic_orders
    FROM `onyga-482313.OI.FACT_AMAZON_SEARCH_PERFORMANCE_WEEKLY` org
    FULL OUTER JOIN `onyga-482313.OI.V_AMAZON_ADS_TOP_SEARCH_QUERY_TERMS_WEEKLY` paid
      ON org.Reporting_Date = paid.week_end_date
      AND org.ASIN = paid.asin
      AND UPPER(TRIM(COALESCE(org.Search_Query, ''))) = UPPER(TRIM(COALESCE(paid.search_term, '')))
    WHERE 
      (org.Search_Query IS NOT NULL OR paid.search_term IS NOT NULL)
      AND (org.ASIN IS NOT NULL OR paid.asin IS NOT NULL)
      AND NOT REGEXP_CONTAINS(UPPER(TRIM(COALESCE(org.Search_Query, paid.search_term, ''))), r'^B[0-9A-Z]{9}$')
      AND NOT REGEXP_CONTAINS(UPPER(TRIM(COALESCE(org.Search_Query, paid.search_term, ''))), r'^ASIN')
    GROUP BY 1, 2, 3
  )
  GROUP BY 1, 2
  HAVING SUM(paid_clicks) >= 5
)
SELECT 
  'CAMPAIGN RULES SUMMARY' AS analysis_type,
  COUNT(*) AS total_terms_analyzed,
  
  -- Terms meeting 5:1 ratio
  COUNT(CASE WHEN orders_per_paid_click >= 0.2 THEN 1 END) AS terms_meeting_5_to_1,
  ROUND(COUNT(CASE WHEN orders_per_paid_click >= 0.2 THEN 1 END) / COUNT(*) * 100, 2) AS pct_meeting_target,
  
  -- Terms close to target
  COUNT(CASE WHEN orders_per_paid_click >= 0.15 AND orders_per_paid_click < 0.2 THEN 1 END) AS terms_close_to_target,
  
  -- Average performance
  ROUND(AVG(orders_per_paid_click), 4) AS avg_orders_per_click,
  ROUND(AVG(orders_per_paid_click) * 100, 2) AS avg_conversion_rate_pct,
  ROUND(AVG(1.0 / NULLIF(orders_per_paid_click, 0)), 2) AS avg_clicks_per_order,
  
  -- Best performers
  MAX(orders_per_paid_click) AS best_orders_per_click,
  MAX(orders_per_paid_click) * 100 AS best_conversion_rate_pct,
  
  -- Total volume
  SUM(total_paid_clicks) AS total_paid_clicks_all_terms,
  SUM(total_combined_orders) AS total_combined_orders_all_terms,
  ROUND(SUM(total_combined_orders) / SUM(total_paid_clicks), 4) AS overall_orders_per_click
  
FROM term_performance;
