-- =============================================
-- OI Database Project - V_SRC_AmazonAds_sb_ad_report
-- =============================================
--
-- Purpose: Interface view for Sponsored Brands (SB) ad report data from Fivetran
-- Business Logic: Joins sb_ad_report with sb_creative_history to get creative information
-- Dependencies: fivetran-hl.amazon_ads.sb_ad_report, fivetran-hl.amazon_ads.sb_creative_history
-- Project: onyga-482313
-- Dataset: OI
-- Updated: 2026-01-31
--
-- =============================================

DROP VIEW IF EXISTS `OI.V_SRC_AmazonAds_sb_ad_report`;
CREATE VIEW `onyga-482313.OI.V_SRC_AmazonAds_sb_ad_report`
AS 
WITH base_data AS (
  SELECT 
    ar.campaign_id,
    ar.ad_group_id,
    ch.ad_id,
    ch._fivetran_id,
    ch.landing_page_type,
    ch.custom_image_crop_width,
    ch.custom_image_crop_height,
    ch.headline,
    ch.creation_time,
    ch.creative_version,
    ch.creative_type,
    ch.custom_image_url,
    -- AD_Advertised_ID: Use custom_image_url if not empty, otherwise use campaign_name|ad_group_name
    CASE 
      WHEN ch.custom_image_url IS NOT NULL AND ch.custom_image_url != '' 
      THEN ch.custom_image_url
      ELSE CONCAT(COALESCE(c.campaign_name, ar.campaign_id), '|', COALESCE(ag.ad_group_name, CAST(ar.ad_group_id AS STRING)))
    END AS AD_Advertised_ID,
    c.campaign_name,
    ag.ad_group_name,
    ar.clicks,
    ar.cost,
    ar.impressions,
    ar.viewable_impressions,
    ar.currency,
    ar.attributed_conversions_14_d,
    ar.attributed_sales_14_d,
    ar.report_date,
    CAST(ar.report_date AS DATE) AS date
  FROM `fivetran-hl.amazon_ads.sb_ad_report` ar
  LEFT JOIN (
    SELECT 
      _fivetran_id,
      ad_id,
      landing_page_type,
      custom_image_crop_width,
      custom_image_crop_height,
      headline,
      creation_time,
      creative_version,
      creative_type,
      custom_image_url,
      COALESCE(
        LEAD(creation_time) OVER (PARTITION BY ad_id ORDER BY creative_version) - INTERVAL 3 MILLISECOND,
        CURRENT_TIMESTAMP()
      ) AS C_END_DATE
    FROM `fivetran-hl.amazon_ads.sb_creative_history`
  ) ch 
    ON ch.ad_id = ar.ad_id 
    AND TIMESTAMP(ar.report_date) BETWEEN ch.creation_time AND ch.C_END_DATE
  LEFT JOIN `onyga-482313.OI.V_SRC_AmazonAds_campaign_history` c
    ON ar.campaign_id = c.campaign_id
    AND TIMESTAMP(ar.report_date) BETWEEN c.OI_start_date AND c.OI_end_date
  LEFT JOIN `onyga-482313.OI.V_SRC_AmazonAds_ad_group_history` ag
    ON ar.ad_group_id = ag.ad_group_id
    AND TIMESTAMP(ar.report_date) BETWEEN ag.OI_start_date AND ag.OI_end_date
)
SELECT 
  bd.campaign_id,
  bd.ad_group_id,
  bd.ad_id,
  bd._fivetran_id,
  bd.landing_page_type,
  bd.custom_image_crop_width,
  bd.custom_image_crop_height,
  bd.headline,
  bd.creation_time,
  bd.creative_version,
  bd.creative_type,
  bd.custom_image_url,
  bd.AD_Advertised_ID,
  bd.campaign_name,
  bd.ad_group_name,
  gc.target AS advertised_asin,  -- ASIN extracted from GENERAL_CONVERSION
  bd.clicks,
  bd.cost,
  bd.impressions,
  bd.viewable_impressions,
  bd.currency,
  bd.attributed_conversions_14_d,
  bd.attributed_sales_14_d,
  bd.report_date,
  bd.date
FROM base_data bd
LEFT JOIN `onyga-482313.OI.GENERAL_CONVERSION` gc
  ON gc.list_of_values = 'ad_URL_ASIN'
  AND gc.`key` = bd.AD_Advertised_ID;

-- =============================================
-- VIEW DESCRIPTION
-- =============================================
--
-- This view provides standardized access to Sponsored Brands (SB) ad performance data
-- from Amazon Ads API via Fivetran, enriched with creative history information.
--
-- Key Fields:
-- - campaign_id, ad_group_id, ad_id: Campaign structure identifiers
-- - report_date, date: Report date
-- - Creative fields: landing_page_type, headline, creative_type, custom_image_url, etc.
-- - Performance metrics: clicks, cost, impressions, viewable_impressions
-- - Attribution metrics: attributed_conversions_14_d, attributed_sales_14_d (14-day window)
--
-- Creative History Join Logic:
-- - Joins sb_creative_history to get creative information valid for each report date
-- - Uses window function to determine when each creative version was active
-- - Creative version is valid from creation_time until the next version's creation_time
-- - Last version is valid until CURRENT_TIMESTAMP()
--
-- This view is useful for:
-- - Analyzing SB campaign ad performance
-- - Understanding creative performance over time
-- - Tracking creative version changes
-- - SB campaign analysis (complements SP campaign data)
--
-- Note: This is for Sponsored Brands campaigns only. For Sponsored Products,
-- use V_SRC_AmazonAds_advertised_product instead.
--
-- =============================================
