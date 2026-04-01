-- =============================================
-- OI Database Project - STG_AMAZON_SEARCH_PERFORMANCE_WEEKLY Table
-- =============================================
--
-- Purpose: Staging table for weekly Amazon search performance data by ASIN and Search Query
-- Project: onyga-482313
-- Dataset: OI
--
-- =============================================

CREATE OR REPLACE TABLE `onyga-482313.OI.STG_AMAZON_SEARCH_PERFORMANCE_WEEKLY` (
  -- Primary Key Dimensions
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
  
  -- Primary Key
  PRIMARY KEY (Reporting_Date, ASIN, Search_Query) NOT ENFORCED
)
PARTITION BY DATE_TRUNC(Reporting_Date, YEAR)
CLUSTER BY ASIN, Reporting_Date;

-- =============================================
-- TABLE DESCRIPTION
-- =============================================
--
-- This staging table holds weekly Amazon search performance data aggregated by:
-- - Reporting_Date: The week reporting date
-- - ASIN: Amazon Standard Identification Number
-- - Search_Query: The search query term
--
-- Key Features:
-- - Contains both overall performance metrics and Amazon-specific metrics
-- - Search_Query_Score provides relevance/quality scoring for the search query
-- - Partitioned by year for efficient querying
-- - Clustered by ASIN and Reporting_Date for optimal performance
--
-- Performance Metrics:
-- - Impressions, Clicks, Cart_Adds, ORDERS: Overall metrics
-- - AMAZON_IMPRESSIONS, AMAZON_Clicks, AMAZON_Cart_Adds, AMAZON_ORDERS: Amazon-specific metrics
--
-- =============================================
