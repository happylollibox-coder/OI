-- =============================================
-- CAMPAIGN RULES BY ASIN: 5 Clicks to 1 Order Analysis
-- =============================================
-- Purpose: Find ASINs that consistently achieve 5 paid clicks = 1 order
--          Enables creating ASIN-level campaign rules
--
-- Project: onyga-482313
-- Dataset: OI
-- =============================================

WITH asin_weekly AS (
  SELECT 
    COALESCE(org.Reporting_Date, paid.week_end_date) AS week_end_date,
    COALESCE(org.ASIN, paid.asin) AS asin,
    SUM(COALESCE(paid.clicks, 0)) AS paid_clicks,
    SUM(COALESCE(paid.orders, 0)) AS paid_orders,
    SUM(COALESCE(org.ORDERS, 0)) AS organic_orders,
    SUM(COALESCE(paid.impressions, 0)) AS paid_impressions,
    SUM(COALESCE(paid.units, 0)) AS paid_units,
    COUNT(DISTINCT UPPER(TRIM(COALESCE(org.Search_Query, paid.search_term)))) AS unique_search_terms
  FROM `onyga-482313.OI.FACT_AMAZON_SEARCH_PERFORMANCE_WEEKLY` org
  FULL OUTER JOIN `onyga-482313.OI.V_AMAZON_ADS_TOP_SEARCH_QUERY_TERMS_WEEKLY` paid
    ON org.Reporting_Date = paid.week_end_date
    AND org.ASIN = paid.asin
  WHERE 
    (org.ASIN IS NOT NULL OR paid.asin IS NOT NULL)
    AND (org.Search_Query IS NOT NULL OR paid.search_term IS NOT NULL)
    AND NOT REGEXP_CONTAINS(UPPER(TRIM(COALESCE(org.Search_Query, paid.search_term, ''))), r'^B[0-9A-Z]{9}$')
    AND NOT REGEXP_CONTAINS(UPPER(TRIM(COALESCE(org.Search_Query, paid.search_term, ''))), r'^ASIN')
  GROUP BY 1, 2
),

asin_aggregates AS (
  SELECT 
    asin,
    SUM(paid_clicks) AS total_paid_clicks,
    SUM(paid_orders) AS total_paid_orders,
    SUM(organic_orders) AS total_organic_orders,
    SUM(paid_orders + organic_orders) AS total_combined_orders,
    SUM(paid_impressions) AS total_paid_impressions,
    SUM(paid_units) AS total_paid_units,
    COUNT(DISTINCT week_end_date) AS weeks_active,
    AVG(unique_search_terms) AS avg_search_terms_per_week,
    
    -- KEY METRIC: Orders per Paid Click
    CASE 
      WHEN SUM(paid_clicks) > 0 
      THEN SUM(paid_orders + organic_orders) / SUM(paid_clicks)
      ELSE 0
    END AS orders_per_paid_click,
    
    -- Conversion rates
    CASE 
      WHEN SUM(paid_clicks) > 0 
      THEN SUM(paid_orders) / SUM(paid_clicks)
      ELSE 0
    END AS paid_cvr,
    
    -- Consistency: How many weeks meet 5:1 ratio
    COUNT(CASE 
      WHEN paid_clicks >= 5 
        AND (paid_orders + organic_orders) / NULLIF(paid_clicks, 0) >= 0.2 
      THEN 1 
    END) AS weeks_meeting_5_to_1,
    
    -- Average clicks per order
    CASE 
      WHEN SUM(paid_orders + organic_orders) > 0 
      THEN ROUND(SUM(paid_clicks) / SUM(paid_orders + organic_orders), 2)
      ELSE NULL
    END AS avg_clicks_per_order
    
  FROM asin_weekly
  GROUP BY asin
  HAVING 
    SUM(paid_clicks) >= 25  -- Minimum 25 clicks for ASIN-level analysis
    AND SUM(paid_orders + organic_orders) > 0
)

SELECT 
  asin,
  
  -- Performance metrics
  total_paid_clicks,
  total_paid_orders,
  total_organic_orders,
  total_combined_orders,
  total_paid_impressions,
  total_paid_units,
  weeks_active,
  ROUND(avg_search_terms_per_week, 1) AS avg_search_terms_per_week,
  
  -- KEY METRICS FOR CAMPAIGN RULES
  ROUND(orders_per_paid_click, 4) AS orders_per_paid_click,
  ROUND(orders_per_paid_click * 100, 2) AS conversion_rate_pct,
  avg_clicks_per_order,
  weeks_meeting_5_to_1,
  ROUND(weeks_meeting_5_to_1 / weeks_active * 100, 2) AS pct_weeks_meeting_target,
  
  -- Individual rates
  ROUND(paid_cvr, 4) AS paid_conversion_rate,
  
  -- Efficiency status
  CASE 
    WHEN orders_per_paid_click >= 0.2 THEN '✅ MEETS TARGET (5:1)'
    WHEN orders_per_paid_click >= 0.15 THEN '💡 CLOSE TO TARGET (6.7:1)'
    WHEN orders_per_paid_click >= 0.1 THEN '📊 MODERATE (10:1)'
    ELSE '❌ BELOW TARGET'
  END AS efficiency_status,
  
  -- Consistency indicator
  CASE 
    WHEN weeks_meeting_5_to_1 >= weeks_active * 0.7 THEN '🔥 VERY CONSISTENT'
    WHEN weeks_meeting_5_to_1 >= weeks_active * 0.5 THEN '✅ CONSISTENT'
    WHEN weeks_meeting_5_to_1 >= weeks_active * 0.3 THEN '💡 SOMETIMES'
    ELSE '📊 INCONSISTENT'
  END AS consistency_status,
  
  -- Campaign rule for this ASIN
  CASE 
    WHEN orders_per_paid_click >= 0.2 AND weeks_meeting_5_to_1 >= weeks_active * 0.7 THEN 
      'INCREASE BID - Consistently exceeds 5:1 ratio'
    WHEN orders_per_paid_click >= 0.2 THEN 
      'MAINTAIN BID - Meets 5:1 ratio'
    WHEN orders_per_paid_click >= 0.15 THEN 
      'OPTIMIZE KEYWORDS - Close to target, test improvements'
    WHEN orders_per_paid_click >= 0.1 THEN 
      'MONITOR - Below target, needs optimization'
    ELSE 
      'PAUSE/REVIEW - Low efficiency, investigate'
  END AS asin_campaign_rule,
  
  -- Value score
  ROUND((
    orders_per_paid_click * 100 * 0.4 +  -- Conversion efficiency
    (weeks_meeting_5_to_1 / NULLIF(weeks_active, 1)) * 100 * 0.3 +  -- Consistency
    LEAST(total_combined_orders, 100) * 0.2 +  -- Total orders
    LEAST(avg_search_terms_per_week, 20) * 0.1  -- Term diversity
  ), 2) AS asin_campaign_score,
  
  -- Organic contribution
  ROUND(total_organic_orders / NULLIF(total_combined_orders, 0) * 100, 2) AS pct_orders_from_organic,
  
  -- Insight
  CASE 
    WHEN orders_per_paid_click >= 0.2 AND total_organic_orders > total_paid_orders THEN 
      '🔥 EXCELLENT - Paid clicks driving strong organic orders'
    WHEN orders_per_paid_click >= 0.2 THEN 
      '✅ STRONG - Consistently meets 5:1 ratio'
    WHEN orders_per_paid_click >= 0.15 THEN 
      '💡 GOOD - Close to target, optimize to reach 5:1'
    WHEN total_organic_orders > total_paid_orders * 2 THEN 
      '💡 OPPORTUNITY - Strong organic lift from paid'
    ELSE 
      '📊 MONITOR - Needs optimization'
  END AS insight
  
FROM asin_aggregates
WHERE total_paid_clicks >= 25
ORDER BY 
  -- Prioritize ASINs that meet 5:1 ratio consistently
  CASE 
    WHEN orders_per_paid_click >= 0.2 AND weeks_meeting_5_to_1 >= weeks_active * 0.7 THEN 0
    WHEN orders_per_paid_click >= 0.2 THEN 1
    WHEN orders_per_paid_click >= 0.15 THEN 2
    ELSE 3
  END,
  asin_campaign_score DESC,
  total_combined_orders DESC
LIMIT 100;
