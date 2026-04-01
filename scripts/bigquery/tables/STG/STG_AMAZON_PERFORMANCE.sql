-- =============================================
-- OI Database Project - STG_AMAZON_PERFORMANCE Table
-- =============================================
--
-- Purpose: Staging table for Amazon sales and traffic performance data
-- Method: TRUNCATE + INSERT (full refresh)
-- Source: V_SRC_sales_and_traffic_business_sku_report_daily
-- Project: onyga-482313
-- Dataset: OI
--
-- Logic:
-- - Loads all data from V_SRC_sales_and_traffic_business_sku_report_daily
-- - Aggregates at DATE + PURCHASED_ASIN level
-- - IS_LOADED flag: false if ASIN_PAGE_VIEWS is NULL or 0, else true
--
-- =============================================

CREATE OR REPLACE TABLE `onyga-482313.OI.STG_AMAZON_PERFORMANCE` (
  -- Aggregated daily performance by purchased ASIN
  DATE DATE NOT NULL,
  PURCHASED_ASIN STRING NOT NULL,
  PURCHASED_ORDERS INT64,
  PURCHASED_UNITS INT64,
  PURCHASED_AMOUNT_USD FLOAT64,
  ASIN_SESSIONS INT64,
  ASIN_PAGE_VIEWS INT64,
  IS_LOADED BOOL,  -- false if ASIN_PAGE_VIEWS is NULL or 0, else true
  
  -- Primary Key
  PRIMARY KEY (DATE, PURCHASED_ASIN) NOT ENFORCED
)
PARTITION BY DATE_TRUNC(DATE, YEAR)
CLUSTER BY PURCHASED_ASIN, DATE;

-- =============================================
-- TABLE DESCRIPTION
-- =============================================
--
-- This staging table holds aggregated Amazon sales and traffic performance data
-- by DATE and PURCHASED_ASIN (child_asin) from Seller Central.
-- It is refreshed using TRUNCATE + INSERT method and runs before STG_AMAZON_ADS.
--
-- Key Features:
-- - Aggregated at DATE + PURCHASED_ASIN level
-- - PURCHASED_ORDERS / PURCHASED_UNITS / PURCHASED_AMOUNT_USD come from sales_by_asin_* measures
-- - ASIN_SESSIONS / ASIN_PAGE_VIEWS come from traffic_by_asin_* measures
-- - IS_LOADED indicates if Seller Central data is valid (ASIN_PAGE_VIEWS > 0)
--
-- =============================================
