-- =============================================
-- OI Database Project - V_SRC_AmazonAds_SearchTerms_with_ASIN
-- =============================================
--
-- Purpose: Search term performance analysis with ASIN data from Amazon SP
-- Business Logic: Extends V_SRC_AmazonAds_SearchTerms with purchased_asin from purchased_product table
-- Dependencies: V_SRC_AmazonAds_SearchTerms + V_SRC_AmazonAds_purchased_product
-- Project: onyga-482313
-- Dataset: OI
-- Created: Based on V_SRC_AmazonAds_SearchTerms.sql
--
-- =============================================

DROP VIEW IF EXISTS `onyga-482313.OI.V_SRC_AmazonAds_SearchTerms_with_ASIN`;
CREATE VIEW `onyga-482313.OI.V_SRC_AmazonAds_SearchTerms_with_ASIN` AS

-- Base SearchTerms data
WITH search_terms_base AS (
  SELECT *
  FROM `onyga-482313.OI.V_SRC_AmazonAds_SearchTerms`
),

-- ASIN data from purchased products (aggregated to avoid duplicates)
asin_data AS (
  SELECT
    campaign_id,
    ad_group_id,
    keyword_id,
    date,
    -- Collect all unique purchased ASINs for each keyword-date combination
    ARRAY_AGG(DISTINCT purchased_asin IGNORE NULLS) as purchased_asins,
    ARRAY_AGG(DISTINCT advertised_asin IGNORE NULLS) as advertised_asins,
    -- Take the first non-null ASIN as primary
    ARRAY_AGG(DISTINCT purchased_asin IGNORE NULLS LIMIT 1)[OFFSET(0)] as primary_purchased_asin,
    ARRAY_AGG(DISTINCT advertised_asin IGNORE NULLS LIMIT 1)[OFFSET(0)] as primary_advertised_asin,
    -- Aggregate purchase metrics
    SUM(orders) as total_orders_from_asins,
    SUM(units) as total_units_from_asins,
    SUM(sales) as total_sales_from_asins,
    COUNT(DISTINCT purchased_asin) as unique_purchased_asins,
    COUNT(DISTINCT advertised_asin) as unique_advertised_asins
  FROM `onyga-482313.OI.V_SRC_AmazonAds_purchased_product`
  GROUP BY campaign_id, ad_group_id, keyword_id, date
)

-- Join SearchTerms with ASIN data using multi-level attribution
SELECT
  st.*,

  -- ASIN information from purchased products (multi-level attribution)
  COALESCE(ad_keyword.primary_purchased_asin, ad_adgroup.primary_purchased_asin, ad_campaign.primary_purchased_asin) as primary_purchased_asin,
  COALESCE(ad_keyword.primary_advertised_asin, ad_adgroup.primary_advertised_asin, ad_campaign.primary_advertised_asin) as primary_advertised_asin,

  -- Arrays (prefer keyword-level, fallback to ad group, then campaign)
  COALESCE(ad_keyword.purchased_asins, ad_adgroup.purchased_asins, ad_campaign.purchased_asins) as purchased_asins,
  COALESCE(ad_keyword.advertised_asins, ad_adgroup.advertised_asins, ad_campaign.advertised_asins) as advertised_asins,

  -- Unique counts
  COALESCE(ad_keyword.unique_purchased_asins, ad_adgroup.unique_purchased_asins, ad_campaign.unique_purchased_asins) as unique_purchased_asins,
  COALESCE(ad_keyword.unique_advertised_asins, ad_adgroup.unique_advertised_asins, ad_campaign.unique_advertised_asins) as unique_advertised_asins,

  -- Aggregated purchase metrics
  COALESCE(ad_keyword.total_orders_from_asins, ad_adgroup.total_orders_from_asins, ad_campaign.total_orders_from_asins) as total_orders_from_asins,
  COALESCE(ad_keyword.total_units_from_asins, ad_adgroup.total_units_from_asins, ad_campaign.total_units_from_asins) as total_units_from_asins,
  COALESCE(ad_keyword.total_sales_from_asins, ad_adgroup.total_sales_from_asins, ad_campaign.total_sales_from_asins) as total_sales_from_asins,

  -- Attribution level indicator
  CASE
    WHEN ad_keyword.primary_purchased_asin IS NOT NULL THEN 'Keyword Level'
    WHEN ad_adgroup.primary_purchased_asin IS NOT NULL THEN 'Ad Group Level'
    WHEN ad_campaign.primary_purchased_asin IS NOT NULL THEN 'Campaign Level'
    WHEN ad_keyword.primary_advertised_asin IS NOT NULL THEN 'Advertised ASIN (Keyword)'
    WHEN ad_adgroup.primary_advertised_asin IS NOT NULL THEN 'Advertised ASIN (Ad Group)'
    WHEN ad_campaign.primary_advertised_asin IS NOT NULL THEN 'Advertised ASIN (Campaign)'
    ELSE 'No ASIN Data'
  END as asin_attribution_level,

  -- Conversion rates using ASIN purchase data
  CASE
    WHEN st.clicks > 0 THEN ROUND(COALESCE(ad_keyword.total_orders_from_asins, ad_adgroup.total_orders_from_asins, ad_campaign.total_orders_from_asins) / st.clicks, 4)
    ELSE NULL
  END as asin_conversion_rate,

  CASE
    WHEN st.impressions > 0 THEN ROUND(COALESCE(ad_keyword.total_orders_from_asins, ad_adgroup.total_orders_from_asins, ad_campaign.total_orders_from_asins) / st.impressions, 6)
    ELSE NULL
  END as asin_conversion_rate_from_impressions

FROM search_terms_base st
-- Keyword-level attribution (most specific)
LEFT JOIN asin_data ad_keyword
  ON st.campaign_id = ad_keyword.campaign_id
  AND st.ad_group_id = ad_keyword.ad_group_id
  AND st.keyword_id = ad_keyword.keyword_id
  AND st.date = ad_keyword.date

-- Ad group-level attribution (fallback)
LEFT JOIN (
  SELECT
    campaign_id,
    ad_group_id,
    date,
    ARRAY_AGG(DISTINCT purchased_asin IGNORE NULLS LIMIT 1)[OFFSET(0)] as primary_purchased_asin,
    ARRAY_AGG(DISTINCT advertised_asin IGNORE NULLS LIMIT 1)[OFFSET(0)] as primary_advertised_asin,
    ARRAY_AGG(DISTINCT purchased_asin IGNORE NULLS) as purchased_asins,
    ARRAY_AGG(DISTINCT advertised_asin IGNORE NULLS) as advertised_asins,
    COUNT(DISTINCT purchased_asin) as unique_purchased_asins,
    COUNT(DISTINCT advertised_asin) as unique_advertised_asins,
    SUM(orders) as total_orders_from_asins,
    SUM(units) as total_units_from_asins,
    SUM(sales) as total_sales_from_asins
  FROM `onyga-482313.OI.V_SRC_AmazonAds_purchased_product`
  GROUP BY campaign_id, ad_group_id, date
) ad_adgroup
  ON st.campaign_id = ad_adgroup.campaign_id
  AND st.ad_group_id = ad_adgroup.ad_group_id
  AND st.date = ad_adgroup.date
  AND ad_keyword.primary_purchased_asin IS NULL  -- Only use if keyword-level failed

-- Campaign-level attribution (broadest fallback)
LEFT JOIN (
  SELECT
    campaign_id,
    date,
    ARRAY_AGG(DISTINCT purchased_asin IGNORE NULLS LIMIT 1)[OFFSET(0)] as primary_purchased_asin,
    ARRAY_AGG(DISTINCT advertised_asin IGNORE NULLS LIMIT 1)[OFFSET(0)] as primary_advertised_asin,
    ARRAY_AGG(DISTINCT purchased_asin IGNORE NULLS) as purchased_asins,
    ARRAY_AGG(DISTINCT advertised_asin IGNORE NULLS) as advertised_asins,
    COUNT(DISTINCT purchased_asin) as unique_purchased_asins,
    COUNT(DISTINCT advertised_asin) as unique_advertised_asins,
    SUM(orders) as total_orders_from_asins,
    SUM(units) as total_units_from_asins,
    SUM(sales) as total_sales_from_asins
  FROM `onyga-482313.OI.V_SRC_AmazonAds_purchased_product`
  GROUP BY campaign_id, date
) ad_campaign
  ON st.campaign_id = ad_campaign.campaign_id
  AND st.date = ad_campaign.date
  AND ad_keyword.primary_purchased_asin IS NULL
  AND ad_adgroup.primary_purchased_asin IS NULL;  -- Only use if both keyword and ad group failed
