-- =============================================
-- Unified SCP Data View
-- =============================================
-- Purpose: UNION view combining data from:
--   - onyga-482313.OI.SCP_ASIN_View_Week (SCP source)
--   - openbridge-482712.DB.sp_ba_search_catalog_by_week_v1 (OpenBridge source)
-- 
-- This view maps both sources to a common schema, extracting Year/Week
-- from OpenBridge dates and mapping column names to match SCP structure.
-- =============================================

CREATE OR REPLACE VIEW `onyga-482313.OI.V_UNIFIED_SCP_DATA` AS

-- ==========================================
-- SCP Source Data
-- ==========================================
SELECT 
  'SCP' as source_system,
  Year,
  Week,
  ASIN,
  PARSE_DATE('%d/%m/%Y', Start_date) as start_date,
  PARSE_DATE('%d/%m/%Y', End_Date) as end_date,
  PARSE_DATE('%d/%m/%Y', Reporting_Date) as reporting_date,
  
  -- Product Information
  ASIN_Title,
  Category,
  
  -- Impressions Metrics
  Impressions_Impressions,
  Impressions_Rating_Median,
  Impressions_Price_Median,
  Impressions_Same_Day_Shipping_Speed,
  Impressions_1D_Shipping_Speed,
  Impressions_2D_Shipping_Speed,
  
  -- Clicks Metrics
  Clicks_Clicks,
  Clicks_Click_Rate_CTR,
  Clicks_Price_Median,
  Clicks_Same_Day_Shipping_Speed,
  Clicks_1D_Shipping_Speed,
  Clicks_2D_Shipping_Speed,
  
  -- Cart Adds Metrics
  Cart_Adds_Cart_Adds,
  Cart_Adds_Price_Median,
  Cart_Adds_Same_Day_Shipping_Speed,
  Cart_Adds_1D_Shipping_Speed,
  Cart_Adds_2D_Shipping_Speed,
  
  -- Purchases Metrics
  Purchases_Purchases,
  Purchases_Search_Traffic_Sales,
  Purchases_Conversion_Rate_Percent,
  Purchases_Rating_Median,
  Purchases_Price_Median,
  Purchases_Same_Day_Shipping_Speed,
  Purchases_1D_Shipping_Speed,
  Purchases_2D_Shipping_Speed,
  
  -- Metadata (SCP-specific)
  Start_date as start_date_raw,
  End_Date as end_date_raw,
  Reporting_Date as reporting_date_raw,
  CAST(NULL AS STRING) as ob_file_name,
  CAST(NULL AS STRING) as ob_marketplace_id,
  CAST(NULL AS STRING) as ob_seller_id,
  CAST(NULL AS STRING) as ob_transaction_id,
  CAST(NULL AS DATETIME) as ob_modified_date,
  CAST(NULL AS STRING) as ob_processed_at

FROM `onyga-482313.OI.SCP_ASIN_View_Week`

UNION ALL

-- ==========================================
-- OpenBridge Source Data
-- ==========================================
SELECT 
  'OpenBridge' as source_system,
  EXTRACT(YEAR FROM ob_date) as Year,
  EXTRACT(WEEK FROM ob_date) as Week,
  ASIN,
  DATE_TRUNC(ob_date, WEEK(MONDAY)) as start_date,  -- Week starts on Monday
  DATE_ADD(DATE_TRUNC(ob_date, WEEK(MONDAY)), INTERVAL 6 DAY) as end_date,  -- Week ends on Sunday
  ob_date as reporting_date,
  
  -- Product Information (OpenBridge doesn't have these)
  CAST(NULL AS STRING) as ASIN_Title,
  CAST(NULL AS STRING) as Category,
  
  -- Impressions Metrics - Map from OpenBridge
  impression_data_impression_count as Impressions_Impressions,
  CAST(NULL AS FLOAT64) as Impressions_Rating_Median,  -- Not available in OpenBridge
  impression_data_impression_median_price_amount as Impressions_Price_Median,
  impression_data_same_day_shipping_impression_count as Impressions_Same_Day_Shipping_Speed,
  impression_data_one_day_shipping_impression_count as Impressions_1D_Shipping_Speed,
  impression_data_two_day_shipping_impression_count as Impressions_2D_Shipping_Speed,
  
  -- Clicks Metrics - Map from OpenBridge
  click_data_click_count as Clicks_Clicks,
  click_data_click_rate as Clicks_Click_Rate_CTR,
  click_data_clicked_median_price_amount as Clicks_Price_Median,
  click_data_same_day_shipping_click_count as Clicks_Same_Day_Shipping_Speed,
  click_data_one_day_shipping_click_count as Clicks_1D_Shipping_Speed,
  click_data_two_day_shipping_click_count as Clicks_2D_Shipping_Speed,
  
  -- Cart Adds Metrics - Map from OpenBridge
  cart_add_data_cart_add_count as Cart_Adds_Cart_Adds,
  cart_add_data_cart_added_median_price_amount as Cart_Adds_Price_Median,
  cart_add_data_same_day_shipping_cart_add_count as Cart_Adds_Same_Day_Shipping_Speed,
  cart_add_data_one_day_shipping_cart_add_count as Cart_Adds_1D_Shipping_Speed,
  cart_add_data_two_day_shipping_cart_add_count as Cart_Adds_2D_Shipping_Speed,
  
  -- Purchases Metrics - Map from OpenBridge
  purchase_data_purchase_count as Purchases_Purchases,
  purchase_data_search_traffic_sales_amount as Purchases_Search_Traffic_Sales,
  purchase_data_conversion_rate as Purchases_Conversion_Rate_Percent,
  CAST(NULL AS FLOAT64) as Purchases_Rating_Median,  -- Not available in OpenBridge
  purchase_data_purchase_median_price_amount as Purchases_Price_Median,
  purchase_data_same_day_shipping_purchase_count as Purchases_Same_Day_Shipping_Speed,
  purchase_data_one_day_shipping_purchase_count as Purchases_1D_Shipping_Speed,
  purchase_data_two_day_shipping_purchase_count as Purchases_2D_Shipping_Speed,
  
  -- Metadata (OpenBridge-specific)
  CAST(NULL AS STRING) as start_date_raw,
  CAST(NULL AS STRING) as end_date_raw,
  CAST(NULL AS STRING) as reporting_date_raw,
  ob_file_name,
  ob_marketplace_id,
  ob_seller_id,
  ob_transaction_id,
  ob_modified_date,
  ob_processed_at

FROM `openbridge-482712.DB.sp_ba_search_catalog_by_week_v1`
WHERE ASIN IS NOT NULL;
