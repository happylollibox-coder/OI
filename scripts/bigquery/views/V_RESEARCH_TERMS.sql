-- =============================================
-- V_RESEARCH_TERMS
-- =============================================
--
-- Purpose: Per-search-term market/brand aggregates for the Research page.
--          Single home for the CTE block previously duplicated across
--          /api/research/top-terms and /api/research/related-terms.
--
-- Grain: query_text. Window: fixed 104 weeks (2 years).
-- Note: top-terms previously used a 12-month window; unified to 104w here.
--
-- Materialized into FACT_RESEARCH_TERMS by SP_REFRESH_RESEARCH_RANKED.
-- Dependencies: V_SQP_QUERY_WEEKLY, SRC_ACC_SQP_WEEKLY, DIM_PRODUCT
-- SOP: architecture/RESEARCH_PAGE.md
-- =============================================

CREATE OR REPLACE VIEW `onyga-482313`.OI.V_RESEARCH_TERMS AS

WITH brand_stems AS (
  SELECT DISTINCT LOWER(SUBSTR(parent_name, 1, LEAST(5, LENGTH(parent_name)))) AS stem
  FROM `onyga-482313`.OI.DIM_PRODUCT
  WHERE is_active = true
),
last_week_data AS (
  SELECT v.query_text, v.week_start_date AS last_week,
    v.search_query_volume AS lw_impressions,
    v.TOTAL_CLICKS AS lw_clicks,
    v.TOTAL_PURCHASES AS lw_purchases,
    MAX(s.Purchases_Price_Median) AS lw_median_click_price,
    MAX(s.Clicks_Price_Median) AS lw_clicks_median
  FROM `onyga-482313`.OI.V_SQP_QUERY_WEEKLY v
  LEFT JOIN `onyga-482313`.OI.SRC_ACC_SQP_WEEKLY s
    ON s.Search_Query = v.query_text AND s.Reporting_Date = v.week_end_date
  WHERE v.week_start_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 104 WEEK)
    AND v.query_text != 'OTHER'
  GROUP BY v.query_text, v.week_start_date, v.week_end_date, v.search_query_volume, v.TOTAL_CLICKS, v.TOTAL_PURCHASES
  QUALIFY ROW_NUMBER() OVER (PARTITION BY v.query_text ORDER BY v.week_start_date DESC) = 1
),
-- Fallback: most recent non-null median price (handles weeks where SQP price is missing)
median_price_fallback AS (
  SELECT query_text, TOTAL_MEDIAN_CLICK_PRICE AS fallback_median_price
  FROM `onyga-482313`.OI.V_SQP_QUERY_WEEKLY
  WHERE TOTAL_MEDIAN_CLICK_PRICE IS NOT NULL
    AND week_start_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 12 MONTH)
  QUALIFY ROW_NUMBER() OVER (PARTITION BY query_text ORDER BY week_start_date DESC) = 1
),
aggregated AS (
  SELECT
    v.query_text,
    COUNT(*) AS weeks_appeared,
    SUM(v.TOTAL_IMPRESSIONS) AS market_impressions,
    SUM(v.TOTAL_CLICKS) AS market_clicks,
    COALESCE(SUM(v.TOTAL_PURCHASES), 0) AS market_purchases,
    SUM(v.BRAND_IMPRESSIONS) AS brand_impressions,
    SUM(v.BRAND_CLICKS) AS brand_clicks,
    SUM(v.BRAND_PURCHASES) AS brand_purchases,
    SUM(v.BRAND_SALES) AS brand_sales,
    COALESCE(ANY_VALUE(lw.lw_median_click_price), ANY_VALUE(mpf.fallback_median_price)) AS median_click_price,
    COALESCE(ANY_VALUE(lw.lw_clicks_median), ANY_VALUE(mpf.fallback_median_price)) AS clicks_median,
    CAST(ANY_VALUE(lw.last_week) AS STRING) AS last_week,
    ANY_VALUE(lw.lw_impressions) AS weekly_market_impressions,
    ANY_VALUE(lw.lw_clicks) AS weekly_market_clicks,
    ANY_VALUE(lw.lw_purchases) AS weekly_market_purchases,
    ANY_VALUE(v.gender) AS gender,
    ANY_VALUE(v.age_group) AS age_group,
    ANY_VALUE(v.occasion) AS occasion,
    ANY_VALUE(v.holiday) AS holiday,
    CASE
      WHEN COALESCE(ANY_VALUE(lw.lw_median_click_price), ANY_VALUE(mpf.fallback_median_price)) < 10 THEN 'Budget (<$10)'
      WHEN COALESCE(ANY_VALUE(lw.lw_median_click_price), ANY_VALUE(mpf.fallback_median_price)) < 20 THEN 'Value ($10-$20)'
      WHEN COALESCE(ANY_VALUE(lw.lw_median_click_price), ANY_VALUE(mpf.fallback_median_price)) < 35 THEN 'Mid ($20-$35)'
      WHEN COALESCE(ANY_VALUE(lw.lw_median_click_price), ANY_VALUE(mpf.fallback_median_price)) < 50 THEN 'Premium ($35-$50)'
      WHEN COALESCE(ANY_VALUE(lw.lw_median_click_price), ANY_VALUE(mpf.fallback_median_price)) >= 50 THEN 'Luxury ($50+)'
      ELSE NULL
    END AS cost_tier,
    ANY_VALUE(v.product_type) AS product_type,
    ANY_VALUE(v.brand) AS brand
  FROM `onyga-482313`.OI.V_SQP_QUERY_WEEKLY v
  LEFT JOIN last_week_data lw ON lw.query_text = v.query_text
  LEFT JOIN median_price_fallback mpf ON mpf.query_text = v.query_text
  WHERE v.week_start_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 104 WEEK)
    AND v.query_text != 'OTHER'
  GROUP BY v.query_text
)
SELECT
  a.*,
  ROUND(SAFE_DIVIDE(a.market_purchases, a.market_clicks) * 100, 2) AS market_cvr_pct,
  ROUND(SAFE_DIVIDE(a.weekly_market_purchases, a.weekly_market_clicks) * 100, 2) AS weekly_market_cvr_pct,
  ROUND(SAFE_DIVIDE(a.brand_impressions, a.market_impressions) * 100, 4) AS show_rate_pct,
  EXISTS(SELECT 1 FROM brand_stems bs WHERE LOWER(a.query_text) LIKE CONCAT('%', bs.stem, '%')) AS is_brand_term
FROM aggregated a
