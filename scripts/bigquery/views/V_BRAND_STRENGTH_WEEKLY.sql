-- =============================================
-- OI Database Project - V_BRAND_STRENGTH_WEEKLY
-- =============================================
--
-- Purpose: Weekly brand health metrics combining SQP and Ads data
--          for brand keywords only. Powers the Brand Strength page.
--          Rows are per (week, brand_keyword, parent_name).
--
-- Dominance Score formula (target-based, equal 33.3% weights):
--   Each component scores 0–100 based on proximity to achievable target.
--   Component score = CLAMP((actual − floor) / (target − floor) × 100, 0, 100)
--
--   1) Show Rate Score:  target = 100%, floor = 0%
--      "Nobody stole my brand terms" — full impression ownership.
--   2) Brand CVR Score:  target = 25%, floor = 0%
--      "I am desirable" — top of 15–25% industry range for brand CVR.
--   3) YoY SQP Growth Score:  target = 2.0× (100% YoY growth), floor = 0.5×
--      "More people are looking for me" — aggressive for young brand.
--
--   Dominance = (show_rate_score + cvr_score + yoy_score) / 3
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

-- ─── SQP brand rows: filter via subquery to avoid fan-out ──
-- A plain JOIN with brand_terms fans out rows when a query matches 2+ phrases.
-- We first find DISTINCT branded query_texts, then filter the fact table.
branded_queries AS (
  SELECT DISTINCT LOWER(sq.query_text) AS bq
  FROM `onyga-482313.OI.FACT_SEARCH_QUERY` sq
  JOIN brand_terms bt ON LOWER(sq.query_text) LIKE CONCAT('%', bt.term, '%')
  WHERE sq.week_start_date IS NOT NULL
),
sqp_brand_rows AS (
  SELECT sq.*, COALESCE(p.parent_name, 'Unknown') AS parent_name
  FROM `onyga-482313.OI.FACT_SEARCH_QUERY` sq
  JOIN branded_queries bq ON LOWER(sq.query_text) = bq.bq
  LEFT JOIN `onyga-482313.OI.DIM_PRODUCT` p ON sq.ASIN = p.asin
  WHERE sq.week_start_date IS NOT NULL
),

-- ─── SQP weekly+keyword+family aggregates ──
sqp_brand AS (
  SELECT
    week_start_date,
    LOWER(query_text)                         AS brand_keyword,
    parent_name,
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
  GROUP BY week_start_date, LOWER(query_text), parent_name
),

-- ─── Monthly SQP impressions for YoY ratio ──
sqp_monthly AS (
  SELECT
    FORMAT_DATE('%Y-%m', week_start_date) AS month_key,
    LOWER(query_text)                     AS brand_keyword,
    parent_name,
    SUM(impressions)                      AS month_impressions
  FROM sqp_brand_rows
  GROUP BY month_key, LOWER(query_text), parent_name
),

-- ─── Same month last year SQP impressions ──
sqp_yoy AS (
  SELECT
    cur.month_key,
    cur.brand_keyword,
    cur.parent_name,
    cur.month_impressions,
    ly.month_impressions AS ly_month_impressions
  FROM sqp_monthly cur
  LEFT JOIN sqp_monthly ly
    ON cur.brand_keyword = ly.brand_keyword
    AND cur.parent_name = ly.parent_name
    AND ly.month_key = FORMAT_DATE('%Y-%m', DATE_SUB(PARSE_DATE('%Y-%m', cur.month_key), INTERVAL 12 MONTH))
),

-- ─── Ads brand rows: filter via subquery to avoid fan-out ──
branded_search_terms AS (
  SELECT DISTINCT LOWER(a.search_term) AS bst
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` a
  JOIN brand_terms bt ON LOWER(a.search_term) LIKE CONCAT('%', bt.term, '%')
  WHERE a.search_term IS NOT NULL
),
ads_brand_rows AS (
  SELECT a.*, COALESCE(p.parent_name, 'Unknown') AS parent_name
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` a
  JOIN branded_search_terms bst ON LOWER(a.search_term) = bst.bst
  LEFT JOIN `onyga-482313.OI.DIM_PRODUCT` p ON a.ASIN_BY_CAMPAIGN_NAME = p.asin
  WHERE a.search_term IS NOT NULL
),

-- ─── Ads weekly+keyword+family aggregates ──
ads_brand AS (
  SELECT
    DATE_TRUNC(date, WEEK(SUNDAY)) AS week_start_date,
    LOWER(search_term)             AS brand_keyword,
    parent_name,
    SUM(Ads_impressions)           AS ads_impressions,
    SUM(Ads_clicks)                AS ads_clicks,
    SUM(Ads_orders)                AS ads_orders,
    SUM(Ads_units)                 AS ads_units,
    SUM(Ads_cost)                  AS ads_spend,
    SUM(Ads_sales)                 AS ads_sales,
    SAFE_DIVIDE(SUM(Ads_cost), NULLIF(SUM(Ads_clicks), 0)) AS ads_cpc
  FROM ads_brand_rows
  GROUP BY week_start_date, LOWER(search_term), parent_name
),

-- ─── Final aggregates joined by week + keyword + parent_name ──
combined AS (
  SELECT
    COALESCE(s.week_start_date, a.week_start_date) AS week_start_date,
    COALESCE(s.brand_keyword, a.brand_keyword)     AS brand_keyword,
    COALESCE(s.parent_name, a.parent_name)         AS parent_name,

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

    -- YoY SQP impression ratio for dominance score
    yoy.month_impressions     AS sqp_month_impressions,
    yoy.ly_month_impressions  AS sqp_ly_month_impressions,

    -- Brand Dominance Score (0-100): target-based, equal 33.3% weights
    -- Each component: CLAMP((actual - floor) / (target - floor) * 100, 0, 100)
    -- Show Rate target=100%, CVR target=25%, YoY Growth target=2.0× floor=0.5×
    ROUND(
      (
        -- 1) Show Rate Score: target = 100%, floor = 0%
        LEAST(GREATEST(COALESCE(s.avg_show_rate, 0), 0), 100)
        -- 2) Brand CVR Score: target = 25% (0.25), floor = 0%
        + LEAST(GREATEST(
            COALESCE(SAFE_DIVIDE(s.sqp_conversions, NULLIF(s.sqp_clicks, 0)), 0) / 0.25 * 100,
          0), 100)
        -- 3) YoY SQP Growth Score: target = 2.0× (200%), floor = 0.5× (50%)
        + LEAST(GREATEST(
            (COALESCE(
              SAFE_DIVIDE(yoy.month_impressions, NULLIF(yoy.ly_month_impressions, 0)),
              1.0  -- If no LY data, assume neutral (1.0× = same as last year)
            ) - 0.5) / (2.0 - 0.5) * 100,
          0), 100)
      ) / 3,  -- Equal weights: average of three 0-100 scores
    1) AS brand_dominance_score

  FROM sqp_brand s
  FULL OUTER JOIN ads_brand a
    ON s.week_start_date = a.week_start_date
    AND s.brand_keyword = a.brand_keyword
    AND s.parent_name = a.parent_name
  LEFT JOIN sqp_yoy yoy
    ON FORMAT_DATE('%Y-%m', COALESCE(s.week_start_date, a.week_start_date)) = yoy.month_key
    AND COALESCE(s.brand_keyword, a.brand_keyword) = yoy.brand_keyword
    AND COALESCE(s.parent_name, a.parent_name) = yoy.parent_name
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
  QUALIFY ROW_NUMBER() OVER (PARTITION BY c.week_start_date, c.brand_keyword, c.parent_name ORDER BY bp.word_count DESC, LENGTH(bp.phrase) DESC) = 1
)

SELECT * FROM matched_brand_phrases
ORDER BY week_start_date DESC, brand_keyword;
