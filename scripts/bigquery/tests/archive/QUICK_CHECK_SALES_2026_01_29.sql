-- Quick Check: Sales Discrepancy Jan 29, 2026
-- Expected: $3,069 | Actual: $3,614.6 | Difference: $545.6

-- 1. Source Total
SELECT 
  'SOURCE' AS step,
  SUM(sales_by_asin_ordered_product_sales_amount) AS total_sales
FROM `fivetran-hl.amazon_selling_partner.sales_and_traffic_business_sku_report_daily`
WHERE end_date = '2026-01-29';

-- 2. STG_AMAZON_PERFORMANCE Total (LOADED)
SELECT 
  'STG_PERFORMANCE (LOADED)' AS step,
  SUM(SALES_AMOUNT) AS total_sales
FROM `onyga-482313.OI.STG_AMAZON_PERFORMANCE`
WHERE date = '2026-01-29' AND IS_LOADED = TRUE;

-- 3. STG_AMAZON_ADS Total
SELECT 
  'STG_ADS' AS step,
  SUM(sales) AS total_sales
FROM `onyga-482313.OI.STG_AMAZON_ADS`
WHERE date = '2026-01-29' AND most_advertised_asin_purchased IS NOT NULL;

-- 4. FACT_AMAZON_PERFORMANCE_DAILY Total
SELECT 
  'FACT_TABLE' AS step,
  SUM(sales) AS total_sales,
  SUM(CASE WHEN Performance_TYPE = 'Ads' THEN sales ELSE 0 END) AS ads_sales,
  SUM(CASE WHEN Performance_TYPE = 'Organic' THEN sales ELSE 0 END) AS organic_sales
FROM `onyga-482313.OI.FACT_AMAZON_PERFORMANCE_DAILY`
WHERE date = '2026-01-29';

-- 5. Check for duplicates in FACT
SELECT 
  'DUPLICATES' AS step,
  COUNT(*) AS duplicate_rows,
  SUM(sales) AS duplicate_sales
FROM (
  SELECT 
    date,
    most_advertised_asin,
    campaign_id,
    ad_group_id,
    keyword_id,
    search_term,
    Performance_TYPE,
    COUNT(*) AS cnt,
    SUM(sales) AS sales
  FROM `onyga-482313.OI.FACT_AMAZON_PERFORMANCE_DAILY`
  WHERE date = '2026-01-29'
  GROUP BY 
    date, most_advertised_asin, campaign_id, ad_group_id, keyword_id, search_term, Performance_TYPE
  HAVING COUNT(*) > 1
);

-- 6. Expected vs Actual Summary
WITH source_total AS (
  SELECT SUM(SALES_AMOUNT) AS total
  FROM `onyga-482313.OI.STG_AMAZON_PERFORMANCE`
  WHERE date = '2026-01-29' AND IS_LOADED = TRUE
),
ads_total AS (
  SELECT SUM(sales) AS total
  FROM `onyga-482313.OI.STG_AMAZON_ADS`
  WHERE date = '2026-01-29' AND most_advertised_asin_purchased IS NOT NULL
),
fact_total AS (
  SELECT SUM(sales) AS total
  FROM `onyga-482313.OI.FACT_AMAZON_PERFORMANCE_DAILY`
  WHERE date = '2026-01-29'
)
SELECT 
  'SUMMARY' AS step,
  3069.0 AS expected,
  (SELECT total FROM source_total) AS source_total,
  (SELECT total FROM ads_total) AS ads_total,
  (SELECT total FROM fact_total) AS fact_total,
  (SELECT total FROM fact_total) - 3069.0 AS difference;
