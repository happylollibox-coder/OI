-- =============================================
-- ONE-TIME INSERT: SCP_ASIN_View_Week to STG_SCP_WEEKLY
-- =============================================
-- Purpose: One-time data migration from SCP table to staging table
-- Maps SCP column structure to STG_SCP_WEEKLY structure
-- Project: onyga-482313
-- Dataset: OI
--
-- IMPORTANT: This is a ONE-TIME script. Run only once to migrate existing data.
-- After this, use SP_MERGE_SCP_WEEKLY for ongoing updates.
-- =============================================

-- Insert data from SCP_ASIN_View_Week into STG_SCP_WEEKLY
INSERT INTO `onyga-482313.OI.STG_SCP_WEEKLY` (
  -- Primary Key Dimensions
  ASIN,
  Year,
  Week,
  ob_date,  -- Using Reporting_Date as the date reference
  week_start_date,
  week_end_date,
  
  -- Performance Metrics (matching SQP naming convention)
  impressions,
  clicks,
  click_through_rate,
  cart_adds,
  conversions,
  conversion_rate,
  sales_amount,
  sales_currency_code,
  
  -- OpenBridge Metadata (NULL for SCP data)
  ob_file_name,
  ob_marketplace_id,
  ob_seller_id,
  ob_transaction_id,
  ob_modified_date,
  ob_processed_at
)
SELECT
  -- Primary Key Dimensions
  scp.ASIN,
  scp.Year,
  scp.Week,
  PARSE_DATE('%d/%m/%Y', scp.Reporting_Date) as ob_date,  -- Use Reporting_Date as the date reference
  PARSE_DATE('%d/%m/%Y', scp.Start_date) as week_start_date,
  PARSE_DATE('%d/%m/%Y', scp.End_Date) as week_end_date,
  
  -- Performance Metrics - Map from SCP to SQP naming convention
  scp.Impressions_Impressions as impressions,
  scp.Clicks_Clicks as clicks,
  scp.Clicks_Click_Rate_CTR as click_through_rate,
  scp.Cart_Adds_Cart_Adds as cart_adds,
  scp.Purchases_Purchases as conversions,
  scp.Purchases_Conversion_Rate_Percent as conversion_rate,
  scp.Purchases_Search_Traffic_Sales as sales_amount,
  CAST(NULL AS STRING) as sales_currency_code,  -- Not available in SCP, default to NULL
  
  -- OpenBridge Metadata - All NULL for SCP data
  CAST(NULL AS STRING) as ob_file_name,
  CAST(NULL AS STRING) as ob_marketplace_id,
  CAST(NULL AS STRING) as ob_seller_id,
  CAST(NULL AS STRING) as ob_transaction_id,
  CAST(NULL AS DATETIME) as ob_modified_date,
  CAST(NULL AS STRING) as ob_processed_at

FROM `onyga-482313.OI.SCP_ASIN_View_Week` scp
WHERE scp.ASIN IS NOT NULL
  AND scp.Year IS NOT NULL
  AND scp.Week IS NOT NULL
  AND scp.Reporting_Date IS NOT NULL
  AND scp.Start_date IS NOT NULL
  AND scp.End_Date IS NOT NULL
  -- Exclude records that already exist in staging (if re-running)
  AND NOT EXISTS (
    SELECT 1
    FROM `onyga-482313.OI.STG_SCP_WEEKLY` stg
    WHERE stg.ASIN = scp.ASIN
      AND stg.Year = scp.Year
      AND stg.Week = scp.Week
  );

-- =============================================
-- VERIFICATION QUERIES
-- =============================================

-- Check how many rows were inserted
SELECT 
  'Insert Summary' as query_type,
  COUNT(*) as total_rows_inserted,
  COUNT(DISTINCT ASIN) as unique_asins,
  COUNT(DISTINCT Year) as unique_years,
  MIN(Year) as min_year,
  MAX(Year) as max_year,
  MIN(ob_date) as earliest_date,
  MAX(ob_date) as latest_date
FROM `onyga-482313.OI.STG_SCP_WEEKLY`
WHERE ob_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY);

-- Check data quality - verify date parsing worked
SELECT 
  'Data Quality Check' as query_type,
  COUNT(*) as total_rows,
  COUNTIF(ob_date IS NULL) as null_ob_dates,
  COUNTIF(week_start_date IS NULL) as null_start_dates,
  COUNTIF(week_end_date IS NULL) as null_end_dates,
  COUNTIF(Year != EXTRACT(YEAR FROM ob_date)) as year_mismatches,
  COUNTIF(Week != EXTRACT(WEEK FROM ob_date)) as week_mismatches
FROM `onyga-482313.OI.STG_SCP_WEEKLY`
WHERE ob_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY);

-- Sample of inserted data
SELECT 
  ASIN,
  Year,
  Week,
  ob_date,
  week_start_date,
  week_end_date,
  impressions,
  clicks,
  conversions,
  sales_amount
FROM `onyga-482313.OI.STG_SCP_WEEKLY`
WHERE ob_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY)
ORDER BY Year DESC, Week DESC, ASIN
LIMIT 10;
