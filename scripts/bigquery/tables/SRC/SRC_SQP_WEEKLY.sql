-- =============================================
-- OI Database Project - SRC_SQP_WEEKLY Table
-- =============================================
--
-- Purpose: Temporary staging table for SQP CSV file uploads
-- Data is loaded here first, then processed to SRC_ACC_SQP_WEEKLY
-- Project: onyga-482313
-- Dataset: OI
--
-- =============================================

CREATE OR REPLACE TABLE `onyga-482313.OI.SRC_SQP_WEEKLY` (
  -- CSV columns matching Amazon SQP export structure
  Search_Query STRING,
  Search_Query_Score INT64,
  Search_Query_Volume INT64,
  Impressions_Total_Count INT64,
  Impressions_ASIN_Count INT64,
  Impressions_ASIN_Share FLOAT64,
  Clicks_Total_Count INT64,
  Clicks_Click_Rate FLOAT64,
  Clicks_ASIN_Count INT64,
  Clicks_ASIN_Share FLOAT64,
  Clicks_Price_Median FLOAT64,
  Clicks_ASIN_Price_Median FLOAT64,
  Clicks_Same_Day_Shipping_Speed INT64,
  Clicks_1D_Shipping_Speed INT64,
  Clicks_2D_Shipping_Speed INT64,
  Cart_Adds_Total_Count INT64,
  Cart_Adds_Cart_Add_Rate FLOAT64,
  Cart_Adds_ASIN_Count INT64,
  Cart_Adds_ASIN_Share FLOAT64,
  Cart_Adds_Price_Median FLOAT64,
  Cart_Adds_ASIN_Price_Median FLOAT64,
  Cart_Adds_Same_Day_Shipping_Speed INT64,
  Cart_Adds_1D_Shipping_Speed INT64,
  Cart_Adds_2D_Shipping_Speed INT64,
  Purchases_Total_Count INT64,
  Purchases_Purchase_Rate FLOAT64,
  Purchases_ASIN_Count INT64,
  Purchases_ASIN_Share FLOAT64,
  Purchases_Price_Median FLOAT64,
  Purchases_ASIN_Price_Median FLOAT64,
  Purchases_Same_Day_Shipping_Speed INT64,
  Purchases_1D_Shipping_Speed INT64,
  Purchases_2D_Shipping_Speed INT64,
  Reporting_Date DATE,
  -- Metadata (extracted from file)
  ASIN STRING,  -- Extracted from metadata row or filename
  source_file STRING,
  processed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP()
)
OPTIONS (
  description = "Temporary staging table for SQP CSV file uploads. Data is processed to SRC_ACC_SQP_WEEKLY by SP_PROCESS_MANUAL_UPLOADS."
);
