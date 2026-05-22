-- V_BRAND_SEARCH_MONTHLY
-- Aggregates search purchases from SQP AND Ads at the FAMILY level, by month.
-- Splits into BRANDED (brand defense) and TOTAL (all queries) channels.
-- Non-brand = total - branded (computed in frontend).
--
-- Uses the SAME branded-term detection as V_BRAND_STRENGTH_WEEKLY:
--   DIM_BRAND_PHRASES joined to FACT_SEARCH_QUERY + FACT_AMAZON_ADS.
--
-- Grain: (year, month, family) — one row per month per product family.
--
-- Key metrics:
--   branded_purchases  = SQP conversions from brand searches
--   ads_units          = ad units on branded search terms (brand defense)
--   ads_spend          = ad spend on branded search terms
--   total_sqp_purchases  = SQP conversions from ALL searches
--   total_ads_units      = ad units from ALL search terms
--   total_ads_spend      = ad spend on ALL search terms
--
-- Used by: PlanWizard Growth step — Brand / Non-brand / Combined demand.
--
-- Dependencies: FACT_SEARCH_QUERY, FACT_AMAZON_ADS, DIM_BRAND_PHRASES, DIM_PRODUCT
CREATE OR REPLACE VIEW `onyga-482313.OI.V_BRAND_SEARCH_MONTHLY` AS
WITH brand_terms AS (
  SELECT phrase AS term
  FROM `onyga-482313.OI.DIM_BRAND_PHRASES`
),

-- ═══ BRANDED CHANNEL ═══

-- SQP branded queries (dedup step)
branded_queries AS (
  SELECT DISTINCT LOWER(sq.query_text) AS bq
  FROM `onyga-482313.OI.FACT_SEARCH_QUERY` sq
  JOIN brand_terms bt ON LOWER(sq.query_text) LIKE CONCAT('%', bt.term, '%')
  WHERE sq.week_start_date IS NOT NULL
),
-- SQP branded aggregated
branded_sqp AS (
  SELECT
    sq.Year  AS yr,
    EXTRACT(MONTH FROM sq.week_start_date) AS mo,
    COALESCE(p.parent_name, 'Unknown') AS family,
    SUM(sq.conversions) AS branded_purchases,
    SUM(sq.impressions) AS branded_impressions,
    SUM(sq.clicks)      AS branded_clicks
  FROM `onyga-482313.OI.FACT_SEARCH_QUERY` sq
  JOIN branded_queries bq ON LOWER(sq.query_text) = bq.bq
  LEFT JOIN `onyga-482313.OI.DIM_PRODUCT` p ON sq.ASIN = p.asin
  WHERE sq.week_start_date IS NOT NULL
  GROUP BY yr, mo, family
),
-- Ads branded search terms (dedup step)
branded_search_terms AS (
  SELECT DISTINCT LOWER(a.search_term) AS bst
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` a
  JOIN brand_terms bt ON LOWER(a.search_term) LIKE CONCAT('%', bt.term, '%')
  WHERE a.search_term IS NOT NULL
),
-- Ads branded aggregated
branded_ads AS (
  SELECT
    EXTRACT(YEAR FROM a.date) AS yr,
    EXTRACT(MONTH FROM a.date) AS mo,
    COALESCE(p.parent_name, 'Unknown') AS family,
    SUM(a.Ads_units)  AS ads_units,
    SUM(a.Ads_orders) AS ads_orders,
    SUM(a.Ads_cost)   AS ads_spend,
    SUM(a.Ads_sales)  AS ads_sales
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` a
  JOIN branded_search_terms bst ON LOWER(a.search_term) = bst.bst
  LEFT JOIN `onyga-482313.OI.DIM_PRODUCT` p ON a.ASIN_BY_CAMPAIGN_NAME = p.asin
  WHERE a.search_term IS NOT NULL
  GROUP BY yr, mo, family
),
-- Branded combined
branded_monthly AS (
  SELECT
    COALESCE(s.yr, a.yr) AS yr,
    COALESCE(s.mo, a.mo) AS mo,
    COALESCE(s.family, a.family) AS family,
    COALESCE(s.branded_purchases, 0) AS branded_purchases,
    COALESCE(s.branded_impressions, 0) AS branded_impressions,
    COALESCE(s.branded_clicks, 0) AS branded_clicks,
    COALESCE(a.ads_units, 0) AS branded_ads_units,
    COALESCE(a.ads_orders, 0) AS branded_ads_orders,
    COALESCE(a.ads_spend, 0) AS branded_ads_spend,
    COALESCE(a.ads_sales, 0) AS branded_ads_sales
  FROM branded_sqp s
  FULL OUTER JOIN branded_ads a
    ON s.yr = a.yr AND s.mo = a.mo AND s.family = a.family
),

-- ═══ TOTAL CHANNEL (all queries, no brand filter) ═══

-- Total SQP (all queries)
total_sqp AS (
  SELECT
    sq.Year AS yr,
    EXTRACT(MONTH FROM sq.week_start_date) AS mo,
    COALESCE(p.parent_name, 'Unknown') AS family,
    SUM(sq.conversions) AS total_sqp_purchases,
    SUM(sq.impressions) AS total_sqp_impressions,
    SUM(sq.clicks)      AS total_sqp_clicks
  FROM `onyga-482313.OI.FACT_SEARCH_QUERY` sq
  LEFT JOIN `onyga-482313.OI.DIM_PRODUCT` p ON sq.ASIN = p.asin
  WHERE sq.week_start_date IS NOT NULL
  GROUP BY yr, mo, family
),
-- Total Ads (all search terms)
total_ads AS (
  SELECT
    EXTRACT(YEAR FROM a.date) AS yr,
    EXTRACT(MONTH FROM a.date) AS mo,
    COALESCE(p.parent_name, 'Unknown') AS family,
    SUM(a.Ads_units)  AS total_ads_units,
    SUM(a.Ads_orders) AS total_ads_orders,
    SUM(a.Ads_cost)   AS total_ads_spend,
    SUM(a.Ads_sales)  AS total_ads_sales
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` a
  LEFT JOIN `onyga-482313.OI.DIM_PRODUCT` p ON a.ASIN_BY_CAMPAIGN_NAME = p.asin
  WHERE a.search_term IS NOT NULL
  GROUP BY yr, mo, family
),
-- Total combined
total_monthly AS (
  SELECT
    COALESCE(s.yr, a.yr) AS yr,
    COALESCE(s.mo, a.mo) AS mo,
    COALESCE(s.family, a.family) AS family,
    COALESCE(s.total_sqp_purchases, 0) AS total_sqp_purchases,
    COALESCE(s.total_sqp_impressions, 0) AS total_sqp_impressions,
    COALESCE(s.total_sqp_clicks, 0) AS total_sqp_clicks,
    COALESCE(a.total_ads_units, 0) AS total_ads_units,
    COALESCE(a.total_ads_orders, 0) AS total_ads_orders,
    COALESCE(a.total_ads_spend, 0) AS total_ads_spend,
    COALESCE(a.total_ads_sales, 0) AS total_ads_sales
  FROM total_sqp s
  FULL OUTER JOIN total_ads a
    ON s.yr = a.yr AND s.mo = a.mo AND s.family = a.family
)

-- ═══ FINAL: Join branded + total ═══
SELECT
  COALESCE(b.yr, t.yr) AS yr,
  COALESCE(b.mo, t.mo) AS mo,
  COALESCE(b.family, t.family) AS family,
  -- Branded channel
  COALESCE(b.branded_purchases, 0)  AS branded_purchases,
  COALESCE(b.branded_impressions, 0) AS branded_impressions,
  COALESCE(b.branded_clicks, 0)    AS branded_clicks,
  COALESCE(b.branded_ads_units, 0) AS ads_units,
  COALESCE(b.branded_ads_orders, 0) AS ads_orders,
  COALESCE(b.branded_ads_spend, 0) AS ads_spend,
  COALESCE(b.branded_ads_sales, 0) AS ads_sales,
  -- Total channel (all queries)
  COALESCE(t.total_sqp_purchases, 0)  AS total_sqp_purchases,
  COALESCE(t.total_sqp_impressions, 0) AS total_sqp_impressions,
  COALESCE(t.total_sqp_clicks, 0)    AS total_sqp_clicks,
  COALESCE(t.total_ads_units, 0)     AS total_ads_units,
  COALESCE(t.total_ads_orders, 0)    AS total_ads_orders,
  COALESCE(t.total_ads_spend, 0)     AS total_ads_spend,
  COALESCE(t.total_ads_sales, 0)     AS total_ads_sales
FROM branded_monthly b
FULL OUTER JOIN total_monthly t
  ON b.yr = t.yr AND b.mo = t.mo AND b.family = t.family;
