-- =============================================
-- OI Database Project - V_SRC_OLD_HIST_SearchTerms
-- =============================================
--
-- Purpose: Historical search-term data from manually exported Amazon reports
--          (Sep 2024 – Mar 2025) formatted to match V_SRC_AmazonAds_SearchTerms schema.
--
-- Source tables:
--   SRC_OLD_HIST_SP_SEARCH_TERMS  (Sponsored Products – 7-day attribution)
--   SRC_OLD_HIST_SB_SEARCH_TERMS  (Sponsored Brands  – 14-day attribution)
--
-- ID resolution:
--   campaign_id  → resolved via campaign_history / sb_campaign_history where possible,
--                   otherwise '-1'
--   ad_group_id  → resolved via ad_group_history / sb_ad_group_history where possible,
--                   otherwise '-1'
--   keyword_id   → always '-1' (not available in exports)
--
-- Attribution note:
--   SP orders/units/sales use 7-day attribution (Fivetran SP uses 30-day).
--   SB orders/units/sales use 14-day attribution (matches Fivetran SB).
--   source_table column distinguishes: hist_sp_7d_attr / hist_sb_14d_attr
--
-- Project: onyga-482313
-- Dataset: OI
-- =============================================

DROP VIEW IF EXISTS `OI.V_SRC_OLD_HIST_SearchTerms`;
CREATE VIEW `onyga-482313.OI.V_SRC_OLD_HIST_SearchTerms` AS

WITH
-- ── SP campaign name → ID ──
sp_camp AS (
  SELECT name, CAST(id AS STRING) AS campaign_id
  FROM (
    SELECT name, id, ROW_NUMBER() OVER (PARTITION BY id ORDER BY _fivetran_synced DESC) AS rn
    FROM `fivetran-hl.amazon_ads.campaign_history`
  ) WHERE rn = 1
),
-- ── SB campaign name → ID ──
sb_camp AS (
  SELECT name, CAST(id AS STRING) AS campaign_id
  FROM (
    SELECT name, id, ROW_NUMBER() OVER (PARTITION BY id ORDER BY _fivetran_synced DESC) AS rn
    FROM `fivetran-hl.amazon_ads.sb_campaign_history`
  ) WHERE rn = 1
),
-- ── SP ad-group name → ID ──
sp_ag AS (
  SELECT name AS ag_name, CAST(id AS STRING) AS ad_group_id, CAST(campaign_id AS STRING) AS campaign_id
  FROM (
    SELECT name, id, campaign_id, ROW_NUMBER() OVER (PARTITION BY id ORDER BY _fivetran_synced DESC) AS rn
    FROM `fivetran-hl.amazon_ads.ad_group_history`
  ) WHERE rn = 1
),
-- ── SB ad-group name → ID ──
sb_ag AS (
  SELECT name AS ag_name, CAST(id AS STRING) AS ad_group_id, CAST(campaign_id AS STRING) AS campaign_id
  FROM (
    SELECT name, id, campaign_id, ROW_NUMBER() OVER (PARTITION BY id ORDER BY _fivetran_synced DESC) AS rn
    FROM `fivetran-hl.amazon_ads.sb_ad_group_history`
  ) WHERE rn = 1
),
-- ── Format SP historical rows ──
hist_sp AS (
  SELECT
    h.campaign_name,
    'SP' AS campaign_type,
    h.date,
    COALESCE(c.campaign_id, '-1') AS campaign_id,
    COALESCE(ag.ad_group_id, '-1') AS ad_group_id,
    '-1' AS keyword_id,
    h.date AS report_date,
    h.search_term,
    COALESCE(h.match_type, '-') AS ad_keyword_status,
    h.targeting,
    COALESCE(h.clicks, 0)      AS clicks,
    COALESCE(h.impressions, 0)  AS impressions,
    COALESCE(h.spend, 0)        AS cost,
    COALESCE(h.orders_7d, 0)    AS orders,
    COALESCE(h.units_7d, 0)     AS units,
    COALESCE(h.sales_7d, 0.0)   AS sales,
    CAST(NULL AS TIMESTAMP)      AS _fivetran_synced,
    'hist_sp_7d_attr'            AS source_table,
    CASE
      WHEN h.search_term IS NULL OR h.search_term = '' THEN 'other'
      WHEN REGEXP_CONTAINS(UPPER(h.search_term), r'^B[0-9A-Z]{9}$') THEN 'Module #5 - Other ASIN/Product Pages (ASIN Pattern)'
      WHEN REGEXP_CONTAINS(UPPER(h.search_term), r'^ASIN')           THEN 'Module #5 - Other ASIN/Product Pages (ASIN Text)'
      WHEN LENGTH(h.search_term) > 0                                 THEN 'Module #1 - Paid Search (Text Search Term)'
      ELSE 'other'
    END AS inferred_sales_module,
    CASE
      WHEN h.search_term IS NULL OR h.search_term = '' THEN 'other'
      WHEN REGEXP_CONTAINS(UPPER(h.search_term), r'^B[0-9A-Z]{9}$') THEN 'Product_Page'
      WHEN REGEXP_CONTAINS(UPPER(h.search_term), r'^ASIN')           THEN 'Product_Page'
      ELSE 'Search_Results'
    END AS placement_type,
    h.ASIN_BY_CAMPAIGN_NAME as asin_by_campaign_name
  FROM `onyga-482313.OI.SRC_OLD_HIST_SP_SEARCH_TERMS` h
  LEFT JOIN sp_camp c  ON h.campaign_name = c.name
  LEFT JOIN sp_ag   ag ON c.campaign_id = ag.campaign_id AND h.ad_group_name = ag.ag_name
),
-- Column list for hist_sp:
-- campaign_name, campaign_type, date, campaign_id, ad_group_id, keyword_id,
-- report_date, search_term, ad_keyword_status, targeting,
-- clicks, impressions, cost, orders, units, sales,
-- _fivetran_synced, source_table, inferred_sales_module, placement_type,
-- asin_by_campaign_name
-- ── Format SB historical rows ──
hist_sb AS (
  SELECT
    h.campaign_name,
    'SB' AS campaign_type,
    h.date,
    COALESCE(c.campaign_id, '-1') AS campaign_id,
    COALESCE(ag.ad_group_id, '-1') AS ad_group_id,
    '-1' AS keyword_id,
    h.date AS report_date,
    h.search_term,
    COALESCE(h.match_type, '-') AS ad_keyword_status,
    h.targeting,
    COALESCE(h.clicks, 0)        AS clicks,
    COALESCE(h.impressions, 0)    AS impressions,
    COALESCE(h.spend, 0)          AS cost,
    COALESCE(h.orders_14d, 0)     AS orders,
    COALESCE(h.units_14d, 0)      AS units,
    COALESCE(h.sales_14d, 0.0)    AS sales,
    CAST(NULL AS TIMESTAMP)        AS _fivetran_synced,
    'hist_sb_14d_attr'             AS source_table,
    CASE
      WHEN h.search_term IS NULL OR h.search_term = '' THEN 'other'
      WHEN REGEXP_CONTAINS(UPPER(h.search_term), r'^B[0-9A-Z]{9}$') THEN 'Module #5 - Other ASIN/Product Pages (ASIN Pattern)'
      WHEN REGEXP_CONTAINS(UPPER(h.search_term), r'^ASIN')           THEN 'Module #5 - Other ASIN/Product Pages (ASIN Text)'
      WHEN LENGTH(h.search_term) > 0                                 THEN 'Module #1 - Paid Search (Text Search Term)'
      ELSE 'other'
    END AS inferred_sales_module,
    CASE
      WHEN h.search_term IS NULL OR h.search_term = '' THEN 'other'
      WHEN REGEXP_CONTAINS(UPPER(h.search_term), r'^B[0-9A-Z]{9}$') THEN 'Product_Page'
      WHEN REGEXP_CONTAINS(UPPER(h.search_term), r'^ASIN')           THEN 'Product_Page'
      ELSE 'Search_Results'
    END AS placement_type,
    h.ASIN_BY_CAMPAIGN_NAME as asin_by_campaign_name
  FROM `onyga-482313.OI.SRC_OLD_HIST_SB_SEARCH_TERMS` h
  LEFT JOIN sb_camp c  ON h.campaign_name = c.name
  LEFT JOIN sb_ag   ag ON c.campaign_id = ag.campaign_id AND h.ad_group_name = ag.ag_name
),
-- ── Combine both and add num_st_in_date_keyword ──
combined AS (
  SELECT * FROM hist_sp
  UNION ALL
  SELECT * FROM hist_sb
)
SELECT
  campaign_name,
  campaign_type,
  date,
  campaign_id,
  ad_group_id,
  keyword_id,
  report_date,
  search_term,
  ad_keyword_status,
  targeting,
  clicks,
  impressions,
  cost,
  orders,
  units,
  sales,
  _fivetran_synced,
  source_table,
  inferred_sales_module,
  placement_type,
  COUNT(*) OVER (PARTITION BY date, campaign_id, ad_group_id, keyword_id) AS num_st_in_date_keyword,
  asin_by_campaign_name
FROM combined;
