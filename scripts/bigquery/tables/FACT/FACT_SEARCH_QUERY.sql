-- =============================================
-- OI Database Project - FACT_SEARCH_QUERY Table
-- =============================================
--
-- Purpose: Fact table combining SQP (query-level) and SCP (ASIN-level) search performance data
-- Combines query-level detail from SQP with delta records representing non-query traffic
-- When aggregated by ASIN+Year+Week, sum equals SCP values
-- Project: onyga-482313
-- Dataset: OI
--
-- =============================================

CREATE OR REPLACE TABLE `onyga-482313.OI.FACT_SEARCH_QUERY` (
  -- Primary Key Dimensions
  query_text STRING,
  ASIN STRING,
  Year INT64 NOT NULL,
  Week INT64 NOT NULL,
  ob_date DATE,
  
  -- Week Boundaries (calculated)
  week_start_date DATE NOT NULL,
  week_end_date DATE NOT NULL,
  
  -- Search Query Performance Metrics
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
  
  -- Additional metrics
  query_rank INT64,
  avg_position FLOAT64,

  -- Organic Rank Estimation (calibrated from SQP IS% vs manual rank checks)
  search_query_volume INT64,              -- weekly search volume for this query
  impression_share_pct FLOAT64,           -- our_impr / total_impr * 100
  show_rate_pct FLOAT64,                  -- our_impr / search_volume * 100 (key predictor)
  estimated_organic_rank FLOAT64,         -- 52 - 0.85 * show_rate_pct
  organic_rank_zone STRING,               -- upper_p1 / mid_p1 / lower_p1 / bottom_p1 / page_2_plus
  
  -- OpenBridge Metadata
  ob_file_name STRING,
  ob_marketplace_id STRING,
  ob_seller_id STRING,
  ob_transaction_id STRING,
  ob_modified_date DATETIME,
  ob_processed_at STRING,
  
  -- Data Source Identifier
  data_source STRING NOT NULL,  -- 'SQP' or 'SCP'
  
  -- Primary Key
  PRIMARY KEY (query_text, ASIN, Year, Week) NOT ENFORCED
)
PARTITION BY DATE_TRUNC(week_start_date, YEAR)
CLUSTER BY query_text, ASIN, Year, Week;

-- =============================================
-- TABLE DESCRIPTION
-- =============================================
--
-- This fact table combines search query performance data from two sources:
-- 1. SQP (Search Query Performance): Query-level detail with query_text
-- 2. SCP (Search Catalog Performance): Delta records representing non-query traffic
--
-- Key Features:
-- - Contains all SQP records with data_source = 'SQP'
-- - Contains delta records (SCP - SUM(SQP)) with query_text = 'OTHER' and data_source = 'SCP'
-- - When aggregated by ASIN+Year+Week, sum equals SCP table values
-- - Delta records have NULL values for TOTAL_* fields, query_rank, and avg_position
--
-- Population:
-- - Managed by SP_LOAD_FACT_SEARCH_QUERY
-- - Uses TRUNCATE + INSERT pattern (full refresh each run)
-- - Step 1: Insert all SQP data
-- - Step 2: Calculate and insert delta records per ASIN+Year+Week
--
-- =============================================
