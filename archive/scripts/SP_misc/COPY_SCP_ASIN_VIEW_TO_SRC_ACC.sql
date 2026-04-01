-- =============================================
-- OI Database Project - Copy SCP_ASIN_View_Week to SRC_ACC_SCP_WEEKLY
-- =============================================
--
-- Purpose: One-time copy of data from SCP_ASIN_View_Week to SRC_ACC_SCP_WEEKLY
-- Excludes: Year, Week, Start_date, End_Date
-- Converts Reporting_Date from string (DD/MM/YYYY) to DATE
-- Project: onyga-482313
-- Dataset: OI
--
-- =============================================

INSERT INTO `onyga-482313.OI.SRC_ACC_SCP_WEEKLY` (
  ASIN_Title,
  ASIN,
  Category,
  Impressions_Impressions,
  Impressions_Rating_Median,
  Impressions_Price_Median,
  Impressions_Same_Day_Shipping_Speed,
  Impressions_1D_Shipping_Speed,
  Impressions_2D_Shipping_Speed,
  Clicks_Clicks,
  Clicks_Click_Rate_CTR,
  Clicks_Price_Median,
  Clicks_Same_Day_Shipping_Speed,
  Clicks_1D_Shipping_Speed,
  Clicks_2D_Shipping_Speed,
  Cart_Adds_Cart_Adds,
  Cart_Adds_Price_Median,
  Cart_Adds_Same_Day_Shipping_Speed,
  Cart_Adds_1D_Shipping_Speed,
  Cart_Adds_2D_Shipping_Speed,
  Purchases_Purchases,
  Purchases_Search_Traffic_Sales,
  Purchases_Conversion_Rate,
  Purchases_Rating_Median,
  Purchases_Price_Median,
  Purchases_Same_Day_Shipping_Speed,
  Purchases_1D_Shipping_Speed,
  Purchases_2D_Shipping_Speed,
  Reporting_Date,
  source_file,
  processed_at
)
SELECT
  src.ASIN_Title,
  src.ASIN,
  src.Category,
  src.Impressions_Impressions,
  src.Impressions_Rating_Median,
  src.Impressions_Price_Median,
  src.Impressions_Same_Day_Shipping_Speed,
  src.Impressions_1D_Shipping_Speed,
  src.Impressions_2D_Shipping_Speed,
  src.Clicks_Clicks,
  src.Clicks_Click_Rate_CTR,
  src.Clicks_Price_Median,
  src.Clicks_Same_Day_Shipping_Speed,
  src.Clicks_1D_Shipping_Speed,
  src.Clicks_2D_Shipping_Speed,
  src.Cart_Adds_Cart_Adds,
  src.Cart_Adds_Price_Median,
  src.Cart_Adds_Same_Day_Shipping_Speed,
  src.Cart_Adds_1D_Shipping_Speed,
  src.Cart_Adds_2D_Shipping_Speed,
  src.Purchases_Purchases,
  src.Purchases_Search_Traffic_Sales,
  src.Purchases_Conversion_Rate_Percent as Purchases_Conversion_Rate,  -- Map column name
  src.Purchases_Rating_Median,
  src.Purchases_Price_Median,
  src.Purchases_Same_Day_Shipping_Speed,
  src.Purchases_1D_Shipping_Speed,
  src.Purchases_2D_Shipping_Speed,
  PARSE_DATE('%d/%m/%Y', src.Reporting_Date) as Reporting_Date,  -- Convert from DD/MM/YYYY string to DATE
  CAST(NULL AS STRING) as source_file,  -- No source file for historical data
  CURRENT_TIMESTAMP() as processed_at
FROM `onyga-482313.OI.SCP_ASIN_View_Week` src
WHERE src.ASIN IS NOT NULL
  AND src.Reporting_Date IS NOT NULL
  -- Exclude rows that already exist in SRC_ACC_SCP_WEEKLY (by PK: ASIN, Reporting_Date)
  AND NOT EXISTS (
    SELECT 1
    FROM `onyga-482313.OI.SRC_ACC_SCP_WEEKLY` acc
    WHERE acc.ASIN = src.ASIN
      AND acc.Reporting_Date = PARSE_DATE('%d/%m/%Y', src.Reporting_Date)
  );
