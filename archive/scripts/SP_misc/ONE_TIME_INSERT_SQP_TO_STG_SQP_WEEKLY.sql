-- =============================================
-- ONE-TIME INSERT: SQP_ASIN_View_Simple_Week to STG_SQP_WEEKLY
-- =============================================
-- Purpose: One-time data migration from SQP table to staging table
-- Maps SQP column structure to STG_SQP_WEEKLY structure
-- Project: onyga-482313
-- Dataset: OI
--
-- IMPORTANT: This is a ONE-TIME script. Run only once to migrate existing data.
-- After this, use SP_MERGE_SQP_WEEKLY for ongoing updates from OpenBridge.
-- =============================================

-- Insert data from SQP_ASIN_View_Simple_Week into STG_SQP_WEEKLY
INSERT INTO `onyga-482313.OI.STG_SQP_WEEKLY` (
  -- Primary Key Dimensions
  query_text,
  ASIN,
  Year,
  Week,
  ob_date,  -- Using Week_Start_date as the date reference
  week_start_date,
  week_end_date,
  
  -- Search Query Performance Metrics
  impressions,
  clicks,
  click_through_rate,
  cart_adds,
  conversions,
  conversion_rate,
  sales_amount,
  sales_currency_code,
  TOTAL_IMPRESSIONS,
  TOTAL_CLICKS,
  TOTAL_CART_ADDS,
  TOTAL_PURCHASES,
  query_rank,
  avg_position,
  
  -- OpenBridge Metadata (NULL for SQP data)
  ob_file_name,
  ob_marketplace_id,
  ob_seller_id,
  ob_transaction_id,
  ob_modified_date,
  ob_processed_at
)
SELECT
  -- Primary Key Dimensions
  sqp.Search_Query as query_text,
  sqp.SKU as ASIN,  -- SKU contains ASIN value
  sqp.Year,
  sqp.Week,
  sqp.Week_Start_date as ob_date,  -- Use Week_Start_date as the date reference (already DATE type)
  sqp.Week_Start_date as week_start_date,  -- Already DATE type
  sqp.Week_End_date as week_end_date,  -- Already DATE type
  
  -- Search Query Performance Metrics
  -- Using ASIN-specific metrics (your product's performance) as primary metrics
  sqp.Impressions_ASIN_Count as impressions,
  sqp.Clicks_ASIN_Count as clicks,
  -- Calculate CTR: (Clicks / Impressions) * 100
  CASE 
    WHEN sqp.Impressions_ASIN_Count > 0 
    THEN (sqp.Clicks_ASIN_Count / sqp.Impressions_ASIN_Count) * 100.0
    ELSE 0.0
  END as click_through_rate,
  sqp.Cart_Adds_ASIN_Count as cart_adds,
  sqp.Purchases_ASIN_Count as conversions,
  -- Calculate conversion rate: (Purchases / Clicks) * 100
  CASE 
    WHEN sqp.Clicks_ASIN_Count > 0 
    THEN (sqp.Purchases_ASIN_Count / sqp.Clicks_ASIN_Count) * 100.0
    ELSE 0.0
  END as conversion_rate,
  -- Sales amount: Purchases_ASIN_Count * Purchases_ASIN_Price_Median
  CASE 
    WHEN sqp.Purchases_ASIN_Count > 0 AND sqp.`Purchases_ASIN_Price_ Median` IS NOT NULL
    THEN sqp.Purchases_ASIN_Count * sqp.`Purchases_ASIN_Price_ Median`
    ELSE NULL
  END as sales_amount,
  -- Currency code: Default to 'USD' for SQP data (Amazon US marketplace - ATVPDKIKX0DER)
  -- Note: OpenBridge data will have currency_code from purchase_data_asin_median_purchase_price_currency_code
  'USD' as sales_currency_code,
  -- Total Count Metrics (across all ASINs for the query)
  sqp.Impressions_Total_Count as TOTAL_IMPRESSIONS,
  sqp.Clicks_Total_Count as TOTAL_CLICKS,
  sqp.Cart_Adds_Total_Count as TOTAL_CART_ADDS,
  sqp.Purchases_Total_Count as TOTAL_PURCHASES,
  -- Query rank/position (if available)
  CAST(NULL AS INT64) as query_rank,  -- Not available in SQP
  CAST(NULL AS FLOAT64) as avg_position,  -- Not available in SQP
  
  -- OpenBridge Metadata - All NULL for SQP data
  CAST(NULL AS STRING) as ob_file_name,
  CAST(NULL AS STRING) as ob_marketplace_id,
  CAST(NULL AS STRING) as ob_seller_id,
  CAST(NULL AS STRING) as ob_transaction_id,
  CAST(NULL AS DATETIME) as ob_modified_date,
  CAST(NULL AS STRING) as ob_processed_at

FROM `onyga-482313.OI.SQP_ASIN_View_Simple_Week` sqp
WHERE sqp.SKU IS NOT NULL
  AND sqp.Search_Query IS NOT NULL
  AND sqp.Year IS NOT NULL
  AND sqp.Week IS NOT NULL
  AND sqp.Week_Start_date IS NOT NULL
  AND sqp.Week_End_date IS NOT NULL
  -- Exclude records that already exist in staging (if re-running)
  AND NOT EXISTS (
    SELECT 1
    FROM `onyga-482313.OI.STG_SQP_WEEKLY` stg
    WHERE stg.query_text = sqp.Search_Query
      AND stg.ASIN = sqp.SKU
      AND stg.Year = sqp.Year
      AND stg.Week = sqp.Week
  );

-- =============================================
-- VERIFICATION QUERIES
-- =============================================

-- Check how many rows were inserted
SELECT 
  'Insert Summary' as query_type,
  COUNT(*) as total_rows_inserted,
  COUNT(DISTINCT query_text) as unique_queries,
  COUNT(DISTINCT ASIN) as unique_asins,
  COUNT(DISTINCT Year) as unique_years,
  MIN(Year) as min_year,
  MAX(Year) as max_year,
  MIN(ob_date) as earliest_date,
  MAX(ob_date) as latest_date
FROM `onyga-482313.OI.STG_SQP_WEEKLY`
WHERE ob_file_name IS NULL  -- SQP data has NULL ob_file_name
  AND ob_marketplace_id IS NULL;

-- Check data quality - verify date parsing worked
SELECT 
  'Data Quality Check' as query_type,
  COUNT(*) as total_rows,
  COUNTIF(ob_date IS NULL) as null_ob_dates,
  COUNTIF(week_start_date IS NULL) as null_start_dates,
  COUNTIF(week_end_date IS NULL) as null_end_dates,
  COUNTIF(Year != EXTRACT(YEAR FROM ob_date)) as year_mismatches,
  COUNTIF(Week != EXTRACT(WEEK FROM ob_date)) as week_mismatches
FROM `onyga-482313.OI.STG_SQP_WEEKLY`
WHERE ob_file_name IS NULL  -- SQP data
  AND ob_marketplace_id IS NULL;

-- Sample of inserted data
SELECT 
  query_text,
  ASIN,
  Year,
  Week,
  ob_date,
  week_start_date,
  week_end_date,
  impressions,
  clicks,
  click_through_rate,
  cart_adds,
  conversions,
  conversion_rate,
  TOTAL_IMPRESSIONS,
  TOTAL_CLICKS,
  TOTAL_CART_ADDS,
  TOTAL_PURCHASES
FROM `onyga-482313.OI.STG_SQP_WEEKLY`
WHERE ob_file_name IS NULL  -- SQP data
  AND ob_marketplace_id IS NULL
ORDER BY Year DESC, Week DESC, query_text, ASIN
LIMIT 10;

-- Compare source vs target counts
SELECT 
  'Source Count' as source_type,
  COUNT(*) as row_count
FROM `onyga-482313.OI.SQP_ASIN_View_Simple_Week`
WHERE SKU IS NOT NULL
  AND Search_Query IS NOT NULL
  AND Year IS NOT NULL
  AND Week IS NOT NULL

UNION ALL

SELECT 
  'Target Count (SQP data)' as source_type,
  COUNT(*) as row_count
FROM `onyga-482313.OI.STG_SQP_WEEKLY`
WHERE ob_file_name IS NULL  -- SQP data
  AND ob_marketplace_id IS NULL;
