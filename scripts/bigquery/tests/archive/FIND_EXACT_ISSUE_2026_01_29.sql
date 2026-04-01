-- =============================================
-- Find Exact Issue: Jan 29, 2026 Sales Discrepancy
-- =============================================
-- This query will identify the exact source of the $545.6 difference
-- =============================================

-- 1. Check if SUM vs MAX is the issue - compare grouped results
WITH unpivoted AS (
  SELECT 
    date,
    campaign_id,
    ad_group_id,
    keyword_id,
    search_term,
    asin,
    sales
  FROM `onyga-482313.OI.STG_AMAZON_ADS`
  UNPIVOT (asin FOR measure_type IN (
    most_advertised_asin_purchased AS 'purchased'
  ))
  WHERE date = '2026-01-29'
    AND asin IS NOT NULL
    AND measure_type = 'purchased'
),
grouped_max AS (
  SELECT 
    date,
    campaign_id,
    campaign_name,
    campaign_type,
    inferred_sales_module,
    ad_group_id,
    keyword_id,
    ad_keyword_status,
    targeting,
    search_term,
    placement_type,
    advertised_asins,
    advertised_asins_count,
    asin,
    _fivetran_synced,
    source_table,
    MAX(sales) AS sales_max
  FROM unpivoted u
  JOIN `onyga-482313.OI.STG_AMAZON_ADS` s
    ON u.date = s.date
    AND u.campaign_id = s.campaign_id
    AND u.ad_group_id = s.ad_group_id
    AND u.keyword_id = s.keyword_id
    AND u.search_term = s.search_term
    AND u.asin = s.most_advertised_asin_purchased
  GROUP BY 
    date, campaign_id, campaign_name, campaign_type, inferred_sales_module,
    ad_group_id, keyword_id, ad_keyword_status, targeting, search_term,
    placement_type, advertised_asins, advertised_asins_count, asin,
    _fivetran_synced, source_table
),
grouped_sum AS (
  SELECT 
    date,
    campaign_id,
    campaign_name,
    campaign_type,
    inferred_sales_module,
    ad_group_id,
    keyword_id,
    ad_keyword_status,
    targeting,
    search_term,
    placement_type,
    advertised_asins,
    advertised_asins_count,
    asin,
    _fivetran_synced,
    source_table,
    SUM(COALESCE(sales, 0)) AS sales_sum
  FROM unpivoted u
  JOIN `onyga-482313.OI.STG_AMAZON_ADS` s
    ON u.date = s.date
    AND u.campaign_id = s.campaign_id
    AND u.ad_group_id = s.ad_group_id
    AND u.keyword_id = s.keyword_id
    AND u.search_term = s.search_term
    AND u.asin = s.most_advertised_asin_purchased
  GROUP BY 
    date, campaign_id, campaign_name, campaign_type, inferred_sales_module,
    ad_group_id, keyword_id, ad_keyword_status, targeting, search_term,
    placement_type, advertised_asins, advertised_asins_count, asin,
    _fivetran_synced, source_table
)
SELECT 
  'SUM vs MAX Comparison' AS check_type,
  SUM(sales_max) AS total_with_max,
  SUM(sales_sum) AS total_with_sum,
  SUM(sales_sum) - SUM(sales_max) AS difference,
  COUNT(*) AS record_count
FROM grouped_max gm
FULL OUTER JOIN grouped_sum gs
  ON gm.date = gs.date
  AND gm.campaign_id = gs.campaign_id
  AND gm.ad_group_id = gs.ad_group_id
  AND gm.keyword_id = gs.keyword_id
  AND gm.search_term = gs.search_term
  AND gm.asin = gs.asin;

-- 2. Check for duplicates in STG_AMAZON_ADS that would cause issues
SELECT 
  'Duplicates in STG_AMAZON_ADS' AS check_type,
  date,
  campaign_id,
  ad_group_id,
  keyword_id,
  search_term,
  most_advertised_asin_purchased,
  COUNT(*) AS duplicate_count,
  SUM(sales) AS total_sales,
  MAX(sales) AS max_sales,
  MIN(sales) AS min_sales,
  SUM(sales) - MAX(sales) AS lost_with_max
FROM `onyga-482313.OI.STG_AMAZON_ADS`
WHERE date = '2026-01-29'
  AND most_advertised_asin_purchased IS NOT NULL
GROUP BY 
  date, campaign_id, ad_group_id, keyword_id, search_term, most_advertised_asin_purchased
HAVING COUNT(*) > 1
ORDER BY lost_with_max DESC;

-- 3. Check actual FACT table totals
SELECT 
  'FACT Table Current State' AS check_type,
  SUM(sales) AS total_sales,
  SUM(CASE WHEN Performance_TYPE = 'Ads' THEN sales ELSE 0 END) AS ads_sales,
  SUM(CASE WHEN Performance_TYPE = 'Organic' THEN sales ELSE 0 END) AS organic_sales,
  COUNT(*) AS total_records,
  COUNT(DISTINCT most_advertised_asin) AS distinct_asins
FROM `onyga-482313.OI.FACT_AMAZON_PERFORMANCE_DAILY`
WHERE date = '2026-01-29';

-- 4. Check source totals
SELECT 
  'Source Totals' AS check_type,
  'STG_AMAZON_PERFORMANCE' AS source,
  SUM(SALES_AMOUNT) AS total_sales
FROM `onyga-482313.OI.STG_AMAZON_PERFORMANCE`
WHERE date = '2026-01-29' AND IS_LOADED = TRUE

UNION ALL

SELECT 
  'Source Totals',
  'STG_AMAZON_ADS (all sales)',
  SUM(sales) AS total_sales
FROM `onyga-482313.OI.STG_AMAZON_ADS`
WHERE date = '2026-01-29'
  AND most_advertised_asin_purchased IS NOT NULL

UNION ALL

SELECT 
  'Source Totals',
  'STG_AMAZON_ADS (aggregated by ASIN)',
  SUM(ads_sales) AS total_sales
FROM (
  SELECT 
    most_advertised_asin_purchased AS asin,
    SUM(sales) AS ads_sales
  FROM `onyga-482313.OI.STG_AMAZON_ADS`
  WHERE date = '2026-01-29'
    AND most_advertised_asin_purchased IS NOT NULL
  GROUP BY most_advertised_asin_purchased
);

-- 5. Check if UNPIVOT is creating the issue - count rows before and after
SELECT 
  'UNPIVOT Row Count' AS check_type,
  'Before UNPIVOT (STG_AMAZON_ADS)' AS stage,
  COUNT(*) AS row_count,
  SUM(sales) AS total_sales
FROM `onyga-482313.OI.STG_AMAZON_ADS`
WHERE date = '2026-01-29'
  AND most_advertised_asin_purchased IS NOT NULL

UNION ALL

SELECT 
  'UNPIVOT Row Count',
  'After UNPIVOT (purchased only)',
  COUNT(*) AS row_count,
  SUM(sales) AS total_sales
FROM `onyga-482313.OI.STG_AMAZON_ADS`
UNPIVOT (asin FOR measure_type IN (
  most_advertised_asin_purchased AS 'purchased'
))
WHERE date = '2026-01-29'
  AND asin IS NOT NULL
  AND measure_type = 'purchased';

-- 6. Check if same ASIN appears in multiple columns (impressions, clicks, purchased)
SELECT 
  'ASIN in Multiple Columns' AS check_type,
  date,
  campaign_id,
  ad_group_id,
  keyword_id,
  search_term,
  most_advertised_asin_impressions AS asin,
  'impressions' AS column_type,
  NULL AS sales
FROM `onyga-482313.OI.STG_AMAZON_ADS`
WHERE date = '2026-01-29'
  AND most_advertised_asin_impressions IS NOT NULL

UNION ALL

SELECT 
  'ASIN in Multiple Columns',
  date,
  campaign_id,
  ad_group_id,
  keyword_id,
  search_term,
  most_advertised_asin_clicks AS asin,
  'clicks' AS column_type,
  NULL AS sales
FROM `onyga-482313.OI.STG_AMAZON_ADS`
WHERE date = '2026-01-29'
  AND most_advertised_asin_clicks IS NOT NULL

UNION ALL

SELECT 
  'ASIN in Multiple Columns',
  date,
  campaign_id,
  ad_group_id,
  keyword_id,
  search_term,
  most_advertised_asin_purchased AS asin,
  'purchased' AS column_type,
  sales
FROM `onyga-482313.OI.STG_AMAZON_ADS`
WHERE date = '2026-01-29'
  AND most_advertised_asin_purchased IS NOT NULL;

-- 7. Check what happens when we group the UNPIVOTed data
WITH unpivoted_all AS (
  SELECT 
    date,
    campaign_id,
    campaign_name,
    campaign_type,
    inferred_sales_module,
    ad_group_id,
    keyword_id,
    ad_keyword_status,
    targeting,
    search_term,
    placement_type,
    advertised_asins,
    advertised_asins_count,
    _fivetran_synced,
    source_table,
    asin,
    CASE WHEN measure_type = 'impressions' THEN impressions ELSE NULL END AS impressions,
    CASE WHEN measure_type = 'clicks' THEN clicks ELSE NULL END AS clicks,
    CASE WHEN measure_type = 'purchased' THEN orders ELSE NULL END AS orders,
    CASE WHEN measure_type = 'purchased' THEN units ELSE NULL END AS units,
    CASE WHEN measure_type = 'purchased' THEN cost ELSE NULL END AS cost,
    CASE WHEN measure_type = 'purchased' THEN sales ELSE NULL END AS sales
  FROM `onyga-482313.OI.STG_AMAZON_ADS`
  UNPIVOT (asin FOR measure_type IN (
    most_advertised_asin_impressions AS 'impressions',
    most_advertised_asin_clicks AS 'clicks',
    most_advertised_asin_purchased AS 'purchased'
  ))
  WHERE date = '2026-01-29'
    AND asin IS NOT NULL
)
SELECT 
  'Grouped UNPIVOT Results' AS check_type,
  COUNT(*) AS grouped_rows,
  SUM(COALESCE(sales, 0)) AS total_sales_with_sum,
  SUM(MAX(sales)) AS total_sales_with_max_wrong,  -- This is wrong but shows the issue
  COUNT(DISTINCT asin) AS distinct_asins
FROM (
  SELECT 
    date,
    campaign_id,
    campaign_name,
    campaign_type,
    inferred_sales_module,
    ad_group_id,
    keyword_id,
    ad_keyword_status,
    targeting,
    search_term,
    placement_type,
    advertised_asins,
    advertised_asins_count,
    asin,
    _fivetran_synced,
    source_table,
    MAX(impressions) AS impressions,
    MAX(clicks) AS clicks,
    MAX(orders) AS orders,
    MAX(units) AS units,
    MAX(cost) AS cost,
    sales  -- Keep individual sales values
  FROM unpivoted_all
  GROUP BY 
    date, campaign_id, campaign_name, campaign_type, inferred_sales_module,
    ad_group_id, keyword_id, ad_keyword_status, targeting, search_term,
    placement_type, advertised_asins, advertised_asins_count, asin,
    _fivetran_synced, source_table, sales
);

-- 8. Most important: Find ASINs where SUM != MAX (the problematic ones)
WITH unpivoted_purchased AS (
  SELECT 
    date,
    campaign_id,
    ad_group_id,
    keyword_id,
    search_term,
    asin,
    sales
  FROM `onyga-482313.OI.STG_AMAZON_ADS`
  UNPIVOT (asin FOR measure_type IN (
    most_advertised_asin_purchased AS 'purchased'
  ))
  WHERE date = '2026-01-29'
    AND asin IS NOT NULL
    AND measure_type = 'purchased'
),
grouped_data AS (
  SELECT 
    date,
    campaign_id,
    campaign_name,
    campaign_type,
    inferred_sales_module,
    ad_group_id,
    keyword_id,
    ad_keyword_status,
    targeting,
    search_term,
    placement_type,
    advertised_asins,
    advertised_asins_count,
    asin,
    _fivetran_synced,
    source_table,
    COUNT(*) AS source_row_count,
    SUM(sales) AS sum_sales,
    MAX(sales) AS max_sales,
    SUM(sales) - MAX(sales) AS difference
  FROM unpivoted_purchased u
  JOIN `onyga-482313.OI.STG_AMAZON_ADS` s
    ON u.date = s.date
    AND u.campaign_id = s.campaign_id
    AND u.ad_group_id = s.ad_group_id
    AND u.keyword_id = s.keyword_id
    AND u.search_term = s.search_term
    AND u.asin = s.most_advertised_asin_purchased
  GROUP BY 
    date, campaign_id, campaign_name, campaign_type, inferred_sales_module,
    ad_group_id, keyword_id, ad_keyword_status, targeting, search_term,
    placement_type, advertised_asins, advertised_asins_count, asin,
    _fivetran_synced, source_table
  HAVING COUNT(*) > 1  -- Only show where there are multiple rows
)
SELECT 
  'Problematic ASINs (SUM != MAX)' AS check_type,
  asin,
  SUM(sum_sales) AS total_with_sum,
  SUM(max_sales) AS total_with_max,
  SUM(difference) AS total_lost_with_max,
  COUNT(*) AS affected_groups
FROM grouped_data
WHERE difference > 0
GROUP BY asin
ORDER BY total_lost_with_max DESC;
