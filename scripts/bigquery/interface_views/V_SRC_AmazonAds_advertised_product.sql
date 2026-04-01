-- =============================================
-- OI Database Project - V_SRC_AmazonAds_advertised_product
-- =============================================
--
-- Purpose: Interface view for advertised product report data from Fivetran
-- Business Logic: Direct mapping from fivetran-hl.amazon_ads.advertised_product_report
-- Dependencies: fivetran-hl.amazon_ads.advertised_product_report
-- Project: onyga-482313
-- Dataset: OI
-- Updated: 2026-01-29
--
-- =============================================

DROP VIEW IF EXISTS `OI.V_SRC_AmazonAds_advertised_product`;
CREATE VIEW `onyga-482313.OI.V_SRC_AmazonAds_advertised_product`
AS 
SELECT 
  -- Campaign/Ad Group/Ad Identifiers (cast to STRING for consistency)
  CAST(campaign_id AS STRING) AS campaign_id,
  CAST(ad_group_id AS STRING) AS ad_group_id,
  CAST(ad_id AS STRING) AS ad_id,
  
  -- Date
  date,
  CAST(date AS DATE) AS report_date,
  
  -- Product Identifiers
  advertised_asin,
  advertised_sku,
  
  -- Performance Metrics - Impressions & Clicks
  impressions,
  clicks,
  cost_per_click,
  cost,
  click_through_rate,
  spend,
  
  -- Purchase Metrics - Multiple Time Windows
  purchases_1_d AS orders_1d,
  purchases_7_d AS orders_7d,
  purchases_14_d AS orders_14d,
  purchases_30_d AS orders_30d,
  
  -- Same SKU Purchase Metrics
  purchases_same_sku_1_d AS orders_same_sku_1d,
  purchases_same_sku_7_d AS orders_same_sku_7d,
  purchases_same_sku_14_d AS orders_same_sku_14d,
  purchases_same_sku_30_d AS orders_same_sku_30d,
  
  -- Units Sold Metrics
  units_sold_clicks_1_d AS units_1d,
  units_sold_clicks_7_d AS units_7d,
  units_sold_clicks_14_d AS units_14d,
  units_sold_clicks_30_d AS units_30d,
  
  units_sold_same_sku_1_d AS units_same_sku_1d,
  units_sold_same_sku_7_d AS units_same_sku_7d,
  units_sold_same_sku_14_d AS units_same_sku_14d,
  units_sold_same_sku_30_d AS units_same_sku_30d,
  
  units_sold_other_sku_7_d AS units_other_sku_7d,
  
  -- Sales Metrics - Multiple Time Windows
  sales_1_d,
  sales_7_d,
  sales_14_d,
  sales_30_d,
  
  -- Attributed Sales Same SKU
  attributed_sales_same_sku_1_d AS sales_same_sku_1d,
  attributed_sales_same_sku_7_d AS sales_same_sku_7d,
  attributed_sales_same_sku_14_d AS sales_same_sku_14d,
  attributed_sales_same_sku_30_d AS sales_same_sku_30d,
  
  sales_other_sku_7_d,
  
  -- Engagement Metrics
  add_to_list,
  qualified_borrows,
  royalty_qualified_borrows,
  
  -- Kindle Edition Metrics (if applicable)
  kindle_edition_normalized_pages_read_14_d,
  kindle_edition_normalized_pages_royalties_14_d,
  
  -- Efficiency Metrics
  acos_clicks_7_d AS acos_7d,
  acos_clicks_14_d AS acos_14d,
  roas_clicks_7_d AS roas_7d,
  roas_clicks_14_d AS roas_14d,
  
  -- Campaign Budget Information
  campaign_budget_currency_code,
  campaign_budget_amount,
  campaign_budget_type,
  
  -- Fivetran Metadata
  _fivetran_synced
  
FROM `fivetran-hl.amazon_ads.advertised_product_report`;

-- =============================================
-- VIEW DESCRIPTION
-- =============================================
--
-- This view provides standardized access to advertised product performance data
-- from Amazon Ads API via Fivetran.
--
-- Key Fields:
-- - campaign_id, ad_group_id, ad_id: Campaign structure identifiers
-- - date: Report date
-- - advertised_asin: The ASIN that was advertised
-- - advertised_sku: The SKU that was advertised
-- - Performance metrics: impressions, clicks, cost, orders, sales, units
--   (available in 1-day, 7-day, 14-day, and 30-day attribution windows)
-- - Efficiency metrics: ACOS, ROAS (7-day and 14-day windows)
--
-- This view is useful for:
-- - Understanding which products are being advertised in campaigns
-- - Analyzing advertised product performance at the product level
-- - Matching advertised products to search terms and purchases
-- - Product-level attribution analysis (not keyword-level)
--
-- Note: This report is at the product/ad level, not keyword level.
-- There is no keyword_id in this report.
--
-- =============================================
