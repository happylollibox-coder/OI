-- =============================================
-- OI Database Project - SP_PROCESS_MANUAL_UPLOADS Stored Procedure
-- =============================================
--
-- Purpose: Process manual uploads from SRC tables to SRC_ACC tables
-- Caller must ensure: all files exist and no duplicate files before loading into SRC (see scripts/validate_upload_files.py).
-- Uses DISTINCT to avoid duplicates within SRC tables; only inserts rows where PK does not exist in SRC_ACC.
-- Project: onyga-482313
-- Dataset: OI
--
-- =============================================

CREATE OR REPLACE PROCEDURE `onyga-482313.OI.SP_PROCESS_MANUAL_UPLOADS`()
OPTIONS (
  description = "Process manual uploads from SRC tables to SRC_ACC tables. Uses DISTINCT to avoid duplicates within SRC, and only inserts rows where PK does not exist in SRC_ACC."
)
BEGIN
  -- Declare variables for logging
  DECLARE start_time TIMESTAMP;
  DECLARE end_time TIMESTAMP;
  DECLARE total_processed INT64 DEFAULT 0;
  DECLARE scp_inserted INT64 DEFAULT 0;
  DECLARE sqp_inserted INT64 DEFAULT 0;

  SET start_time = CURRENT_TIMESTAMP();

  -- ============================================
  -- Process SRC_SCP_WEEKLY → SRC_ACC_SCP_WEEKLY
  -- ============================================
  
  -- Check if SRC_SCP_WEEKLY has data
  IF EXISTS (SELECT 1 FROM `onyga-482313.OI.SRC_SCP_WEEKLY` LIMIT 1) THEN
    -- Insert DISTINCT rows where (Reporting_Date, ASIN) does NOT already exist in SRC_ACC
    -- PK is (ASIN, Reporting_Date)
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
    SELECT DISTINCT
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
      src.Purchases_Conversion_Rate,
      src.Purchases_Rating_Median,
      src.Purchases_Price_Median,
      src.Purchases_Same_Day_Shipping_Speed,
      src.Purchases_1D_Shipping_Speed,
      src.Purchases_2D_Shipping_Speed,
      src.Reporting_Date,
      CAST(NULL AS STRING) as source_file,
      CURRENT_TIMESTAMP() as processed_at
    FROM `onyga-482313.OI.SRC_SCP_WEEKLY` src
    WHERE src.Reporting_Date IS NOT NULL
      AND src.ASIN IS NOT NULL
      -- Only insert if (Reporting_Date, ASIN) does not already exist in SRC_ACC
      AND NOT EXISTS (
        SELECT 1
        FROM `onyga-482313.OI.SRC_ACC_SCP_WEEKLY` acc
        WHERE acc.ASIN = src.ASIN
          AND acc.Reporting_Date = src.Reporting_Date
      );
    
    SET scp_inserted = @@row_count;
    
    -- Truncate SRC_SCP_WEEKLY after processing
    TRUNCATE TABLE `onyga-482313.OI.SRC_SCP_WEEKLY`;
    
    SET total_processed = total_processed + 1;
  END IF;

  -- ============================================
  -- Process SRC_SQP_WEEKLY → SRC_ACC_SQP_WEEKLY
  -- ============================================
  
  -- Check if SRC_SQP_WEEKLY has data
  IF EXISTS (SELECT 1 FROM `onyga-482313.OI.SRC_SQP_WEEKLY` LIMIT 1) THEN
    -- Insert DISTINCT rows where (Search_Query, ASIN, Reporting_Date) does NOT already exist in SRC_ACC
    -- PK is (Search_Query, ASIN, Reporting_Date)
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
    SELECT DISTINCT
      src.Search_Query,
      src.Search_Query_Score,
      src.Search_Query_Volume,
      src.Impressions_Total_Count,
      src.Impressions_ASIN_Count,
      src.Impressions_ASIN_Share,
      src.Clicks_Total_Count,
      src.Clicks_Click_Rate,
      src.Clicks_ASIN_Count,
      src.Clicks_ASIN_Share,
      src.Clicks_Price_Median,
      src.Clicks_ASIN_Price_Median,
      src.Clicks_Same_Day_Shipping_Speed,
      src.Clicks_1D_Shipping_Speed,
      src.Clicks_2D_Shipping_Speed,
      src.Cart_Adds_Total_Count,
      src.Cart_Adds_Cart_Add_Rate,
      src.Cart_Adds_ASIN_Count,
      src.Cart_Adds_ASIN_Share,
      src.Cart_Adds_Price_Median,
      src.Cart_Adds_ASIN_Price_Median,
      src.Cart_Adds_Same_Day_Shipping_Speed,
      src.Cart_Adds_1D_Shipping_Speed,
      src.Cart_Adds_2D_Shipping_Speed,
      src.Purchases_Total_Count,
      src.Purchases_Purchase_Rate,
      src.Purchases_ASIN_Count,
      src.Purchases_ASIN_Share,
      src.Purchases_Price_Median,
      src.Purchases_ASIN_Price_Median,
      src.Purchases_Same_Day_Shipping_Speed,
      src.Purchases_1D_Shipping_Speed,
      src.Purchases_2D_Shipping_Speed,
      src.Reporting_Date,
      src.ASIN,
      CAST(NULL AS STRING) as source_file,
      CURRENT_TIMESTAMP() as processed_at
    FROM `onyga-482313.OI.SRC_SQP_WEEKLY` src
    WHERE src.Reporting_Date IS NOT NULL
      AND src.ASIN IS NOT NULL
      AND src.Search_Query IS NOT NULL
      -- Only insert if (Search_Query, ASIN, Reporting_Date) does not already exist in SRC_ACC
      AND NOT EXISTS (
        SELECT 1
        FROM `onyga-482313.OI.SRC_ACC_SQP_WEEKLY` acc
        WHERE acc.Search_Query = src.Search_Query
          AND acc.ASIN = src.ASIN
          AND acc.Reporting_Date = src.Reporting_Date
      );
    
    SET sqp_inserted = @@row_count;
    
    -- Truncate SRC_SQP_WEEKLY after processing
    TRUNCATE TABLE `onyga-482313.OI.SRC_SQP_WEEKLY`;
    
    SET total_processed = total_processed + 1;
  END IF;

  SET end_time = CURRENT_TIMESTAMP();

  -- Log the operation results
  SELECT FORMAT(
    'SP_PROCESS_MANUAL_UPLOADS completed:\n' ||
    '  SCP: Inserted %d rows (DISTINCT used, duplicates by Reporting_Date+ASIN skipped)\n' ||
    '  SQP: Inserted %d rows (DISTINCT used, duplicates by Search_Query+ASIN+Reporting_Date skipped)\n' ||
    '  Total tables processed: %d\n' ||
    '  Duration: %d seconds\n' ||
    '  Completed at: %s',
    scp_inserted,
    sqp_inserted,
    total_processed,
    TIMESTAMP_DIFF(end_time, start_time, SECOND),
    CAST(end_time AS STRING)
  ) as operation_summary;
END;
