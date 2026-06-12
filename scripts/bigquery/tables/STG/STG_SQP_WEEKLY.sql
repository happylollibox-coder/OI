-- =============================================
-- OI Database Project - STG_SQP_WEEKLY Table
-- =============================================
--
-- Purpose: Staging table for weekly search query performance data from OpenBridge
-- Only updates records when data changes, inserts new records
-- Source: openbridge-482712.DB.sp_ba_search_query_by_week_v1
-- Project: onyga-482313
-- Dataset: OI
--
-- =============================================

CREATE OR REPLACE TABLE `onyga-482313.OI.STG_SQP_WEEKLY` (
  -- Primary Key Dimensions
  -- Note: Adjust these based on actual source table structure
  -- Common patterns: query text, ASIN, date/week combinations
  query_text STRING,
  ASIN STRING,
  Year INT64 NOT NULL,  -- Extracted from ob_date or week_date
  Week INT64 NOT NULL,  -- Extracted from ob_date or week_date
  ob_date DATE,  -- Original date from source (if available)
  
  -- Week Boundaries (calculated)
  week_start_date DATE NOT NULL,  -- Week start (Monday)
  week_end_date DATE NOT NULL,    -- Week end (Sunday)
  
  -- Search Query Performance Metrics
  -- These fields will be populated from source table
  -- Adjust field names based on actual source structure
  impressions INT64,
  clicks INT64,
  click_through_rate FLOAT64,
  cart_adds INT64,
  conversions INT64,
  conversion_rate FLOAT64,
  sales_amount FLOAT64,
  sales_currency_code STRING,
  
  -- Total Count Metrics (across all ASINs for the query)
  TOTAL_IMPRESSIONS INT64,
  TOTAL_CLICKS INT64,
  TOTAL_CART_ADDS INT64,
  TOTAL_PURCHASES INT64,
  
  -- Median Click Price Metrics
  total_median_click_price FLOAT64,   -- Median click price across all ASINs for the query
  asin_median_click_price FLOAT64,    -- Median click price for this specific ASIN
  
  -- Additional metrics (adjust based on source)
  query_rank INT64,
  avg_position FLOAT64,
  
  -- OpenBridge Metadata
  ob_file_name STRING,
  ob_marketplace_id STRING,
  ob_seller_id STRING,
  ob_transaction_id STRING,
  ob_modified_date DATETIME,
  ob_processed_at STRING,
  
  -- Primary Key (adjust based on actual source table key structure)
  -- Common pattern: query_text + ASIN + Year + Week
  PRIMARY KEY (query_text, ASIN, Year, Week) NOT ENFORCED
)
PARTITION BY DATE_TRUNC(week_start_date, YEAR)
CLUSTER BY query_text, ASIN, Year, Week;

-- =============================================
-- TABLE DESCRIPTION
-- =============================================
--
-- This staging table holds weekly search query performance data from OpenBridge.
-- It merges data efficiently:
-- - Only updates records when data actually changes
-- - Inserts new records for new query/ASIN/Year/Week combinations
--
-- Key Features:
-- - Year/Week extracted from date fields for compatibility
-- - Week boundaries calculated (Monday to Sunday)
-- - All OpenBridge metrics preserved
-- - Metadata fields from OpenBridge preserved
--
-- The  wanr SP_MERGE_SQP_WEEKLY procedure manages this table:
-- - Compares source data with staging data
-- - Only updates if any metric values changed
-- - Inserts new records for new combinations
--
-- NOTE: This table structure is a template. The actual structure should match
-- the columns in openbridge-482712.DB.sp_ba_search_query_by_week_v1
-- Adjust field names and types based on the actual source table schema.
--
-- =============================================
