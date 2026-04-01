-- =============================================
-- OI Database Project - FACT_AMAZON_SEARCH_PERFORMANCE_WEEKLY Table
-- =============================================
--
-- Purpose: Fact table for weekly Amazon search performance data
-- Method: TRUNCATE + INSERT (full refresh)
-- Source: STG_AMAZON_SEARCH_PERFORMANCE_WEEKLY
-- Project: onyga-482313
-- Dataset: OI
--
-- =============================================

CREATE OR REPLACE TABLE `onyga-482313.OI.FACT_AMAZON_SEARCH_PERFORMANCE_WEEKLY` (
  -- Same columns as STG_AMAZON_SEARCH_PERFORMANCE_WEEKLY
  Reporting_Date DATE NOT NULL,
  ASIN STRING NOT NULL,
  Search_Query STRING,  -- Nullable
  
  -- Search Query Metadata
  Search_Query_Score FLOAT64,
  
  -- Data Source
  DATA_SOURCE STRING,
  
  -- Performance Metrics (Overall)
  Impressions INT64,
  Clicks INT64,
  Cart_Adds INT64,
  ORDERS INT64,
  
  -- Performance Metrics (Amazon-specific)
  AMAZON_IMPRESSIONS INT64,
  AMAZON_Clicks INT64,
  AMAZON_Cart_Adds INT64,
  AMAZON_ORDERS INT64,
  
  -- Performance Metrics (Ads-specific, from V_AMAZON_ADS_TOP_SEARCH_QUERY_TERMS_WEEKLY)
  ADS_Impressions INT64,
  ADS_Clicks INT64,
  ADS_Orders INT64,
  ADS_Units INT64,
  
  -- Derived Organic Metrics (Rule 9: row-grain measures in DB)
  ORGANIC_ORDERS INT64,  -- ORDERS - COALESCE(ADS_Orders, 0); organic orders for this ASIN on this search query
  
  -- Organic Rank Estimation (calibrated from SQP IS% vs manual rank checks, Feb 2026)
  show_rate_pct FLOAT64,                  -- Impressions / AMAZON_IMPRESSIONS * 100
  estimated_organic_rank FLOAT64,         -- 52 - 0.85 * show_rate_pct
  organic_rank_zone STRING,               -- upper_p1 / mid_p1 / lower_p1 / bottom_p1 / page_2_plus

  -- Keys
  ad_key STRING,  -- Composite key: Reporting_Date-ASIN-Search_Query
  factless_key STRING,  -- Composite key: Reporting_Date-ASIN
  
  -- Primary Key: Same as STG
  PRIMARY KEY (Reporting_Date, ASIN, Search_Query) NOT ENFORCED
)
PARTITION BY DATE_TRUNC(Reporting_Date, YEAR)
CLUSTER BY ASIN, Reporting_Date;

-- =============================================
-- TABLE DESCRIPTION
-- =============================================
--
-- This fact table holds weekly Amazon search performance data from STG_AMAZON_SEARCH_PERFORMANCE_WEEKLY.
-- It is refreshed using TRUNCATE + INSERT method.
--
-- Key Features:
-- - Contains all columns from STG_AMAZON_SEARCH_PERFORMANCE_WEEKLY
-- - Adds ad_key field: Reporting_Date-ASIN-Search_Query
-- - Adds factless_key field: Reporting_Date-ASIN
-- - Adds Ads-specific metrics (ADS_* columns) populated from V_AMAZON_ADS_TOP_SEARCH_QUERY_TERMS_WEEKLY
--
-- The SP_LOAD_FACT_AMAZON_SEARCH_PERFORMANCE_WEEKLY procedure manages this table:
-- - TRUNCATEs table on each run
-- - Copies all data from STG_AMAZON_SEARCH_PERFORMANCE_WEEKLY
-- - Calculates ad_key and factless_key for each row
--
-- =============================================
