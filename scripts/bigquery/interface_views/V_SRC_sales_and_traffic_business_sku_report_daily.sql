-- =============================================
-- OI Database Project - V_SRC_sales_and_traffic_business_sku_report_daily
-- =============================================
--
-- Purpose: Standardized view for daily sales and traffic data by SKU/ASIN
-- Business Logic: Maps Fivetran column names to standardized OI naming convention
-- Dependencies: 
--   - fivetran-hl.amazon_selling_partner.sales_and_traffic_business_sku_report_daily
-- Project: onyga-482313
-- Dataset: OI
--
-- =============================================

CREATE OR REPLACE VIEW `onyga-482313.OI.V_SRC_sales_and_traffic_business_sku_report_daily` AS

SELECT 
  child_asin, 
  end_date AS date, 
  marketplace_id, 
  parent_asin, 
  sku,
  sales_by_asin_units_ordered AS SALES_QUANTITY,
  sales_by_asin_ordered_product_sales_amount AS SALES_AMOUNT,
  sales_by_asin_ordered_product_sales_currency_code AS SALES_CURRENCY,
  sales_by_asin_total_order_items AS SALES_ORDERS,
  traffic_by_asin_sessions AS asin_sessions,
  -- traffic_by_asin_session_percentage, 
  traffic_by_asin_page_views AS page_views,
  -- traffic_by_asin_page_views_percentage,  
  -- traffic_by_asin_unit_session_percentage
FROM `fivetran-hl.amazon_selling_partner.sales_and_traffic_business_sku_report_daily`;

-- =============================================
-- VIEW DESCRIPTION
-- =============================================
--
-- This view provides standardized access to daily sales and traffic data from Amazon Seller Central.
-- Maps Fivetran column names to OI naming convention for consistency.
--
-- Key Fields:
-- - child_asin: Product ASIN
-- - date: Report date (from end_date)
-- - marketplace_id: Marketplace identifier
-- - parent_asin: Parent product ASIN
-- - sku: Merchant SKU
-- - SALES_QUANTITY: Units ordered
-- - SALES_AMOUNT: Total sales amount
-- - SALES_CURRENCY: Currency code
-- - SALES_ORDERS: Total order items
-- - asin_sessions: Unique sessions (traffic_by_asin_sessions)
-- - page_views: Page views (traffic_by_asin_page_views)
--
-- =============================================
