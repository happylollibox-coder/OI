-- =============================================
-- Explore ASIN Tables: SQP_ASIN_View_Simple_Week and SCP_ASIN_View_Week
-- =============================================
-- Purpose: Data exploration queries for ASIN performance tables
-- Project: onyga-482313
-- Dataset: OI
-- =============================================

-- ==========================================
-- 1. TABLE SCHEMA EXPLORATION
-- ==========================================

-- Get schema for SQP_ASIN_View_Simple_Week
SELECT 
    column_name,
    data_type,
    is_nullable,
    column_default
FROM `onyga-482313.OI.INFORMATION_SCHEMA.COLUMNS`
WHERE table_name = 'SQP_ASIN_View_Simple_Week'
ORDER BY ordinal_position;

-- Get schema for SCP_ASIN_View_Week (if it exists)
SELECT 
    column_name,
    data_type,
    is_nullable,
    column_default
FROM `onyga-482313.OI.INFORMATION_SCHEMA.COLUMNS`
WHERE table_name = 'SCP_ASIN_View_Week'
ORDER BY ordinal_position;

-- ==========================================
-- 2. DATA VOLUME AND DATE RANGES
-- ==========================================

-- Row counts and date ranges for SQP_ASIN_View_Simple_Week
SELECT 
    'SQP_ASIN_View_Simple_Week' as table_name,
    COUNT(*) as total_rows,
    COUNT(DISTINCT SKU) as unique_skus,
    COUNT(DISTINCT Year) as unique_years,
    COUNT(DISTINCT Week) as unique_weeks,
    MIN(PARSE_DATE('%d/%m/%Y', Week_Start_date)) as earliest_week_start,
    MAX(PARSE_DATE('%d/%m/%Y', Week_End_date)) as latest_week_end,
    MIN(PARSE_DATE('%d/%m/%Y', Reporting_Date)) as earliest_reporting_date,
    MAX(PARSE_DATE('%d/%m/%Y', Reporting_Date)) as latest_reporting_date
FROM `onyga-482313.OI.SQP_ASIN_View_Simple_Week`;

-- Row counts and date ranges for SCP_ASIN_View_Week (if it exists)
SELECT 
    'SCP_ASIN_View_Week' as table_name,
    COUNT(*) as total_rows,
    COUNT(DISTINCT ASIN) as unique_asins,
    COUNT(DISTINCT Year) as unique_years,
    COUNT(DISTINCT Week) as unique_weeks,
    MIN(PARSE_DATE('%d/%m/%Y', Start_date)) as earliest_week_start,
    MAX(PARSE_DATE('%d/%m/%Y', End_Date)) as latest_week_end,
    MIN(PARSE_DATE('%d/%m/%Y', Reporting_Date)) as earliest_reporting_date,
    MAX(PARSE_DATE('%d/%m/%Y', Reporting_Date)) as latest_reporting_date
FROM `onyga-482313.OI.SCP_ASIN_View_Week`;

-- ==========================================
-- 3. SAMPLE DATA - SQP_ASIN_View_Simple_Week
-- ==========================================

-- Top 20 rows from SQP_ASIN_View_Simple_Week (most recent reporting date)
SELECT *
FROM `onyga-482313.OI.SQP_ASIN_View_Simple_Week`
ORDER BY PARSE_DATE('%d/%m/%Y', Reporting_Date) DESC, SKU, Search_Query
LIMIT 20;

-- Sample data by SKU
SELECT *
FROM `onyga-482313.OI.SQP_ASIN_View_Simple_Week`
WHERE SKU = (SELECT SKU FROM `onyga-482313.OI.SQP_ASIN_View_Simple_Week` LIMIT 1)
ORDER BY Year DESC, Week DESC, Search_Query
LIMIT 10;

-- ==========================================
-- 4. SAMPLE DATA - SCP_ASIN_View_Week
-- ==========================================

-- Top 20 rows from SCP_ASIN_View_Week (most recent reporting date)
SELECT *
FROM `onyga-482313.OI.SCP_ASIN_View_Week`
ORDER BY PARSE_DATE('%d/%m/%Y', Reporting_Date) DESC, ASIN
LIMIT 20;

-- Sample data by ASIN
SELECT *
FROM `onyga-482313.OI.SCP_ASIN_View_Week`
WHERE ASIN = (SELECT ASIN FROM `onyga-482313.OI.SCP_ASIN_View_Week` WHERE ASIN IS NOT NULL LIMIT 1)
ORDER BY Year DESC, Week DESC
LIMIT 10;

-- ==========================================
-- 5. SUMMARY STATISTICS - SQP_ASIN_View_Simple_Week
-- ==========================================

-- Performance metrics by week
SELECT 
    Year,
    Week,
    PARSE_DATE('%d/%m/%Y', Week_Start_date) as week_start,
    COUNT(DISTINCT SKU) as sku_count,
    COUNT(DISTINCT Search_Query) as search_query_count,
    SUM(Impressions_Total_Count) as total_impressions,
    SUM(Clicks_Total_Count) as total_clicks,
    SUM(Cart_Adds_Total_Count) as total_cart_adds,
    SUM(Purchases_Total_Count) as total_purchases,
    ROUND(SAFE_DIVIDE(SUM(Clicks_Total_Count), SUM(Impressions_Total_Count)) * 100, 2) as overall_ctr_pct,
    ROUND(SAFE_DIVIDE(SUM(Purchases_Total_Count), SUM(Clicks_Total_Count)) * 100, 2) as overall_conversion_pct
FROM `onyga-482313.OI.SQP_ASIN_View_Simple_Week`
GROUP BY Year, Week, Week_Start_date
ORDER BY Year DESC, Week DESC
LIMIT 20;

-- Top SKUs by total purchases
SELECT 
    SKU,
    COUNT(DISTINCT Search_Query) as search_queries,
    SUM(Impressions_Total_Count) as total_impressions,
    SUM(Clicks_Total_Count) as total_clicks,
    SUM(Purchases_Total_Count) as total_purchases,
    ROUND(SAFE_DIVIDE(SUM(Purchases_Total_Count), SUM(Clicks_Total_Count)) * 100, 2) as conversion_rate_pct
FROM `onyga-482313.OI.SQP_ASIN_View_Simple_Week`
GROUP BY SKU
ORDER BY total_purchases DESC
LIMIT 20;

-- Top search queries by purchases
SELECT 
    Search_Query,
    COUNT(DISTINCT SKU) as sku_count,
    SUM(Impressions_Total_Count) as total_impressions,
    SUM(Clicks_Total_Count) as total_clicks,
    SUM(Purchases_Total_Count) as total_purchases,
    ROUND(SAFE_DIVIDE(SUM(Purchases_Total_Count), SUM(Clicks_Total_Count)) * 100, 2) as conversion_rate_pct
FROM `onyga-482313.OI.SQP_ASIN_View_Simple_Week`
GROUP BY Search_Query
ORDER BY total_purchases DESC
LIMIT 20;

-- ==========================================
-- 6. SUMMARY STATISTICS - SCP_ASIN_View_Week
-- ==========================================

-- Performance metrics by week
SELECT 
    Year,
    Week,
    PARSE_DATE('%d/%m/%Y', Start_date) as week_start,
    COUNT(DISTINCT ASIN) as asin_count,
    SUM(Impressions_Impressions) as total_impressions,
    SUM(Clicks_Clicks) as total_clicks,
    SUM(Cart_Adds_Cart_Adds) as total_cart_adds,
    SUM(Purchases_Purchases) as total_purchases,
    ROUND(AVG(Clicks_Click_Rate_CTR), 2) as avg_ctr_pct,
    ROUND(AVG(Purchases_Conversion_Rate_Percent), 2) as avg_conversion_pct,
    SUM(Purchases_Search_Traffic_Sales) as total_sales
FROM `onyga-482313.OI.SCP_ASIN_View_Week`
GROUP BY Year, Week, Start_date
ORDER BY Year DESC, Week DESC
LIMIT 20;

-- Top ASINs by purchases
SELECT 
    ASIN,
    ASIN_Title,
    Category,
    SUM(Impressions_Impressions) as total_impressions,
    SUM(Clicks_Clicks) as total_clicks,
    SUM(Purchases_Purchases) as total_purchases,
    SUM(Purchases_Search_Traffic_Sales) as total_sales,
    ROUND(AVG(Purchases_Conversion_Rate_Percent), 2) as avg_conversion_pct,
    ROUND(AVG(Purchases_Price_Median), 2) as avg_price
FROM `onyga-482313.OI.SCP_ASIN_View_Week`
WHERE ASIN IS NOT NULL
GROUP BY ASIN, ASIN_Title, Category
ORDER BY total_purchases DESC
LIMIT 20;

-- Performance by category
SELECT 
    Category,
    COUNT(DISTINCT ASIN) as asin_count,
    SUM(Impressions_Impressions) as total_impressions,
    SUM(Clicks_Clicks) as total_clicks,
    SUM(Purchases_Purchases) as total_purchases,
    SUM(Purchases_Search_Traffic_Sales) as total_sales,
    ROUND(SAFE_DIVIDE(SUM(Purchases_Purchases), SUM(Clicks_Clicks)) * 100, 2) as conversion_rate_pct
FROM `onyga-482313.OI.SCP_ASIN_View_Week`
WHERE Category IS NOT NULL
GROUP BY Category
ORDER BY total_purchases DESC;

-- ==========================================
-- 7. DATA QUALITY CHECKS
-- ==========================================

-- Check for missing values in SQP_ASIN_View_Simple_Week
SELECT 
    'SQP_ASIN_View_Simple_Week' as table_name,
    COUNT(*) as total_rows,
    COUNTIF(SKU IS NULL) as null_sku,
    COUNTIF(Search_Query IS NULL) as null_search_query,
    COUNTIF(Year IS NULL) as null_year,
    COUNTIF(Week IS NULL) as null_week,
    COUNTIF(Reporting_Date IS NULL) as null_reporting_date
FROM `onyga-482313.OI.SQP_ASIN_View_Simple_Week`;

-- Check for missing values in SCP_ASIN_View_Week
SELECT 
    'SCP_ASIN_View_Week' as table_name,
    COUNT(*) as total_rows,
    COUNTIF(ASIN IS NULL) as null_asin,
    COUNTIF(Year IS NULL) as null_year,
    COUNTIF(Week IS NULL) as null_week,
    COUNTIF(Reporting_Date IS NULL) as null_reporting_date
FROM `onyga-482313.OI.SCP_ASIN_View_Week`;

-- ==========================================
-- 8. COMPARISON BETWEEN TABLES
-- ==========================================

-- Compare date ranges (if both tables exist)
SELECT 
    'SQP_ASIN_View_Simple_Week' as table_name,
    MIN(PARSE_DATE('%d/%m/%Y', Reporting_Date)) as earliest_date,
    MAX(PARSE_DATE('%d/%m/%Y', Reporting_Date)) as latest_date,
    COUNT(DISTINCT Year || '-' || Week) as unique_week_keys
FROM `onyga-482313.OI.SQP_ASIN_View_Simple_Week`
UNION ALL
SELECT 
    'SCP_ASIN_View_Week' as table_name,
    MIN(PARSE_DATE('%d/%m/%Y', Reporting_Date)) as earliest_date,
    MAX(PARSE_DATE('%d/%m/%Y', Reporting_Date)) as latest_date,
    COUNT(DISTINCT Year || '-' || Week) as unique_week_keys
FROM `onyga-482313.OI.SCP_ASIN_View_Week`;
