-- =============================================
-- OI Database Project - Copy SQP_ASIN_View_Simple_Week to SRC_ACC_SQP_WEEKLY
-- =============================================
--
-- Purpose: One-time copy of data from SQP_ASIN_View_Simple_Week to SRC_ACC_SQP_WEEKLY
-- Excludes: Year, Week, Week_Start_date, Week_End_date
-- Maps SKU to ASIN
-- Handles column name differences (spaces, % symbols)
-- Project: onyga-482313
-- Dataset: OI
--
-- =============================================

CREATE OR REPLACE PROCEDURE `onyga-482313.OI.COPY_SQP_ASIN_VIEW_TO_SRC_ACC`()
OPTIONS (
  description = "Copy historical data from SQP_ASIN_View_Simple_Week to SRC_ACC_SQP_WEEKLY, excluding Year, Week, Week_Start_date, Week_End_date, and handling column name mapping."
)
BEGIN
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
    src.Search_Query,
    src.Search_Query_Score,
    src.Search_Query_Volume,
    src.Impressions_Total_Count,
    src.Impressions_ASIN_Count,
    src.`Impressions_ASIN_Share_%` as Impressions_ASIN_Share,  -- Map column with % symbol
    src.Clicks_Total_Count,
    src.`Clicks_Click_Rate_%` as Clicks_Click_Rate,  -- Map column with % symbol
    src.Clicks_ASIN_Count,
    src.`Clicks_ASIN_Share_%` as Clicks_ASIN_Share,  -- Map column with % symbol
    src.`Clicks_Price_ Median` as Clicks_Price_Median,  -- Map column with space
    src.`Clicks_ASIN_Price_ Median` as Clicks_ASIN_Price_Median,  -- Map column with space
    src.Clicks_Same_Day_Shipping_Speed,
    src.Clicks_1D_Shipping_Speed,
    src.Clicks_2D_Shipping_Speed,
    src.Cart_Adds_Total_Count,
    src.`Cart_Adds_Cart_Add_Rate_%` as Cart_Adds_Cart_Add_Rate,  -- Map column with % symbol
    src.Cart_Adds_ASIN_Count,
    src.`Cart_Adds_ASIN_Share_%` as Cart_Adds_ASIN_Share,  -- Map column with % symbol
    src.`Cart_Adds_Price_ Median` as Cart_Adds_Price_Median,  -- Map column with space
    src.`Cart_Adds_ASIN_Price_ Median` as Cart_Adds_ASIN_Price_Median,  -- Map column with space
    src.Cart_Adds_Same_Day_Shipping_Speed,
    src.Cart_Adds_1D_Shipping_Speed,
    src.Cart_Adds_2D_Shipping_Speed,
    src.Purchases_Total_Count,
    src.`Purchases_Purchase_Rate_%` as Purchases_Purchase_Rate,  -- Map column with % symbol
    src.Purchases_ASIN_Count,
    src.`Purchases_ASIN_Share_%` as Purchases_ASIN_Share,  -- Map column with % symbol
    src.`Purchases_Price_ Median` as Purchases_Price_Median,  -- Map column with space
    src.`Purchases_ASIN_Price_ Median` as Purchases_ASIN_Price_Median,  -- Map column with space
    src.Purchases_Same_Day_Shipping_Speed,
    src.Purchases_1D_Shipping_Speed,
    src.Purchases_2D_Shipping_Speed,
    src.Reporting_Date,  -- Already DATE type, no conversion needed
    src.SKU as ASIN,  -- Map SKU to ASIN
    'SQP_ASIN_View_Simple_Week_Historical' as source_file,
    CURRENT_TIMESTAMP() as processed_at
  FROM `onyga-482313.OI.SQP_ASIN_View_Simple_Week` src
  WHERE src.SKU IS NOT NULL
    AND src.Reporting_Date IS NOT NULL
    AND src.Search_Query IS NOT NULL
    -- Exclude rows that already exist in SRC_ACC_SQP_WEEKLY (by PK: Search_Query, ASIN, Reporting_Date)
    AND NOT EXISTS (
      SELECT 1
      FROM `onyga-482313.OI.SRC_ACC_SQP_WEEKLY` acc
      WHERE acc.Search_Query = src.Search_Query
        AND acc.ASIN = src.SKU
        AND acc.Reporting_Date = src.Reporting_Date
    );
END;
