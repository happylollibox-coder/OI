-- =============================================
-- Correlation Analysis: Organic vs Paid Search Performance
-- =============================================
--
-- Purpose: Find correlations between FACT_AMAZON_SEARCH_PERFORMANCE_WEEKLY (organic)
--          and V_AMAZON_ADS_TOP_SEARCH_QUERY_TERMS_WEEKLY (paid) to identify
--          unique search terms that can improve organic sales per ASIN
--
-- Project: onyga-482313
-- Dataset: OI
--
-- =============================================

-- ==========================================
-- PHASE 1: DATA EXPLORATION & VALIDATION
-- ==========================================

-- 1.1 Date Range Check
SELECT 
  'FACT_AMAZON_SEARCH_PERFORMANCE_WEEKLY' AS source,
  MIN(Reporting_Date) AS min_date,
  MAX(Reporting_Date) AS max_date,
  COUNT(DISTINCT Reporting_Date) AS distinct_weeks,
  COUNT(*) AS total_records,
  COUNT(DISTINCT ASIN) AS distinct_asins,
  COUNT(DISTINCT Search_Query) AS distinct_search_queries
FROM `onyga-482313.OI.FACT_AMAZON_SEARCH_PERFORMANCE_WEEKLY`

UNION ALL

SELECT 
  'V_AMAZON_ADS_TOP_SEARCH_QUERY_TERMS_WEEKLY' AS source,
  MIN(week_end_date) AS min_date,
  MAX(week_end_date) AS max_date,
  COUNT(DISTINCT week_end_date) AS distinct_weeks,
  COUNT(*) AS total_records,
  COUNT(DISTINCT asin) AS distinct_asins,
  COUNT(DISTINCT search_term) AS distinct_search_queries
FROM `onyga-482313.OI.V_AMAZON_ADS_TOP_SEARCH_QUERY_TERMS_WEEKLY`;

-- 1.2 NULL Search Query Analysis (Organic)
SELECT 
  COUNT(*) AS total_records,
  COUNT(Search_Query) AS records_with_search_query,
  COUNT(*) - COUNT(Search_Query) AS records_with_null_search_query,
  ROUND((COUNT(*) - COUNT(Search_Query)) / COUNT(*) * 100, 2) AS pct_null_search_query
FROM `onyga-482313.OI.FACT_AMAZON_SEARCH_PERFORMANCE_WEEKLY`;

-- 1.3 ASIN Overlap Analysis
WITH organic_asins AS (
  SELECT DISTINCT ASIN
  FROM `onyga-482313.OI.FACT_AMAZON_SEARCH_PERFORMANCE_WEEKLY`
  WHERE ASIN IS NOT NULL
),
paid_asins AS (
  SELECT DISTINCT asin
  FROM `onyga-482313.OI.V_AMAZON_ADS_TOP_SEARCH_QUERY_TERMS_WEEKLY`
  WHERE asin IS NOT NULL
)
SELECT 
  COUNT(DISTINCT o.ASIN) AS organic_only_asins,
  COUNT(DISTINCT p.asin) AS paid_only_asins,
  COUNT(DISTINCT o.ASIN) + COUNT(DISTINCT p.asin) - COUNT(DISTINCT COALESCE(o.ASIN, p.asin)) AS overlapping_asins,
  COUNT(DISTINCT COALESCE(o.ASIN, p.asin)) AS total_unique_asins
FROM organic_asins o
FULL OUTER JOIN paid_asins p ON o.ASIN = p.asin;

-- ==========================================
-- PHASE 2: CORRELATION ANALYSIS
-- ==========================================

-- 2.1 Matched Search Terms: Direct Comparison
WITH matched_terms AS (
  SELECT 
    -- Date alignment: Using week_end_date as common key
    -- NOTE: Verify if Reporting_Date aligns with week_end_date
    COALESCE(org.Reporting_Date, paid.week_end_date) AS report_date,
    COALESCE(org.ASIN, paid.asin) AS asin,
    COALESCE(org.Search_Query, paid.search_term) AS search_term,
    
    -- Organic metrics
    COALESCE(org.Impressions, 0) AS organic_impressions,
    COALESCE(org.Clicks, 0) AS organic_clicks,
    COALESCE(org.ORDERS, 0) AS organic_orders,
    COALESCE(org.AMAZON_ORDERS, 0) AS organic_amazon_orders,
    COALESCE(org.Search_Query_Score, 0) AS organic_search_score,
    CASE 
      WHEN COALESCE(org.Impressions, 0) > 0 
      THEN COALESCE(org.Clicks, 0) / org.Impressions 
      ELSE 0 
    END AS organic_ctr,
    CASE 
      WHEN COALESCE(org.Clicks, 0) > 0 
      THEN COALESCE(org.ORDERS, 0) / org.Clicks 
      ELSE 0 
    END AS organic_conversion_rate,
    
    -- Paid metrics
    COALESCE(paid.impressions, 0) AS paid_impressions,
    COALESCE(paid.clicks, 0) AS paid_clicks,
    COALESCE(paid.orders, 0) AS paid_orders,
    COALESCE(paid.units, 0) AS paid_units,
    paid.campaign_type,
    paid.inferred_sales_module,
    CASE 
      WHEN COALESCE(paid.impressions, 0) > 0 
      THEN COALESCE(paid.clicks, 0) / paid.impressions 
      ELSE 0 
    END AS paid_ctr,
    CASE 
      WHEN COALESCE(paid.clicks, 0) > 0 
      THEN COALESCE(paid.orders, 0) / paid.clicks 
      ELSE 0 
    END AS paid_conversion_rate
    
  FROM `onyga-482313.OI.FACT_AMAZON_SEARCH_PERFORMANCE_WEEKLY` org
  FULL OUTER JOIN `onyga-482313.OI.V_AMAZON_ADS_TOP_SEARCH_QUERY_TERMS_WEEKLY` paid
    ON org.Reporting_Date = paid.week_end_date
    AND org.ASIN = paid.asin
    AND UPPER(TRIM(COALESCE(org.Search_Query, ''))) = UPPER(TRIM(COALESCE(paid.search_term, '')))
  WHERE 
    -- Filter out NULL search terms for meaningful analysis
    (org.Search_Query IS NOT NULL OR paid.search_term IS NOT NULL)
    AND (org.ASIN IS NOT NULL OR paid.asin IS NOT NULL)
)
SELECT 
  report_date,
  asin,
  search_term,
  organic_impressions,
  organic_clicks,
  organic_orders,
  organic_ctr,
  organic_conversion_rate,
  paid_impressions,
  paid_clicks,
  paid_orders,
  paid_ctr,
  paid_conversion_rate,
  -- Gap analysis
  paid_impressions - organic_impressions AS impression_gap,
  paid_orders - organic_orders AS order_gap,
  paid_conversion_rate - organic_conversion_rate AS conversion_rate_gap,
  -- Opportunity indicators
  CASE 
    WHEN organic_orders = 0 AND paid_orders > 0 THEN 'High Opportunity - No Organic'
    WHEN organic_orders > 0 AND paid_orders > organic_orders * 2 THEN 'High Opportunity - Paid Dominant'
    WHEN organic_conversion_rate > paid_conversion_rate * 1.5 THEN 'Efficiency Opportunity - Organic Better'
    ELSE 'Monitor'
  END AS opportunity_category
FROM matched_terms
ORDER BY 
  (paid_orders * paid_conversion_rate) DESC,  -- Prioritize high-performing paid terms
  organic_orders ASC;  -- With low organic presence

-- ==========================================
-- PHASE 3: OPPORTUNITY IDENTIFICATION
-- ==========================================

-- 3.1 Unique Paid Terms (No Organic Presence) - TOP OPPORTUNITIES
WITH paid_terms AS (
  SELECT 
    paid.week_end_date,
    paid.asin,
    paid.search_term,
    SUM(paid.impressions) AS total_paid_impressions,
    SUM(paid.clicks) AS total_paid_clicks,
    SUM(paid.orders) AS total_paid_orders,
    SUM(paid.units) AS total_paid_units,
    COUNT(DISTINCT paid.week_end_date) AS weeks_active,
    AVG(CASE WHEN paid.clicks > 0 THEN paid.orders / paid.clicks ELSE 0 END) AS avg_paid_conversion_rate,
    MAX(paid.inferred_sales_module) AS sales_module
  FROM `onyga-482313.OI.V_AMAZON_ADS_TOP_SEARCH_QUERY_TERMS_WEEKLY` paid
  WHERE paid.search_term IS NOT NULL
    AND paid.asin IS NOT NULL
    -- Filter out ASIN patterns (B + 9 alphanumeric) - these are product page visits
    AND NOT REGEXP_CONTAINS(UPPER(paid.search_term), r'^B[0-9A-Z]{9}$')
    AND NOT REGEXP_CONTAINS(UPPER(paid.search_term), r'^ASIN')
  GROUP BY 1, 2, 3
),
organic_terms AS (
  SELECT DISTINCT
    org.Reporting_Date,
    org.ASIN,
    org.Search_Query
  FROM `onyga-482313.OI.FACT_AMAZON_SEARCH_PERFORMANCE_WEEKLY` org
  WHERE org.Search_Query IS NOT NULL
    AND org.ASIN IS NOT NULL
)
SELECT 
  pt.asin,
  pt.search_term,
  pt.total_paid_impressions,
  pt.total_paid_clicks,
  pt.total_paid_orders,
  pt.total_paid_units,
  pt.weeks_active,
  pt.avg_paid_conversion_rate,
  pt.sales_module,
  -- Opportunity Score: Higher = Better investment opportunity
  (pt.total_paid_orders * 0.4 + 
   pt.avg_paid_conversion_rate * 100 * 0.3 + 
   pt.total_paid_impressions / 1000 * 0.2 + 
   pt.weeks_active * 0.1) AS opportunity_score
FROM paid_terms pt
LEFT JOIN organic_terms ot
  ON pt.week_end_date = ot.Reporting_Date
  AND pt.asin = ot.ASIN
  AND UPPER(TRIM(pt.search_term)) = UPPER(TRIM(ot.Search_Query))
WHERE ot.Search_Query IS NULL  -- No organic presence
  AND pt.total_paid_orders > 0  -- Has actual sales
ORDER BY opportunity_score DESC
LIMIT 100;

-- 3.2 ASIN-Level Opportunity Summary
WITH paid_summary AS (
  SELECT 
    asin,
    COUNT(DISTINCT search_term) AS unique_paid_terms,
    SUM(impressions) AS total_paid_impressions,
    SUM(clicks) AS total_paid_clicks,
    SUM(orders) AS total_paid_orders,
    SUM(units) AS total_paid_units,
    AVG(CASE WHEN clicks > 0 THEN orders / clicks ELSE 0 END) AS avg_paid_conversion_rate
  FROM `onyga-482313.OI.V_AMAZON_ADS_TOP_SEARCH_QUERY_TERMS_WEEKLY`
  WHERE asin IS NOT NULL
    AND search_term IS NOT NULL
    AND NOT REGEXP_CONTAINS(UPPER(search_term), r'^B[0-9A-Z]{9}$')
    AND NOT REGEXP_CONTAINS(UPPER(search_term), r'^ASIN')
  GROUP BY asin
),
organic_summary AS (
  SELECT 
    ASIN,
    COUNT(DISTINCT Search_Query) AS unique_organic_terms,
    SUM(Impressions) AS total_organic_impressions,
    SUM(Clicks) AS total_organic_clicks,
    SUM(ORDERS) AS total_organic_orders,
    AVG(CASE WHEN Clicks > 0 THEN ORDERS / Clicks ELSE 0 END) AS avg_organic_conversion_rate
  FROM `onyga-482313.OI.FACT_AMAZON_SEARCH_PERFORMANCE_WEEKLY`
  WHERE ASIN IS NOT NULL
    AND Search_Query IS NOT NULL
  GROUP BY ASIN
)
SELECT 
  COALESCE(p.asin, o.ASIN) AS asin,
  COALESCE(p.unique_paid_terms, 0) AS unique_paid_terms,
  COALESCE(o.unique_organic_terms, 0) AS unique_organic_terms,
  COALESCE(p.total_paid_orders, 0) AS total_paid_orders,
  COALESCE(o.total_organic_orders, 0) AS total_organic_orders,
  COALESCE(p.avg_paid_conversion_rate, 0) AS avg_paid_conversion_rate,
  COALESCE(o.avg_organic_conversion_rate, 0) AS avg_organic_conversion_rate,
  -- Gap metrics
  COALESCE(p.total_paid_orders, 0) - COALESCE(o.total_organic_orders, 0) AS order_gap,
  COALESCE(p.unique_paid_terms, 0) - COALESCE(o.unique_organic_terms, 0) AS term_gap,
  -- Investment priority score
  (COALESCE(p.total_paid_orders, 0) * 0.5 + 
   (COALESCE(p.unique_paid_terms, 0) - COALESCE(o.unique_organic_terms, 0)) * 0.3 +
   COALESCE(p.avg_paid_conversion_rate, 0) * 100 * 0.2) AS investment_priority_score
FROM paid_summary p
FULL OUTER JOIN organic_summary o ON p.asin = o.ASIN
WHERE COALESCE(p.total_paid_orders, 0) > 0  -- Has paid activity
ORDER BY investment_priority_score DESC
LIMIT 50;

-- ==========================================
-- PHASE 4: STATISTICAL CORRELATION
-- ==========================================

-- 4.1 Correlation Coefficients (Requires aggregation by search term)
WITH term_performance AS (
  SELECT 
    COALESCE(org.ASIN, paid.asin) AS asin,
    COALESCE(org.Search_Query, paid.search_term) AS search_term,
    SUM(COALESCE(org.Impressions, 0)) AS total_organic_impressions,
    SUM(COALESCE(org.ORDERS, 0)) AS total_organic_orders,
    SUM(COALESCE(paid.impressions, 0)) AS total_paid_impressions,
    SUM(COALESCE(paid.orders, 0)) AS total_paid_orders,
    AVG(CASE WHEN COALESCE(org.Clicks, 0) > 0 THEN COALESCE(org.ORDERS, 0) / org.Clicks ELSE 0 END) AS avg_organic_cvr,
    AVG(CASE WHEN COALESCE(paid.clicks, 0) > 0 THEN COALESCE(paid.orders, 0) / paid.clicks ELSE 0 END) AS avg_paid_cvr
  FROM `onyga-482313.OI.FACT_AMAZON_SEARCH_PERFORMANCE_WEEKLY` org
  FULL OUTER JOIN `onyga-482313.OI.V_AMAZON_ADS_TOP_SEARCH_QUERY_TERMS_WEEKLY` paid
    ON org.Reporting_Date = paid.week_end_date
    AND org.ASIN = paid.asin
    AND UPPER(TRIM(COALESCE(org.Search_Query, ''))) = UPPER(TRIM(COALESCE(paid.search_term, '')))
  WHERE (org.Search_Query IS NOT NULL OR paid.search_term IS NOT NULL)
    AND (org.ASIN IS NOT NULL OR paid.asin IS NOT NULL)
  GROUP BY 1, 2
  HAVING total_organic_impressions > 0 OR total_paid_impressions > 0
)
SELECT 
  -- Pearson correlation approximation using statistical functions
  COUNT(*) AS sample_size,
  AVG(total_organic_impressions) AS avg_organic_impressions,
  AVG(total_paid_impressions) AS avg_paid_impressions,
  AVG(total_organic_orders) AS avg_organic_orders,
  AVG(total_paid_orders) AS avg_paid_orders,
  STDDEV(total_organic_impressions) AS stddev_organic_impressions,
  STDDEV(total_paid_impressions) AS stddev_paid_impressions,
  -- Correlation calculation (simplified - for full correlation use CORR function)
  CORR(CAST(total_organic_impressions AS FLOAT64), CAST(total_paid_impressions AS FLOAT64)) AS correlation_impressions,
  CORR(CAST(total_organic_orders AS FLOAT64), CAST(total_paid_orders AS FLOAT64)) AS correlation_orders,
  CORR(avg_organic_cvr, avg_paid_cvr) AS correlation_conversion_rate
FROM term_performance
WHERE total_organic_impressions > 0 AND total_paid_impressions > 0;
