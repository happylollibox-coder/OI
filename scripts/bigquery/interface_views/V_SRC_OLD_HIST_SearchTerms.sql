-- =============================================
-- OI Database Project - V_SRC_OLD_HIST_SearchTerms
-- =============================================
--
-- Purpose: Historical search-term data from manually exported Amazon reports
--          (Sep 2024 – Oct 2025) formatted to match V_SRC_AmazonAds_SearchTerms schema.
--
-- Source tables:
--   SRC_OLD_HIST_SP_SEARCH_TERMS  (Sponsored Products – 7-day attribution)
--   SRC_OLD_HIST_SB_SEARCH_TERMS  (Sponsored Brands  – 14-day attribution)
--
-- Deduplication:
--   The exported reports contain BOTH targeting-level aggregate rows (where
--   search_term = targeting) AND individual search-term detail rows.
--   The targeting rows represent the TRUE campaign spend (matches Amazon).
--   The search-term detail rows break this down but don't capture 100%.
--   Strategy:
--     1. Keep all search-term detail rows (search_term != targeting)
--     2. Compute unattributed spend = targeting_row - SUM(detail_rows)
--     3. Emit the difference as a '~unattributed' row to match Amazon totals
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

-- ══════════════════════════════════════════════
-- SP: Search-term detail rows + unattributed
-- ══════════════════════════════════════════════

-- SP detail rows (search_term != targeting)
sp_detail AS (
  SELECT
    h.campaign_name,
    h.ad_group_name,
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
    h.ASIN_BY_CAMPAIGN_NAME as asin_by_campaign_name
  FROM `onyga-482313.OI.SRC_OLD_HIST_SP_SEARCH_TERMS` h
  LEFT JOIN sp_camp c  ON h.campaign_name = c.name
  LEFT JOIN sp_ag   ag ON c.campaign_id = ag.campaign_id AND h.ad_group_name = ag.ag_name
  WHERE h.search_term != h.targeting
),
-- SP targeting aggregate rows (search_term = targeting) → the Amazon truth
sp_targeting AS (
  SELECT
    h.campaign_name,
    h.ad_group_name,
    h.date,
    h.targeting,
    COALESCE(h.match_type, '-') AS ad_keyword_status,
    COALESCE(h.spend, 0)        AS cost,
    COALESCE(h.clicks, 0)       AS clicks,
    COALESCE(h.impressions, 0)  AS impressions,
    COALESCE(h.orders_7d, 0)    AS orders,
    COALESCE(h.units_7d, 0)     AS units,
    COALESCE(h.sales_7d, 0.0)   AS sales,
    h.ASIN_BY_CAMPAIGN_NAME as asin_by_campaign_name
  FROM `onyga-482313.OI.SRC_OLD_HIST_SP_SEARCH_TERMS` h
  WHERE h.search_term = h.targeting
),
-- SP detail sums per (date, campaign_name, ad_group_name, targeting) using raw source keys
sp_detail_sums AS (
  SELECT
    date, campaign_name, ad_group_name, targeting,
    -- Keep the resolved IDs for the unattributed row output
    ANY_VALUE(campaign_id) AS campaign_id,
    ANY_VALUE(ad_group_id) AS ad_group_id,
    SUM(cost)        AS detail_cost,
    SUM(clicks)      AS detail_clicks,
    SUM(impressions) AS detail_impressions,
    SUM(orders)      AS detail_orders,
    SUM(units)       AS detail_units,
    SUM(sales)       AS detail_sales
  FROM sp_detail
  GROUP BY 1, 2, 3, 4
),
-- SP unattributed rows: difference between targeting total and detail sum
sp_unattributed AS (
  SELECT
    t.campaign_name,
    t.ad_group_name,
    'SP' AS campaign_type,
    t.date,
    COALESCE(d.campaign_id, '-1') AS campaign_id,
    COALESCE(d.ad_group_id, '-1') AS ad_group_id,
    '-1' AS keyword_id,
    t.date AS report_date,
    '~unattributed' AS search_term,
    t.ad_keyword_status,
    t.targeting,
    GREATEST(t.clicks - COALESCE(d.detail_clicks, 0), 0)       AS clicks,
    GREATEST(t.impressions - COALESCE(d.detail_impressions, 0), 0) AS impressions,
    GREATEST(t.cost - COALESCE(d.detail_cost, 0), 0)           AS cost,
    GREATEST(t.orders - COALESCE(d.detail_orders, 0), 0)       AS orders,
    GREATEST(t.units - COALESCE(d.detail_units, 0), 0)         AS units,
    GREATEST(t.sales - COALESCE(d.detail_sales, 0), 0)         AS sales,
    CAST(NULL AS TIMESTAMP)  AS _fivetran_synced,
    'hist_sp_7d_attr'        AS source_table,
    t.asin_by_campaign_name
  FROM sp_targeting t
  LEFT JOIN sp_detail_sums d
    ON t.date = d.date
    AND t.campaign_name = d.campaign_name
    AND t.ad_group_name = d.ad_group_name
    AND t.targeting = d.targeting
  WHERE d.detail_cost IS NOT NULL  -- only emit when matching detail rows exist
    AND t.cost - d.detail_cost > 0.005  -- only emit if there's a meaningful difference
),

-- ══════════════════════════════════════════════
-- SB: Search-term detail rows + unattributed
-- ══════════════════════════════════════════════

-- SB detail rows (search_term != targeting)
sb_detail AS (
  SELECT
    h.campaign_name,
    h.ad_group_name,
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
    h.ASIN_BY_CAMPAIGN_NAME as asin_by_campaign_name
  FROM `onyga-482313.OI.SRC_OLD_HIST_SB_SEARCH_TERMS` h
  LEFT JOIN sb_camp c  ON h.campaign_name = c.name
  LEFT JOIN sb_ag   ag ON c.campaign_id = ag.campaign_id AND h.ad_group_name = ag.ag_name
  WHERE h.search_term != h.targeting
),
-- SB targeting aggregate rows (search_term = targeting) → the Amazon truth
sb_targeting AS (
  SELECT
    h.campaign_name,
    h.ad_group_name,
    h.date,
    h.targeting,
    COALESCE(h.match_type, '-') AS ad_keyword_status,
    COALESCE(h.spend, 0)        AS cost,
    COALESCE(h.clicks, 0)       AS clicks,
    COALESCE(h.impressions, 0)  AS impressions,
    COALESCE(h.orders_14d, 0)   AS orders,
    COALESCE(h.units_14d, 0)    AS units,
    COALESCE(h.sales_14d, 0.0)  AS sales,
    h.ASIN_BY_CAMPAIGN_NAME as asin_by_campaign_name
  FROM `onyga-482313.OI.SRC_OLD_HIST_SB_SEARCH_TERMS` h
  WHERE h.search_term = h.targeting
),
-- SB detail sums per (date, campaign_name, ad_group_name, targeting) using raw source keys
sb_detail_sums AS (
  SELECT
    date, campaign_name, ad_group_name, targeting,
    ANY_VALUE(campaign_id) AS campaign_id,
    ANY_VALUE(ad_group_id) AS ad_group_id,
    SUM(cost)        AS detail_cost,
    SUM(clicks)      AS detail_clicks,
    SUM(impressions) AS detail_impressions,
    SUM(orders)      AS detail_orders,
    SUM(units)       AS detail_units,
    SUM(sales)       AS detail_sales
  FROM sb_detail
  GROUP BY 1, 2, 3, 4
),
-- SB unattributed rows
sb_unattributed AS (
  SELECT
    t.campaign_name,
    t.ad_group_name,
    'SB' AS campaign_type,
    t.date,
    COALESCE(d.campaign_id, '-1') AS campaign_id,
    COALESCE(d.ad_group_id, '-1') AS ad_group_id,
    '-1' AS keyword_id,
    t.date AS report_date,
    '~unattributed' AS search_term,
    t.ad_keyword_status,
    t.targeting,
    GREATEST(t.clicks - COALESCE(d.detail_clicks, 0), 0)       AS clicks,
    GREATEST(t.impressions - COALESCE(d.detail_impressions, 0), 0) AS impressions,
    GREATEST(t.cost - COALESCE(d.detail_cost, 0), 0)           AS cost,
    GREATEST(t.orders - COALESCE(d.detail_orders, 0), 0)       AS orders,
    GREATEST(t.units - COALESCE(d.detail_units, 0), 0)         AS units,
    GREATEST(t.sales - COALESCE(d.detail_sales, 0), 0)         AS sales,
    CAST(NULL AS TIMESTAMP)  AS _fivetran_synced,
    'hist_sb_14d_attr'       AS source_table,
    t.asin_by_campaign_name
  FROM sb_targeting t
  LEFT JOIN sb_detail_sums d
    ON t.date = d.date
    AND t.campaign_name = d.campaign_name
    AND t.ad_group_name = d.ad_group_name
    AND t.targeting = d.targeting
  WHERE d.detail_cost IS NOT NULL  -- only emit when matching detail rows exist
    AND t.cost - d.detail_cost > 0.005
),

-- ══════════════════════════════════════════════
-- Combine: detail rows + unattributed rows
-- ══════════════════════════════════════════════

-- Add inferred columns to all rows
add_inferred AS (
  SELECT
    campaign_name, ad_group_name, campaign_type, date, campaign_id, ad_group_id, keyword_id,
    report_date, search_term, ad_keyword_status, targeting,
    clicks, impressions, cost, orders, units, sales,
    _fivetran_synced, source_table, asin_by_campaign_name,
    CASE
      WHEN search_term IS NULL OR search_term = '' THEN 'other'
      WHEN search_term = '~unattributed'                        THEN 'other'
      WHEN REGEXP_CONTAINS(UPPER(search_term), r'^B[0-9A-Z]{9}$') THEN 'Module #5 - Other ASIN/Product Pages (ASIN Pattern)'
      WHEN REGEXP_CONTAINS(UPPER(search_term), r'^ASIN')           THEN 'Module #5 - Other ASIN/Product Pages (ASIN Text)'
      WHEN LENGTH(search_term) > 0                                 THEN 'Module #1 - Paid Search (Text Search Term)'
      ELSE 'other'
    END AS inferred_sales_module,
    CASE
      WHEN search_term IS NULL OR search_term = '' THEN 'other'
      WHEN search_term = '~unattributed'                        THEN 'other'
      WHEN REGEXP_CONTAINS(UPPER(search_term), r'^B[0-9A-Z]{9}$') THEN 'Product_Page'
      WHEN REGEXP_CONTAINS(UPPER(search_term), r'^ASIN')           THEN 'Product_Page'
      ELSE 'Search_Results'
    END AS placement_type
  FROM (
    SELECT * FROM sp_detail
    UNION ALL
    SELECT * FROM sp_unattributed
    UNION ALL
    SELECT * FROM sb_detail
    UNION ALL
    SELECT * FROM sb_unattributed
  )
),

-- ══════════════════════════════════════════════
-- Monthly gap: unknown spend from Amazon benchmarks
-- ══════════════════════════════════════════════

-- Monthly totals from detail + unattributed rows
monthly_totals AS (
  SELECT
    DATE_TRUNC(date, MONTH) AS month_start,
    SUM(cost) AS oi_total
  FROM add_inferred
  GROUP BY 1
),
-- Gap between Amazon benchmark and our data
monthly_gap AS (
  SELECT
    b.month_start,
    b.amazon_total,
    COALESCE(m.oi_total, 0) AS oi_total,
    GREATEST(b.amazon_total - COALESCE(m.oi_total, 0), 0) AS gap_cost
  FROM `onyga-482313.OI.DE_AMAZON_AD_SPEND_BENCHMARKS` b
  LEFT JOIN monthly_totals m ON b.month_start = m.month_start
  WHERE b.amazon_total - COALESCE(m.oi_total, 0) > 0.5  -- only emit if meaningful gap
),
-- One unknown_spend row per month, placed on the 1st of the month
unknown_spend AS (
  SELECT
    '~unknown' AS campaign_name,
    CAST(NULL AS STRING) AS ad_group_name,
    'SB' AS campaign_type,
    g.month_start AS date,
    '-1' AS campaign_id,
    '-1' AS ad_group_id,
    '-1' AS keyword_id,
    g.month_start AS report_date,
    '~unknown_spend' AS search_term,
    '-' AS ad_keyword_status,
    '~unknown_spend' AS targeting,
    0 AS clicks,
    0 AS impressions,
    g.gap_cost AS cost,
    0 AS orders,
    0 AS units,
    0.0 AS sales,
    CAST(NULL AS TIMESTAMP) AS _fivetran_synced,
    'hist_unknown_gap' AS source_table,
    CAST(NULL AS STRING) AS asin_by_campaign_name,
    'other' AS inferred_sales_module,
    'other' AS placement_type
  FROM monthly_gap g
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
FROM add_inferred

UNION ALL

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
  1 AS num_st_in_date_keyword,
  asin_by_campaign_name
FROM unknown_spend;
