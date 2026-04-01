-- =============================================
-- OI Database Project - SRC_ACC_SCP_WEEKLY Table
-- =============================================
--
-- Purpose: Permanent accumulation table for SCP CSV file uploads
-- Stores raw CSV data from manual uploads, processed from SRC_SCP_WEEKLY
-- Project: onyga-482313
-- Dataset: OI
--
-- =============================================

CREATE OR REPLACE TABLE `onyga-482313.OI.SRC_ACC_SCP_WEEKLY` (
  -- CSV columns matching Amazon SCP export structure (same as SRC_SCP_WEEKLY)
  ASIN_Title STRING,
  ASIN STRING NOT NULL,
  Category STRING,
  Impressions_Impressions INT64,
  Impressions_Rating_Median FLOAT64,
  Impressions_Price_Median FLOAT64,
  Impressions_Same_Day_Shipping_Speed INT64,
  Impressions_1D_Shipping_Speed INT64,
  Impressions_2D_Shipping_Speed INT64,
  Clicks_Clicks INT64,
  Clicks_Click_Rate_CTR FLOAT64,
  Clicks_Price_Median FLOAT64,
  Clicks_Same_Day_Shipping_Speed INT64,
  Clicks_1D_Shipping_Speed INT64,
  Clicks_2D_Shipping_Speed INT64,
  Cart_Adds_Cart_Adds INT64,
  Cart_Adds_Price_Median FLOAT64,
  Cart_Adds_Same_Day_Shipping_Speed INT64,
  Cart_Adds_1D_Shipping_Speed INT64,
  Cart_Adds_2D_Shipping_Speed INT64,
  Purchases_Purchases INT64,
  Purchases_Search_Traffic_Sales FLOAT64,
  Purchases_Conversion_Rate FLOAT64,
  Purchases_Rating_Median FLOAT64,
  Purchases_Price_Median FLOAT64,
  Purchases_Same_Day_Shipping_Speed INT64,
  Purchases_1D_Shipping_Speed INT64,
  Purchases_2D_Shipping_Speed INT64,
  Reporting_Date DATE NOT NULL,
  -- Metadata
  source_file STRING,
  processed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP(),
  -- Primary Key
  PRIMARY KEY (ASIN, Reporting_Date) NOT ENFORCED
)
PARTITION BY Reporting_Date
CLUSTER BY ASIN, Reporting_Date
OPTIONS (
  description = "Permanent accumulation table for SCP CSV file uploads. Data is processed from SRC_SCP_WEEKLY by SP_PROCESS_MANUAL_UPLOADS, then used by SP_MERGE_SCP_WEEKLY to populate STG_SCP_WEEKLY."
);
