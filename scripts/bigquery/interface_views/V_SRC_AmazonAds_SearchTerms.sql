-- =============================================
-- OI Database Project - V_SRC_AmazonAds_SearchTerms
-- =============================================
--
-- Purpose: Search term performance — Fivetran live data + historical manual exports
-- Business Logic: Complex multi-source UNION with joins and date filtering
-- Dependencies: Multiple search term tables + V_SRC_AmazonAds_campaign_history
--               + V_SRC_AmazonAds_keyword + V_SRC_OLD_HIST_SearchTerms
-- Project: onyga-482313
-- Dataset: OI
-- Updated: 2026-02-09
--
-- Data sources:
--   Fivetran (Oct 2025+): sp_keyword, sp_targeting, sb_search_term, sb_target_report
--   Historical (Sep 2024 – Mar 2025): hist_sp_7d_attr (7-day attribution),
--                                      hist_sb_14d_attr (14-day attribution)
--
-- SALES MODULE CLASSIFICATION LOGIC:
-- - Empty/NULL search_term → "other"
-- - ASIN pattern (B + 9 alphanumeric) → Module #5 (Other ASIN/Product Pages)
-- - Search term starts with "asin" (case-insensitive) → Module #5 (Other ASIN/Product Pages)
-- - Text search_term → Module #1 (Paid Search)
--
-- =============================================

DROP VIEW IF EXISTS `OI.V_SRC_AmazonAds_SearchTerms`;
CREATE VIEW `onyga-482313.OI.V_SRC_AmazonAds_SearchTerms`
AS

-- ── Part 1: Fivetran live data (Oct 2025 onward) ──
SELECT * FROM (
  SELECT c.campaign_name,
         c.campaign_type,
         st.*,

         CASE
           WHEN st.search_term IS NULL OR st.search_term = '' THEN 'other'
           WHEN REGEXP_CONTAINS(UPPER(st.search_term), r'^B[0-9A-Z]{9}$') THEN 'Module #5 - Other ASIN/Product Pages (ASIN Pattern)'
           WHEN REGEXP_CONTAINS(UPPER(st.search_term), r'^ASIN')          THEN 'Module #5 - Other ASIN/Product Pages (ASIN Text)'
           WHEN LENGTH(st.search_term) > 0                                THEN 'Module #1 - Paid Search (Text Search Term)'
           ELSE 'other'
         END AS inferred_sales_module,

         CASE
           WHEN st.search_term IS NULL OR st.search_term = '' THEN 'other'
           WHEN REGEXP_CONTAINS(UPPER(st.search_term), r'^B[0-9A-Z]{9}$') THEN 'Product_Page'
           WHEN REGEXP_CONTAINS(UPPER(st.search_term), r'^ASIN')          THEN 'Product_Page'
           ELSE 'Search_Results'
         END AS placement_type,

  COUNT(*) OVER (PARTITION BY st.date, st.campaign_id, st.ad_group_id, st.keyword_id) num_st_in_date_keyword,

         CAST(NULL AS STRING) AS asin_by_campaign_name

  FROM (
    SELECT
      date,
      CAST(campaign_id AS STRING) campaign_id,
      CAST(ad_group_id AS STRING) AS ad_group_id,
      CAST(keyword_id AS STRING) AS keyword_id,
      CAST(`date` AS DATE) AS report_date,
      search_term,
      ad_keyword_status,
      targeting,
      clicks,
      impressions,
      cost,
      purchases_30_d orders,
      units_sold_clicks_30_d units,
      sales_30_d sales,
      _fivetran_synced,
      'sp_keyword' AS source_table
    FROM `fivetran-hl.amazon_ads.search_term_ad_keyword_report`

    UNION ALL

    SELECT
      date,
      CAST(campaign_id AS STRING) campaign_id,
      CAST(ad_group_id AS STRING) ad_group_id,
      CAST(keyword_id AS STRING) AS keyword_id,
      CAST(`date` AS DATE) AS report_date,
      search_term,
      ad_keyword_status,
      targeting,
      clicks,
      impressions,
      cost,
      purchases_30_d orders,
      units_sold_clicks_30_d units,
      sales_30_d sales,
      _fivetran_synced,
      'sp_targeting' AS source_table
    FROM `fivetran-hl.amazon_ads.search_term_targeting_report`

    UNION ALL

    SELECT
      report_date date,
      CAST(st.campaign_id AS STRING) campaign_id,
      CAST(st.ad_group_id AS STRING) ad_group_id,
      CAST(st.keyword_id AS STRING) AS keyword_id,
      CAST(report_date AS DATE) AS report_date,
      query_term AS search_term,
      k.state ad_keyword_status,
      keyword_text targeting,
      clicks,
      impressions,
      cost,
      attributed_conversions_14_d orders,
      attributed_conversions_14_d units,
      attributed_sales_14_d sales,
      st._fivetran_synced,
      'sb_search_term' AS source_table
    FROM fivetran-hl.amazon_ads.sb_search_term_report st
    LEFT JOIN onyga-482313.OI.V_SRC_AmazonAds_keyword k ON CAST(st.keyword_id AS STRING) = k.keyword_id

    UNION ALL

    SELECT
      report_date date,
      CAST(campaign_id AS STRING) campaign_id,
      CAST(ad_group_id AS STRING) ad_group_id,
      '-1' AS keyword_id,
      CAST(report_date AS DATE) AS report_date,
      targeting_text AS search_term,
      '-1' ad_keyword_status,
      targeting_text targeting,
      clicks,
      impressions,
      cost,
      attributed_conversions_14_d orders,
      attributed_conversions_14_d units,
      attributed_sales_14_d sales,
      _fivetran_synced,
      'sb_target_report' AS source_table
    FROM `fivetran-hl.amazon_ads.sb_target_report`
    WHERE cost <> 0
  ) st
  LEFT JOIN onyga-482313.OI.V_SRC_AmazonAds_campaign_history c
    ON st.campaign_id = c.campaign_id
    AND TIMESTAMP(st.date) BETWEEN c.OI_start_date AND c.OI_end_date
  WHERE st.date >= '2025-10-28'
) fivetran_data

UNION ALL

-- ── Part 2: Historical manual exports (Sep 2024 – Mar 2025) ──
SELECT * FROM `onyga-482313.OI.V_SRC_OLD_HIST_SearchTerms`;
