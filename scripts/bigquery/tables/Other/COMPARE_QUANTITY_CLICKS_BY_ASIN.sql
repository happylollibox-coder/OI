-- =============================================
-- OI Database Project - COMPARE_QUANTITY_CLICKS_BY_ASIN Table
-- =============================================
--
-- Purpose: Comparison table for Sales & Traffic vs Amazon Ads metrics per ASIN and date
-- Method: TRUNCATE + INSERT (full refresh)
-- Sources: 
--   - V_SRC_sales_and_traffic_business_sku_report_daily (sales_quantity, CLICKS)
--   - STG_AMAZON_ADS (ads_units, ads_clicks)
-- Project: onyga-482313
-- Dataset: OI
--
-- =============================================

CREATE OR REPLACE TABLE `onyga-482313.OI.COMPARE_QUANTITY_CLICKS_BY_ASIN` (
  asin STRING NOT NULL,
  date DATE NOT NULL,
  
  -- Sales & Traffic measures
  sales_quantity INT64,  -- Units ordered from sales & traffic report
  traffic_clicks INT64,  -- Page views from sales & traffic report (CLICKS field)
  
  -- Amazon Ads measures
  ads_units INT64,  -- Units from Amazon Ads attribution
  ads_clicks INT64,  -- Clicks from Amazon Ads
  
  -- Differences
  quantity_minus_units INT64,  -- sales_quantity - ads_units
  traffic_clicks_minus_ads_clicks INT64,  -- traffic_clicks - ads_clicks
  
  -- Ratios (percentages)
  quantity_pct_of_units FLOAT64,  -- (sales_quantity / ads_units) * 100
  traffic_clicks_pct_of_ads_clicks FLOAT64,  -- (traffic_clicks / ads_clicks) * 100
  
  -- Data source indicator
  data_source STRING,  -- 'Both', 'Ads Only', 'Sales Only'
  
  -- Primary Key
  PRIMARY KEY (asin, date) NOT ENFORCED
)
PARTITION BY DATE_TRUNC(date, YEAR)
CLUSTER BY asin, date;

-- =============================================
-- TABLE DESCRIPTION
-- =============================================
--
-- This table compares sales/traffic metrics with Amazon Ads metrics per ASIN and date.
--
-- Key Comparisons:
-- 1. Quantity vs Units:
--    - sales_quantity: Total units ordered (from Seller Central sales report)
--    - ads_units: Units attributed to Amazon Ads (30-day attribution window)
--    - quantity_minus_units: Difference (positive = more sales than ads, negative = more ads than sales)
--    - quantity_pct_of_units: Percentage showing how sales_quantity relates to ads_units
--
-- 2. Clicks vs CLICKS:
--    - traffic_clicks: Page views from Seller Central traffic report
--    - ads_clicks: Clicks from Amazon Ads campaigns
--    - traffic_clicks_minus_ads_clicks: Difference
--    - traffic_clicks_pct_of_ads_clicks: Percentage showing how traffic_clicks relates to ads_clicks
--
-- Data Source:
-- - 'Both': ASIN appears in both datasets for this date
-- - 'Ads Only': ASIN only in Amazon Ads (no sales/traffic data)
-- - 'Sales Only': ASIN only in Sales & Traffic (no ads data)
--
-- Notes:
-- - Attribution windows differ: Ads uses 30-day window, Sales is daily
-- - Some ASINs may show ads_units > sales_quantity due to attribution timing
-- - traffic_clicks represents all page views, not just ad-driven traffic
--
-- =============================================
