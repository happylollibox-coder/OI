-- =============================================
-- V_CONVERSION_CURVE
-- =============================================
--
-- Purpose: Pre-computes clicks-per-sale conversion curves
--          by (product × price_bucket × holiday_season).
--          Used by the Research page to estimate how many clicks
--          a product needs on any search term.
--
-- Dependencies:
--   FACT_AMAZON_ADS, DIM_PRODUCT, DIM_LISTING_HISTORY, DIM_US_HOLIDAYS, V_SQP_QUERY_WEEKLY
--
-- Grain: parent_name × price_bucket × holiday_name
--        Plus '_ALL' rows for global aggregation
--        Plus '_ALL' holiday rows that aggregate across seasons
--
-- Invariant #7: Uses ASIN_BY_CAMPAIGN_NAME (ID-based join)
-- Invariant #8: All business logic in SQL
-- =============================================

CREATE OR REPLACE VIEW `onyga-482313`.OI.V_CONVERSION_CURVE AS

WITH

-- ═══ 1. Product launch: skip first 3 months (cold-start) ═══
product_launch AS (
  SELECT
    ASIN_BY_CAMPAIGN_NAME AS asin,
    MIN(date) AS first_ad_date,
    DATE_ADD(MIN(date), INTERVAL 3 MONTH) AS mature_from
  FROM `onyga-482313`.OI.FACT_AMAZON_ADS
  WHERE ASIN_BY_CAMPAIGN_NAME IS NOT NULL
  GROUP BY ASIN_BY_CAMPAIGN_NAME
),

-- ═══ 2. Holiday windows from DIM_US_HOLIDAYS ═══
holiday_windows AS (
  SELECT
    holiday_name,
    boost_start,
    holiday_date
  FROM `onyga-482313`.OI.DIM_US_HOLIDAYS
  WHERE holiday_date >= '2024-06-01'
),

-- ═══ 3. Median click prices per search query from SQP ═══
median_prices AS (
  SELECT
    query_text,
    AVG(TOTAL_MEDIAN_CLICK_PRICE) AS median_price
  FROM `onyga-482313`.OI.V_SQP_QUERY_WEEKLY
  WHERE TOTAL_MEDIAN_CLICK_PRICE > 0
  GROUP BY query_text
),

-- ═══ 4. Only search terms with at least 1 unit sold ═══
-- Excludes non-converting terms whose clicks inflate CPS
converting_terms AS (
  SELECT search_term
  FROM `onyga-482313`.OI.FACT_AMAZON_ADS
  WHERE Ads_units > 0
  GROUP BY search_term
),

-- ═══ 5. Tag each ads row with holiday season + price ratio ═══
-- Uses DIM_LISTING_HISTORY (SCD2) for dates with coverage,
-- falls back to V_DIM_LISTING_CURRENT for older dates
tagged AS (
  SELECT
    p.parent_name,
    a.date,
    a.Ads_clicks,
    a.Ads_units,
    a.Ads_cost,
    COALESCE(lh.price, lc.price) AS product_price,
    mp.median_price,
    SAFE_DIVIDE(COALESCE(lh.price, lc.price), mp.median_price) AS price_ratio,
    CASE
      WHEN COALESCE(h.holiday_name, 'Off-Season') IN ('Christmas', 'Black Friday', 'Cyber Monday')
        THEN 'Christmas'
      ELSE COALESCE(h.holiday_name, 'Off-Season')
    END AS season
  FROM `onyga-482313`.OI.FACT_AMAZON_ADS a
  JOIN `onyga-482313`.OI.DIM_PRODUCT p
    ON a.ASIN_BY_CAMPAIGN_NAME = p.asin
  JOIN converting_terms ct
    ON ct.search_term = a.search_term
  LEFT JOIN `onyga-482313`.OI.DIM_LISTING_HISTORY lh
    ON lh.asin1 = a.ASIN_BY_CAMPAIGN_NAME
    AND DATETIME(a.date) >= lh.effective_from
    AND DATETIME(a.date) < COALESCE(lh.effective_to, DATETIME '9999-12-31')
  LEFT JOIN `onyga-482313`.OI.V_DIM_LISTING_CURRENT lc
    ON lc.asin1 = a.ASIN_BY_CAMPAIGN_NAME
  JOIN product_launch pl
    ON a.ASIN_BY_CAMPAIGN_NAME = pl.asin
  LEFT JOIN holiday_windows h
    ON a.date BETWEEN h.boost_start AND h.holiday_date
  LEFT JOIN median_prices mp
    ON mp.query_text = a.search_term
  WHERE a.Ads_clicks > 0
    AND COALESCE(lh.price, lc.price) > 0
    AND a.date >= pl.mature_from
    AND p.parent_name IS NOT NULL
    AND mp.median_price IS NOT NULL
),

-- ═══ 6. Price bucket assignment ═══
bucketed AS (
  SELECT
    parent_name,
    date,
    Ads_clicks,
    Ads_units,
    Ads_cost,
    season,
    price_ratio,
    CASE
      WHEN price_ratio < 0.8 THEN 'A. Cheaper'
      WHEN price_ratio < 1.2 THEN 'B. Sweet spot'
      WHEN price_ratio < 1.8 THEN 'C. Pricier'
      WHEN price_ratio < 2.5 THEN 'D. Much pricier'
      ELSE 'E. Way above'
    END AS price_bucket,
    CASE
      WHEN price_ratio < 0.8 THEN 0.0
      WHEN price_ratio < 1.2 THEN 0.8
      WHEN price_ratio < 1.8 THEN 1.2
      WHEN price_ratio < 2.5 THEN 1.8
      ELSE 2.5
    END AS price_ratio_low,
    CASE
      WHEN price_ratio < 0.8 THEN 0.8
      WHEN price_ratio < 1.2 THEN 1.2
      WHEN price_ratio < 1.8 THEN 1.8
      WHEN price_ratio < 2.5 THEN 2.5
      ELSE 999.0
    END AS price_ratio_high
  FROM tagged
),

-- ═══ 6. Maturity filter: products with 8+ months of data ═══
mature_products AS (
  SELECT
    b.parent_name
  FROM bucketed b
  JOIN `onyga-482313`.OI.DIM_PRODUCT p3
    ON p3.parent_name = b.parent_name
  JOIN product_launch pl
    ON pl.asin = p3.asin
  GROUP BY b.parent_name, pl.mature_from
  HAVING DATE_DIFF(MAX(b.date), pl.mature_from, MONTH) >= 8
),

-- ═══ 7a. Per-product per-season aggregation ═══
per_product AS (
  SELECT
    parent_name,
    price_bucket,
    ANY_VALUE(price_ratio_low) AS price_ratio_low,
    ANY_VALUE(price_ratio_high) AS price_ratio_high,
    season AS holiday_name,
    SUM(Ads_clicks) AS total_clicks,
    SUM(Ads_units) AS total_orders,
    SAFE_DIVIDE(SUM(Ads_clicks), SUM(Ads_units)) AS clicks_per_sale,
    SAFE_DIVIDE(SUM(Ads_units), SUM(Ads_clicks)) * 100 AS cvr_pct,
    SAFE_DIVIDE(SUM(Ads_cost), SUM(Ads_units)) AS cost_per_sale,
    SAFE_DIVIDE(SUM(Ads_cost), SUM(Ads_clicks)) AS avg_cpc
  FROM bucketed
  WHERE parent_name IN (SELECT parent_name FROM mature_products)
  GROUP BY parent_name, price_bucket, season
  HAVING SUM(Ads_clicks) >= 20
),

-- ═══ 7b. Per-product _ALL holiday aggregation ═══
per_product_all_holiday AS (
  SELECT
    parent_name,
    price_bucket,
    ANY_VALUE(price_ratio_low) AS price_ratio_low,
    ANY_VALUE(price_ratio_high) AS price_ratio_high,
    '_ALL' AS holiday_name,
    SUM(Ads_clicks) AS total_clicks,
    SUM(Ads_units) AS total_orders,
    SAFE_DIVIDE(SUM(Ads_clicks), SUM(Ads_units)) AS clicks_per_sale,
    SAFE_DIVIDE(SUM(Ads_units), SUM(Ads_clicks)) * 100 AS cvr_pct,
    SAFE_DIVIDE(SUM(Ads_cost), SUM(Ads_units)) AS cost_per_sale,
    SAFE_DIVIDE(SUM(Ads_cost), SUM(Ads_clicks)) AS avg_cpc
  FROM bucketed
  WHERE parent_name IN (SELECT parent_name FROM mature_products)
  GROUP BY parent_name, price_bucket
  HAVING SUM(Ads_clicks) >= 20
),

-- ═══ 8a. Global aggregation (_ALL parent) per season ═══
global_agg AS (
  SELECT
    '_ALL' AS parent_name,
    price_bucket,
    ANY_VALUE(price_ratio_low) AS price_ratio_low,
    ANY_VALUE(price_ratio_high) AS price_ratio_high,
    season AS holiday_name,
    SUM(Ads_clicks) AS total_clicks,
    SUM(Ads_units) AS total_orders,
    SAFE_DIVIDE(SUM(Ads_clicks), SUM(Ads_units)) AS clicks_per_sale,
    SAFE_DIVIDE(SUM(Ads_units), SUM(Ads_clicks)) * 100 AS cvr_pct,
    SAFE_DIVIDE(SUM(Ads_cost), SUM(Ads_units)) AS cost_per_sale,
    SAFE_DIVIDE(SUM(Ads_cost), SUM(Ads_clicks)) AS avg_cpc
  FROM bucketed
  GROUP BY price_bucket, season
  HAVING SUM(Ads_clicks) >= 20
),

-- ═══ 8b. Global _ALL holiday aggregation ═══
global_all_holiday AS (
  SELECT
    '_ALL' AS parent_name,
    price_bucket,
    ANY_VALUE(price_ratio_low) AS price_ratio_low,
    ANY_VALUE(price_ratio_high) AS price_ratio_high,
    '_ALL' AS holiday_name,
    SUM(Ads_clicks) AS total_clicks,
    SUM(Ads_units) AS total_orders,
    SAFE_DIVIDE(SUM(Ads_clicks), SUM(Ads_units)) AS clicks_per_sale,
    SAFE_DIVIDE(SUM(Ads_units), SUM(Ads_clicks)) * 100 AS cvr_pct,
    SAFE_DIVIDE(SUM(Ads_cost), SUM(Ads_units)) AS cost_per_sale,
    SAFE_DIVIDE(SUM(Ads_cost), SUM(Ads_clicks)) AS avg_cpc
  FROM bucketed
  GROUP BY price_bucket
  HAVING SUM(Ads_clicks) >= 20
)

-- ═══ Final UNION ═══
SELECT * FROM per_product
UNION ALL
SELECT * FROM per_product_all_holiday
UNION ALL
SELECT * FROM global_agg
UNION ALL
SELECT * FROM global_all_holiday
