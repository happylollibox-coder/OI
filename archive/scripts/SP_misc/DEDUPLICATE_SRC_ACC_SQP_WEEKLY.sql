-- =============================================
-- OI Database Project - Deduplicate SRC_ACC_SQP_WEEKLY
-- =============================================
--
-- Purpose: Remove duplicates from SRC_ACC_SQP_WEEKLY by copying distinct values to temp table
-- Project: onyga-482313
-- Dataset: OI
--
-- =============================================

-- Step 1: Create temp table with distinct values (keeping most recent record per PK)
CREATE OR REPLACE TABLE `onyga-482313.OI.SRC_ACC_SQP_WEEKLY_TEMP` AS
SELECT DISTINCT
  Search_Query,
  Search_Query_Score,
  Search_Query_Volume,
  Impressions_Total_Count,
  Impressions_ASIN_Count,
  Impressions_ASIN_Share,
  Clicks_Total_Count,
  Clicks_Click_Rate,
  Clicks_ASIN_Count,
  Clicks_ASIN_Share,
  Clicks_Price_Median,
  Clicks_ASIN_Price_Median,
  Clicks_Same_Day_Shipping_Speed,
  Clicks_1D_Shipping_Speed,
  Clicks_2D_Shipping_Speed,
  Cart_Adds_Total_Count,
  Cart_Adds_Cart_Add_Rate,
  Cart_Adds_ASIN_Count,
  Cart_Adds_ASIN_Share,
  Cart_Adds_Price_Median,
  Cart_Adds_ASIN_Price_Median,
  Cart_Adds_Same_Day_Shipping_Speed,
  Cart_Adds_1D_Shipping_Speed,
  Cart_Adds_2D_Shipping_Speed,
  Purchases_Total_Count,
  Purchases_Purchase_Rate,
  Purchases_ASIN_Count,
  Purchases_ASIN_Share,
  Purchases_Price_Median,
  Purchases_ASIN_Price_Median,
  Purchases_Same_Day_Shipping_Speed,
  Purchases_1D_Shipping_Speed,
  Purchases_2D_Shipping_Speed,
  Reporting_Date,
  ASIN,
  source_file,
  processed_at
FROM (
  SELECT 
    Search_Query,
    Search_Query_Score,
    Search_Query_Volume,
    Impressions_Total_Count,
    Impressions_ASIN_Count,
    Impressions_ASIN_Share,
    Clicks_Total_Count,
    Clicks_Click_Rate,
    Clicks_ASIN_Count,
    Clicks_ASIN_Share,
    Clicks_Price_Median,
    Clicks_ASIN_Price_Median,
    Clicks_Same_Day_Shipping_Speed,
    Clicks_1D_Shipping_Speed,
    Clicks_2D_Shipping_Speed,
    Cart_Adds_Total_Count,
    Cart_Adds_Cart_Add_Rate,
    Cart_Adds_ASIN_Count,
    Cart_Adds_ASIN_Share,
    Cart_Adds_Price_Median,
    Cart_Adds_ASIN_Price_Median,
    Cart_Adds_Same_Day_Shipping_Speed,
    Cart_Adds_1D_Shipping_Speed,
    Cart_Adds_2D_Shipping_Speed,
    Purchases_Total_Count,
    Purchases_Purchase_Rate,
    Purchases_ASIN_Count,
    Purchases_ASIN_Share,
    Purchases_Price_Median,
    Purchases_ASIN_Price_Median,
    Purchases_Same_Day_Shipping_Speed,
    Purchases_1D_Shipping_Speed,
    Purchases_2D_Shipping_Speed,
    Reporting_Date,
    ASIN,
    source_file,
    processed_at,
    ROW_NUMBER() OVER (PARTITION BY Search_Query, ASIN, Reporting_Date ORDER BY processed_at DESC) as rn
  FROM `onyga-482313.OI.SRC_ACC_SQP_WEEKLY`
)
WHERE rn = 1;

-- Step 2: Verify counts
SELECT 
  'Original table' as table_name,
  COUNT(*) as record_count,
  COUNT(DISTINCT CONCAT(Search_Query, '|', ASIN, '|', CAST(Reporting_Date AS STRING))) as unique_keys
FROM `onyga-482313.OI.SRC_ACC_SQP_WEEKLY`
UNION ALL
SELECT 
  'Temp table (deduplicated)' as table_name,
  COUNT(*) as record_count,
  COUNT(DISTINCT CONCAT(Search_Query, '|', ASIN, '|', CAST(Reporting_Date AS STRING))) as unique_keys
FROM `onyga-482313.OI.SRC_ACC_SQP_WEEKLY_TEMP`;

-- Step 3: (Manual step) After verification, run:
-- TRUNCATE TABLE `onyga-482313.OI.SRC_ACC_SQP_WEEKLY`;
-- INSERT INTO `onyga-482313.OI.SRC_ACC_SQP_WEEKLY` SELECT * FROM `onyga-482313.OI.SRC_ACC_SQP_WEEKLY_TEMP`;
-- DROP TABLE `onyga-482313.OI.SRC_ACC_SQP_WEEKLY_TEMP`;
