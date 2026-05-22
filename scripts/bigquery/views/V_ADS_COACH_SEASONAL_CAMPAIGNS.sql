CREATE OR REPLACE VIEW `onyga-482313.OI.V_ADS_COACH_SEASONAL_CAMPAIGNS` AS

-- =============================================
-- V_ADS_COACH_SEASONAL_CAMPAIGNS
-- Auto-generates Q4 Seasonal Push campaign recommendations
-- Groups detected Q4-only terms by hero ASIN, max 7 per campaign
-- =============================================

WITH q4_terms AS (
  -- De-duplicate: one row per search_term (pick the row with highest Q4 orders)
  SELECT
    d.search_term,
    COALESCE(d.hero_asin, d.asin) as best_asin,
    COALESCE(d.hero_product_name, d.product_short_name) as best_product,
    d.q4_peak_orders,
    d.q4_peak_net_roas,
    d.q4_os_net_roas,
    d.q4_peak_spend,
    d.q4_os_spend,
    -- Keyword theme detection for sub-grouping
    CASE
      WHEN REGEXP_CONTAINS(d.search_term, r'journal|diary|scrapbook|stationery|stationary') THEN 'journal'
      WHEN REGEXP_CONTAINS(d.search_term, r'birthday') THEN 'birthday'
      WHEN REGEXP_CONTAINS(d.search_term, r'christmas|xmas|holiday') THEN 'christmas'
      WHEN REGEXP_CONTAINS(d.search_term, r'sleepover|spa|party') THEN 'activity'
      WHEN REGEXP_CONTAINS(d.search_term, r'truth.*dare|game') THEN 'game'
      WHEN REGEXP_CONTAINS(d.search_term, r'tween|teen') THEN 'teen'
      WHEN REGEXP_CONTAINS(d.search_term, r'\d+\s*year\s*old') THEN 'by_age'
      ELSE 'general_gifts'
    END as keyword_theme,
    ROW_NUMBER() OVER (
      PARTITION BY d.search_term
      ORDER BY d.q4_peak_orders DESC
    ) as dedup_rn
  FROM `onyga-482313.OI.V_ADS_COACH_DATA` d
  WHERE d.is_q4_seasonal = TRUE
    AND d.recommendation_type = 'ACTIVE_TERM'
),

deduped AS (
  SELECT * FROM q4_terms WHERE dedup_rn = 1
),

-- Assign campaign groups: by hero ASIN + theme, then split into chunks of max 7
grouped AS (
  SELECT
    *,
    -- First group by hero ASIN + keyword theme
    CONCAT(best_asin, '|', keyword_theme) as group_key,
    ROW_NUMBER() OVER (
      PARTITION BY best_asin, keyword_theme
      ORDER BY q4_peak_orders DESC
    ) as pos_in_group
  FROM deduped
),

campaign_assigned AS (
  SELECT
    g.*,
    -- Split into sub-campaigns of max 7
    CAST(CEIL(pos_in_group / 7.0) AS INT64) as sub_group,
    -- Generate campaign name
    CONCAT(
      -- Product prefix
      CASE
        WHEN STRPOS(best_product, 'Lollibox') > 0 THEN 'BOX'
        WHEN STRPOS(best_product, 'LolliME') > 0 OR STRPOS(best_product, 'Lollime') > 0 THEN 'ME'
        WHEN STRPOS(best_product, 'Fresh') > 0 THEN 'FRESH'
        WHEN STRPOS(best_product, 'Bottle') > 0 THEN 'BOTTLE'
        WHEN STRPOS(best_product, 'Truth') > 0 THEN 'TOD'
        ELSE 'OI'
      END,
      '-SP/EXACT (Q4 Seasonal, ',
      -- Theme label
      CASE keyword_theme
        WHEN 'journal' THEN 'Journal'
        WHEN 'birthday' THEN 'Birthday'
        WHEN 'christmas' THEN 'Christmas'
        WHEN 'activity' THEN 'Activity'
        WHEN 'game' THEN 'Game'
        WHEN 'teen' THEN 'Teen'
        WHEN 'by_age' THEN 'By Age'
        ELSE 'Gifts'
      END,
      -- Sub-group number (only if > 1 sub-group exists)
      CASE WHEN CEIL(
        COUNT(*) OVER (PARTITION BY best_asin, keyword_theme) / 7.0
      ) > 1 THEN CONCAT(' ', CAST(CAST(CEIL(pos_in_group / 7.0) AS INT64) AS STRING))
      ELSE '' END,
      ')'
    ) as suggested_campaign_name
  FROM grouped g
)

SELECT
  suggested_campaign_name,
  best_asin as hero_asin,
  best_product as hero_product,
  keyword_theme,
  search_term,
  q4_peak_orders,
  ROUND(q4_peak_net_roas, 2) as q4_net_roas,
  ROUND(COALESCE(q4_os_net_roas, 0), 2) as os_net_roas,
  ROUND(q4_peak_spend, 0) as q4_spend,
  ROUND(COALESCE(q4_os_spend, 0), 0) as os_wasted_spend,
  -- Campaign-level aggregates
  COUNT(*) OVER (PARTITION BY suggested_campaign_name) as keywords_in_campaign,
  SUM(q4_peak_orders) OVER (PARTITION BY suggested_campaign_name) as campaign_q4_orders,
  ROUND(SUM(q4_peak_spend) OVER (PARTITION BY suggested_campaign_name), 0) as campaign_q4_spend,
  ROUND(SUM(COALESCE(q4_os_spend, 0)) OVER (PARTITION BY suggested_campaign_name), 0) as campaign_os_wasted
FROM campaign_assigned
ORDER BY campaign_q4_orders DESC, suggested_campaign_name, q4_peak_orders DESC
