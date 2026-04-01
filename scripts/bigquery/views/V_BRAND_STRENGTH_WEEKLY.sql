-- =============================================
-- OI Database Project - V_BRAND_STRENGTH_WEEKLY
-- =============================================
--
-- Purpose: Weekly brand health metrics combining SQP and Ads data
--          for brand keywords only. Powers the Brand Strength page.
--          Rows are per (week, brand_keyword).
--
-- Dependencies:
--   FACT_SEARCH_QUERY (SQP), FACT_AMAZON_ADS, DIM_PRODUCT, DIM_BRAND_PHRASES
--
-- =============================================

CREATE OR REPLACE VIEW `onyga-482313.OI.V_BRAND_STRENGTH_WEEKLY`
AS
WITH

-- ─── Brand keyword detection using JOIN instead of correlated subquery ──
brand_terms AS (
  SELECT phrase AS term FROM `onyga-482313.OI.DIM_BRAND_PHRASES`
),

-- ─── SQP brand rows: join on LIKE pattern ──
sqp_brand_rows AS (
  SELECT sq.*
  FROM `onyga-482313.OI.FACT_SEARCH_QUERY` sq
  JOIN brand_terms bt ON LOWER(sq.query_text) LIKE CONCAT('%', bt.term, '%')
  WHERE sq.week_start_date IS NOT NULL
),

-- ─── SQP weekly+keyword aggregates ──
sqp_brand AS (
  SELECT
    week_start_date,
    LOWER(query_text)                         AS brand_keyword,
    SUM(impressions)                          AS sqp_impressions,
    SUM(clicks)                               AS sqp_clicks,
    SUM(conversions)                          AS sqp_conversions,
    SUM(cart_adds)                            AS sqp_cart_adds,
    AVG(show_rate_pct)                        AS avg_show_rate,
    AVG(impression_share_pct)                 AS avg_impression_share,
    AVG(estimated_organic_rank)               AS avg_organic_rank,
    SUM(search_query_volume)                  AS total_search_volume,
    COUNT(DISTINCT ASIN)                      AS brand_asin_count
  FROM sqp_brand_rows
  GROUP BY week_start_date, LOWER(query_text)
),

-- ─── Ads brand rows: join on LIKE pattern ──
ads_brand_rows AS (
  SELECT a.*
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` a
  JOIN brand_terms bt ON LOWER(a.search_term) LIKE CONCAT('%', bt.term, '%')
  WHERE a.search_term IS NOT NULL
),

-- ─── Ads weekly+keyword aggregates ──
ads_brand AS (
  SELECT
    DATE_TRUNC(date, WEEK(SUNDAY)) AS week_start_date,
    LOWER(search_term)             AS brand_keyword,
    SUM(Ads_impressions)           AS ads_impressions,
    SUM(Ads_clicks)                AS ads_clicks,
    SUM(Ads_orders)                AS ads_orders,
    SUM(Ads_units)                 AS ads_units,
    SUM(Ads_cost)                  AS ads_spend,
    SUM(Ads_sales)                 AS ads_sales,
    SAFE_DIVIDE(SUM(Ads_cost), NULLIF(SUM(Ads_clicks), 0)) AS ads_cpc
  FROM ads_brand_rows
  GROUP BY week_start_date, LOWER(search_term)
),

-- ─── Final aggregates joined by week + keyword ──
combined AS (
  SELECT
    COALESCE(s.week_start_date, a.week_start_date) AS week_start_date,
    COALESCE(s.brand_keyword, a.brand_keyword)     AS brand_keyword,

    -- SQP metrics
    COALESCE(s.sqp_impressions, 0)        AS sqp_impressions,
    COALESCE(s.sqp_clicks, 0)             AS sqp_clicks,
    COALESCE(s.sqp_conversions, 0)        AS sqp_conversions,
    COALESCE(s.sqp_cart_adds, 0)          AS sqp_cart_adds,
    s.avg_show_rate,
    s.avg_impression_share,
    s.avg_organic_rank,
    COALESCE(s.total_search_volume, 0)    AS total_search_volume,
    COALESCE(s.brand_asin_count, 0)       AS brand_asin_count,

    -- Ads metrics
    COALESCE(a.ads_impressions, 0)        AS ads_impressions,
    COALESCE(a.ads_clicks, 0)             AS ads_clicks,
    COALESCE(a.ads_orders, 0)             AS ads_orders,
    COALESCE(a.ads_units, 0)              AS ads_units,
    COALESCE(a.ads_spend, 0.0)            AS ads_spend,
    COALESCE(a.ads_sales, 0.0)            AS ads_sales,
    a.ads_cpc,

    -- Derived
    SAFE_DIVIDE(COALESCE(s.sqp_conversions, 0), NULLIF(COALESCE(s.sqp_clicks, 0), 0)) AS brand_cvr,

    -- Brand Dominance Score (0-100): 50% impression share + 50% CVR
    ROUND(
      (COALESCE(s.avg_impression_share, 0) * 0.5
       + LEAST(COALESCE(SAFE_DIVIDE(s.sqp_conversions, NULLIF(s.sqp_clicks, 0)), 0) * 100, 100) * 0.5
      ), 1
    ) AS brand_dominance_score

  FROM sqp_brand s
  FULL OUTER JOIN ads_brand a
    ON s.week_start_date = a.week_start_date
    AND s.brand_keyword = a.brand_keyword
),

matched_brand_phrases AS (
  SELECT 
    c.*,
    bp.phrase_type,
    bp.requested_product,
    bp.tag
  FROM combined c
  LEFT JOIN `onyga-482313.OI.DIM_BRAND_PHRASES` bp
    ON STRPOS(c.brand_keyword, LOWER(bp.phrase)) > 0
  QUALIFY ROW_NUMBER() OVER (PARTITION BY c.week_start_date, c.brand_keyword ORDER BY bp.word_count DESC, LENGTH(bp.phrase) DESC) = 1
)

SELECT * FROM matched_brand_phrases
ORDER BY week_start_date DESC, brand_keyword;
