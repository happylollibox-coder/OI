-- =============================================
-- Validation: SQP keyword terms (Family page)
-- =============================================
-- Purpose: Validate sqp_weekly.json. Compare to dashboard Family SQP keyword table.
-- Source: dashboard/refresh_data.py QUERIES["sqp_weekly.json"] (lines 660-712)
-- Source table: FACT_AMAZON_SEARCH_PERFORMANCE_WEEKLY
--
-- Usage: Replace week_start with desired week (e.g. 2026-02-23 for week of Feb 23).
-- =============================================

WITH family_map AS (
  SELECT asin,
    CASE
      WHEN product_short_name LIKE '%Lollibox%' THEN 'Lollibox'
      WHEN product_short_name LIKE '%LolliME%' THEN 'LolliME'
      WHEN product_short_name LIKE '%Fresh%' THEN 'Fresh'
      WHEN product_short_name LIKE '%Truth%' OR product_short_name LIKE '%Bottle%' THEN 'Bottle'
      ELSE product_short_name
    END as family,
    product_short_name
  FROM `onyga-482313.OI.DIM_PRODUCT` WHERE asin IS NOT NULL AND asin != 'UNKNOWN'
),
agg AS (
  SELECT
    fm.family as product_type,
    s.ASIN as asin,
    fm.product_short_name,
    DATE_SUB(s.Reporting_Date, INTERVAL 6 DAY) as week_start,
    s.Search_Query as search_term,
    COALESCE(s.Impressions, 0) as impressions,
    COALESCE(s.Clicks, 0) as clicks,
    COALESCE(s.Cart_Adds, 0) as cart_adds,
    COALESCE(s.ORDERS, 0) as orders,
    COALESCE(s.AMAZON_IMPRESSIONS, 0) as amazon_impressions,
    COALESCE(s.AMAZON_Clicks, 0) as amazon_clicks,
    COALESCE(s.AMAZON_ORDERS, 0) as amazon_orders,
    COALESCE(s.ADS_Impressions, 0) as ads_impressions,
    COALESCE(s.ADS_Clicks, 0) as ads_clicks,
    COALESCE(s.ADS_Orders, 0) as ads_orders,
    ROUND(COALESCE(s.show_rate_pct, 0), 1) as show_rate_pct,
    GREATEST(1, ROUND(48 * (1 - LEAST(COALESCE(s.show_rate_pct, 0), 100) / 100), 0)) as estimated_organic_rank,
    COALESCE(s.organic_rank_zone, 'unknown') as organic_rank_zone,
    ROUND(COALESCE(s.Search_Query_Score, 0), 0) as search_query_score
  FROM `onyga-482313.OI.FACT_AMAZON_SEARCH_PERFORMANCE_WEEKLY` s
  JOIN family_map fm ON s.ASIN = fm.asin
  WHERE s.Reporting_Date >= DATE_SUB(CURRENT_DATE(), INTERVAL 395 DAY)
    AND s.Impressions IS NOT NULL AND s.Impressions > 0
),
ranked AS (
  SELECT *,
    ROW_NUMBER() OVER (PARTITION BY asin, week_start ORDER BY orders DESC, impressions DESC) as rn
  FROM agg
)
SELECT product_type, asin, product_short_name, week_start, search_term,
  impressions, clicks, cart_adds, orders,
  amazon_impressions, amazon_clicks, amazon_orders,
  ads_impressions, ads_clicks, ads_orders,
  show_rate_pct, estimated_organic_rank, organic_rank_zone, search_query_score
FROM ranked
WHERE rn <= 100
  AND week_start = DATE('2026-02-23')  -- Replace with desired week
ORDER BY orders DESC, impressions DESC;
