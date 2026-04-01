-- =============================================
-- OI Database Project - V_CAMPAIGN_PLACEMENT_REPORT View
-- =============================================
--
-- Purpose: Unified placement-level performance report combining
--          Sponsored Products and Sponsored Brands placement data.
--          Shows daily impressions, clicks, cost, orders, sales per placement per campaign.
--
-- Sources:
--   - fivetran-hl.amazon_ads.campaign_placement_report (SP: Sponsored Products)
--   - fivetran-hl.amazon_ads.sb_placement_report (SB: Sponsored Brands / Video)
--
-- Placement values (normalized):
--   TOP_OF_SEARCH, DETAIL_PAGE, REST_OF_SEARCH, OTHER, OFF_AMAZON, HOMEPAGE
--
-- Project: onyga-482313
-- Dataset: OI
--
-- =============================================

CREATE OR REPLACE VIEW `onyga-482313.OI.V_CAMPAIGN_PLACEMENT_REPORT`
AS

-- Sponsored Products placement report
SELECT
  CAST(sp.campaign_id AS STRING) as campaign_id,
  'SP' as campaign_source,
  sp.date as report_date,
  -- Normalize placement names to a standard enum
  CASE sp.placement
    WHEN 'Top of Search on-Amazon' THEN 'TOP_OF_SEARCH'
    WHEN 'Detail Page on-Amazon' THEN 'DETAIL_PAGE'
    WHEN 'Rest of Search' THEN 'REST_OF_SEARCH'
    WHEN 'Other on-Amazon' THEN 'OTHER'
    WHEN 'Off Amazon' THEN 'OFF_AMAZON'
    ELSE UPPER(REPLACE(sp.placement, ' ', '_'))
  END as placement,
  sp.placement as placement_raw,
  sp.campaign_bidding_strategy as bidding_strategy,
  COALESCE(sp.impressions, 0) as impressions,
  COALESCE(sp.clicks, 0) as clicks,
  ROUND(COALESCE(sp.cost, 0), 2) as cost,
  COALESCE(sp.purchases_14_d, 0) as orders,
  COALESCE(sp.units_sold_clicks_14_d, 0) as units,
  ROUND(COALESCE(sp.sales_14_d, 0), 2) as sales,
  -- Same-SKU (own product only, not cross-sell)
  COALESCE(sp.purchases_same_sku_14_d, 0) as orders_same_sku,
  ROUND(COALESCE(sp.attributed_sales_same_sku_14_d, 0), 2) as sales_same_sku,
  -- Derived
  ROUND(SAFE_DIVIDE(sp.sales_14_d, NULLIF(sp.cost, 0)), 2) as roas,
  ROUND(SAFE_DIVIDE(sp.cost, NULLIF(sp.clicks, 0)), 2) as cpc,
  ROUND(SAFE_DIVIDE(sp.clicks, NULLIF(sp.impressions, 0)) * 100, 2) as ctr_pct,
  ROUND(SAFE_DIVIDE(sp.purchases_14_d, NULLIF(sp.clicks, 0)) * 100, 2) as conversion_rate_pct,
  -- New-to-brand (not available for SP)
  CAST(NULL AS INT64) as orders_new_to_brand,
  CAST(NULL AS FLOAT64) as sales_new_to_brand,
  sp._fivetran_synced
FROM `fivetran-hl`.amazon_ads.campaign_placement_report sp

UNION ALL

-- Sponsored Brands placement report
SELECT
  sb.campaign_id as campaign_id,
  'SB' as campaign_source,
  sb.report_date,
  -- Normalize placement names
  CASE sb.placement
    WHEN 'Top of Search on-Amazon' THEN 'TOP_OF_SEARCH'
    WHEN 'Detail Page on-Amazon' THEN 'DETAIL_PAGE'
    WHEN 'Other on-Amazon' THEN 'OTHER'
    WHEN 'Homepage on-Amazon' THEN 'HOMEPAGE'
    ELSE UPPER(REPLACE(sb.placement, ' ', '_'))
  END as placement,
  sb.placement as placement_raw,
  CAST(NULL AS STRING) as bidding_strategy,
  COALESCE(sb.impressions, 0) as impressions,
  COALESCE(sb.clicks, 0) as clicks,
  ROUND(COALESCE(sb.cost, 0), 2) as cost,
  COALESCE(sb.attributed_conversions_14_d, 0) as orders,
  COALESCE(sb.units_sold_14_d, 0) as units,
  ROUND(COALESCE(sb.attributed_sales_14_d, 0), 2) as sales,
  -- Same-SKU
  COALESCE(sb.attributed_conversions_14_d_same_sku, 0) as orders_same_sku,
  ROUND(COALESCE(sb.attributed_sales_14_d_same_sku, 0), 2) as sales_same_sku,
  -- Derived
  ROUND(SAFE_DIVIDE(sb.attributed_sales_14_d, NULLIF(sb.cost, 0)), 2) as roas,
  ROUND(SAFE_DIVIDE(sb.cost, NULLIF(sb.clicks, 0)), 2) as cpc,
  ROUND(SAFE_DIVIDE(sb.clicks, NULLIF(sb.impressions, 0)) * 100, 2) as ctr_pct,
  ROUND(SAFE_DIVIDE(sb.attributed_conversions_14_d, NULLIF(sb.clicks, 0)) * 100, 2) as conversion_rate_pct,
  -- New-to-brand (SB only)
  COALESCE(sb.attributed_orders_new_to_brand_14_d, 0) as orders_new_to_brand,
  ROUND(COALESCE(sb.attributed_sales_new_to_brand_14_d, 0), 2) as sales_new_to_brand,
  sb._fivetran_synced
FROM `fivetran-hl`.amazon_ads.sb_placement_report sb;
