-- =============================================
-- OI Database Project - Replace SRC_ACC_SQP_WEEKLY with deduplicated data
-- =============================================
--
-- Purpose: Replace SRC_ACC_SQP_WEEKLY with deduplicated data from temp table
-- Project: onyga-482313
-- Dataset: OI
--
-- =============================================

-- Step 1: Truncate the original table
TRUNCATE TABLE `onyga-482313.OI.SRC_ACC_SQP_WEEKLY`;

-- Step 2: Copy all data from temp table to original table
INSERT INTO `onyga-482313.OI.SRC_ACC_SQP_WEEKLY` (
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
)
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
  processed_at
FROM `onyga-482313.OI.SRC_ACC_SQP_WEEKLY_TEMP`;

-- Step 3: Verify the replacement
SELECT 
  'SRC_ACC_SQP_WEEKLY (after replacement)' as table_name,
  COUNT(*) as record_count,
  COUNT(DISTINCT CONCAT(Search_Query, '|', ASIN, '|', CAST(Reporting_Date AS STRING))) as unique_keys
FROM `onyga-482313.OI.SRC_ACC_SQP_WEEKLY`;
