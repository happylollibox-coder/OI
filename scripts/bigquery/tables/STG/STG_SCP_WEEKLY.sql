-- =============================================
-- OI Database Project - STG_SCP_WEEKLY Table
-- =============================================
--
-- Purpose: Staging table for weekly ASIN performance data from OpenBridge and SCP
-- Simple upsert pattern - updates existing records, inserts new ones
-- Project: onyga-482313
-- Dataset: OI
--
-- =============================================

CREATE OR REPLACE TABLE `onyga-482313.OI.STG_SCP_WEEKLY` (
  -- Primary Key Dimensions
  ASIN STRING NOT NULL,
  Year INT64 NOT NULL,  -- Extracted from ob_date
  Week INT64 NOT NULL,  -- Extracted from ob_date
  ob_date DATE,  -- Original date from source (not in PK)
  
  -- Week Boundaries (calculated)
  week_start_date DATE NOT NULL,  -- Week start (Monday)
  week_end_date DATE NOT NULL,    -- Week end (Sunday)
  
  -- Performance Metrics (matching SQP naming convention)
  impressions INT64,
  clicks INT64,
  click_through_rate FLOAT64,
  cart_adds INT64,
  conversions INT64,
  conversion_rate FLOAT64,
  sales_amount FLOAT64,
  sales_currency_code STRING,
  
  -- OpenBridge Metadata
  ob_file_name STRING,
  ob_marketplace_id STRING,
  ob_seller_id STRING,
  ob_transaction_id STRING,
  ob_modified_date DATETIME,
  ob_processed_at STRING,
  
  -- Primary Key
  PRIMARY KEY (ASIN, Year, Week) NOT ENFORCED
)
PARTITION BY DATE_TRUNC(week_start_date, YEAR)
CLUSTER BY ASIN, Year, Week;

-- =============================================
-- TABLE DESCRIPTION
-- =============================================
--
-- This staging table holds weekly ASIN performance data from both OpenBridge and SCP sources.
-- Simple upsert pattern:
-- - Updates existing records (overwrites with latest data)
-- - Inserts new records for new ASIN/Year/Week combinations
--
-- Key Features:
-- - Year/Week extracted from ob_date for compatibility with SCP structure
-- - Week boundaries calculated (Monday to Sunday)
-- - Field naming matches STG_SQP_WEEKLY for consistency
-- - Metadata fields from OpenBridge preserved
-- - Source can be identified by ob_file_name (NULL = SCP, NOT NULL = OpenBridge)
--
-- The SP_MERGE_SCP_WEEKLY procedure manages this table:
-- - Simple MERGE: UPDATE if exists, INSERT if not
-- - No change detection - always updates matched records
--
-- =============================================
