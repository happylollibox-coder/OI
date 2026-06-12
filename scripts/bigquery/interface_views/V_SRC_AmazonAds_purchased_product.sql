-- =============================================
-- OI Database Project - V_SRC_AmazonAds_purchased_product
-- =============================================
--
-- Purpose: Product purchase attribution across different campaign types
-- Business Logic: Triple UNION combining targeting, keyword, and SB campaigns
-- Dependencies: Multiple purchased_product tables from fivetran-hl.amazon_ads
-- Project: onyga-482313
-- Dataset: OI
-- Updated: 2025-01-01
-- Enhanced: 2026-02-02 - Enriched advertised_asin for SB campaigns using search terms with units > 0
-- Enhanced: 2026-02-14 - Added attribution window variants (_1d, _7d, _14d, _30d) for orders, units, sales
--
-- =============================================

DROP VIEW IF EXISTS `OI.V_SRC_AmazonAds_purchased_product`;
CREATE VIEW `onyga-482313.OI.V_SRC_AmazonAds_purchased_product`
AS 
WITH 
-- SB: Get advertised ASIN from ad_report for all campaign+ad_group+date combinations
-- Match based on purchased_product having units (not search terms with units > 0)
sb_ad_report_agg AS (
  SELECT 
    campaign_id,
    ad_group_id,
    date,
    advertised_asin,
    SUM(attributed_sales_14_d) AS total_sales
  FROM `onyga-482313.OI.V_SRC_AmazonAds_sb_ad_report`
  WHERE advertised_asin IS NOT NULL
  GROUP BY campaign_id, ad_group_id, date, advertised_asin
),
sb_primary_advertised_asin AS (
  SELECT 
    campaign_id,
    ad_group_id,
    date,
    ARRAY_AGG(advertised_asin ORDER BY total_sales DESC, advertised_asin ASC LIMIT 1)[OFFSET(0)] AS Advertised_sell_asin
  FROM sb_ad_report_agg
  GROUP BY campaign_id, ad_group_id, date
)
SELECT 
  t.campaign_id,
  t.ad_group_id,
  t.keyword_id,
  t.date,
  t.purchased_asin,
  t.match_type,
  t.campaign_budget_currency_code,
  -- Enrich advertised_asin: SP uses source value, SB uses enriched value from search terms + ad report
  COALESCE(
    sb_asin.Advertised_sell_asin,  -- SB: Use enriched value (replaces 'Unknown')
    t.advertised_asin,  -- SP: Use source advertised_asin (already exists in source data)
    'Unknown'  -- Fallback: rare cases where Amazon API returns NULL (e.g. self-purchase zero-measure rows)
  ) AS advertised_asin,
  t.advertised_sku,
  t.orders,
  t.units,
  t.sales,
  -- Attribution window variants
  t.orders_1d,
  t.orders_7d,
  t.orders_14d,
  t.orders_30d,
  t.units_1d,
  t.units_7d,
  t.units_14d,
  t.units_30d,
  t.sales_1d,
  t.sales_7d,
  t.sales_14d,
  t.sales_30d,
  COUNT(*) OVER (PARTITION BY t.date, t.campaign_id, t.ad_group_id, t.keyword_id) AS num_SKU_in_date_keyword,
  t.data_source
FROM (
  SELECT 
    CAST(campaign_id AS STRING) campaign_id,
    CAST(ad_group_id AS STRING) AS ad_group_id,
    CAST(keyword_id AS STRING) AS keyword_id,
    date,
    purchased_asin,
    match_type, 
    campaign_budget_currency_code, 
    advertised_asin, 
    advertised_sku,
    purchases_other_sku_30_d orders, 
    units_sold_other_sku_30_d units,
    sales_other_sku_30_d sales,
    -- Attribution window variants
    purchases_other_sku_1_d AS orders_1d,
    purchases_other_sku_7_d AS orders_7d,
    purchases_other_sku_14_d AS orders_14d,
    purchases_other_sku_30_d AS orders_30d,
    units_sold_other_sku_1_d AS units_1d,
    units_sold_other_sku_7_d AS units_7d,
    units_sold_other_sku_14_d AS units_14d,
    units_sold_other_sku_30_d AS units_30d,
    sales_other_sku_1_d AS sales_1d,
    sales_other_sku_7_d AS sales_7d,
    sales_other_sku_14_d AS sales_14d,
    sales_other_sku_30_d AS sales_30d,
    'SP_product_targeting' AS data_source
  FROM `fivetran-hl`.amazon_ads.purchased_product_targeting_report
  UNION ALL
  SELECT 
    CAST(campaign_id AS STRING) campaign_id,
    CAST(ad_group_id AS STRING) AS ad_group_id,
    CAST(keyword_id AS STRING) AS keyword_id,
    date,
    purchased_asin,
    match_type, 
    campaign_budget_currency_code, 
    advertised_asin, 
    advertised_sku,
    purchases_other_sku_30_d orders, 
    units_sold_other_sku_30_d units,
    sales_other_sku_30_d sales,
    -- Attribution window variants
    purchases_other_sku_1_d AS orders_1d,
    purchases_other_sku_7_d AS orders_7d,
    purchases_other_sku_14_d AS orders_14d,
    purchases_other_sku_30_d AS orders_30d,
    units_sold_other_sku_1_d AS units_1d,
    units_sold_other_sku_7_d AS units_7d,
    units_sold_other_sku_14_d AS units_14d,
    units_sold_other_sku_30_d AS units_30d,
    sales_other_sku_1_d AS sales_1d,
    sales_other_sku_7_d AS sales_7d,
    sales_other_sku_14_d AS sales_14d,
    sales_other_sku_30_d AS sales_30d,
    'SP' AS data_source
  FROM `fivetran-hl`.amazon_ads.purchased_product_keyword_report
  UNION ALL
  SELECT 
    CAST(campaign_id AS STRING) campaign_id,
    CAST(ad_group_id AS STRING) AS ad_group_id,
    '-1' AS keyword_id,
    date, 
    purchased_asin,
    'Unknown' match_type, 
    campaign_budget_currency_code,
    'Unknown' advertised_asin, 
    'Unknown' advertised_sku,
    orders_14_d orders, 
    units_sold_14_d units,
    sales_14_d sales,
    -- Attribution window variants (SB only has 14d)
    CAST(NULL AS INT64) AS orders_1d,
    CAST(NULL AS INT64) AS orders_7d,
    orders_14_d AS orders_14d,
    CAST(NULL AS INT64) AS orders_30d,
    CAST(NULL AS INT64) AS units_1d,
    CAST(NULL AS INT64) AS units_7d,
    units_sold_14_d AS units_14d,
    CAST(NULL AS INT64) AS units_30d,
    CAST(NULL AS FLOAT64) AS sales_1d,
    CAST(NULL AS FLOAT64) AS sales_7d,
    sales_14_d AS sales_14d,
    CAST(NULL AS FLOAT64) AS sales_30d,
    'SB' AS data_source
  FROM `fivetran-hl`.amazon_ads.sb_purchased_product
) t
LEFT JOIN sb_primary_advertised_asin sb_asin
  ON t.campaign_id = sb_asin.campaign_id
  AND t.ad_group_id = sb_asin.ad_group_id
  AND t.date = sb_asin.date
  AND t.keyword_id = '-1'  -- Only match SB records
;
