-- V_ADS_CHANNEL_EFFICIENCY
-- Per-family × month × search_type (BRAND / NON_BRAND) ads efficiency.
-- Provides CPC, CVR, Net ROAS split by brand vs non-brand keywords.
--
-- Grain: (family, yr, mo, search_type)
--
-- Metrics:
--   spend, clicks, units, orders, sales, impressions
--   cpc, unit_cvr_pct, net_roas
--   current_30d_daily_spend, current_30d_cpc
--
-- Classification:
--   BRAND = search_term matches any phrase in DIM_BRAND_PHRASES
--   NON_BRAND = everything else
--
-- Dependencies: FACT_AMAZON_ADS, DIM_BRAND_PHRASES, DIM_PRODUCT, DIM_COSTS_HISTORY
-- Invariant #8: All business logic in SQL.

CREATE OR REPLACE VIEW `onyga-482313.OI.V_ADS_CHANNEL_EFFICIENCY` AS

WITH

-- All brand phrases for matching
brand_phrases AS (
  SELECT LOWER(phrase) AS phrase
  FROM `onyga-482313.OI.DIM_BRAND_PHRASES`
),

-- Deduplicate branded search terms (any search term containing a brand phrase)
branded_search_terms AS (
  SELECT DISTINCT LOWER(a.search_term) AS term
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` a
  JOIN brand_phrases bp ON LOWER(a.search_term) LIKE CONCAT('%', bp.phrase, '%')
  WHERE a.search_term IS NOT NULL
    AND a.date >= DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL 13 MONTH)
),

-- Unit economics per ASIN (for Net ROAS calculation)
asin_costs AS (
  SELECT
    p.asin,
    p.parent_name AS family,
    p.listing_price_amount AS price,
    COALESCE(ch.TOTAL_COST_PER_UNIT, 0) AS cost_per_unit
  FROM `onyga-482313.OI.DIM_PRODUCT` p
  LEFT JOIN (
    SELECT asin, TOTAL_COST_PER_UNIT,
      ROW_NUMBER() OVER (PARTITION BY asin ORDER BY end_date DESC NULLS FIRST) AS rn
    FROM `onyga-482313.OI.DIM_COSTS_HISTORY`
  ) ch ON p.asin = ch.asin AND ch.rn = 1
  WHERE p.asin IS NOT NULL AND p.parent_name IS NOT NULL
),

-- Tag every ads row with BRAND or NON_BRAND
ads_tagged AS (
  SELECT
    a.date,
    COALESCE(ac.family, 'Unknown') AS family,
    CASE WHEN bst.term IS NOT NULL THEN 'BRAND' ELSE 'NON_BRAND' END AS search_type,
    a.Ads_cost AS spend,
    a.Ads_clicks AS clicks,
    a.Ads_units AS units,
    a.Ads_orders AS orders,
    a.Ads_sales AS sales,
    a.Ads_impressions AS impressions,
    -- For net ROAS: gross profit = (price - cost) × units - spend
    COALESCE(ac.price, 0) AS price,
    COALESCE(ac.cost_per_unit, 0) AS cost_per_unit
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` a
  LEFT JOIN asin_costs ac ON COALESCE(a.most_advertised_asin_impressions, a.ASIN_BY_CAMPAIGN_NAME) = ac.asin
  LEFT JOIN branded_search_terms bst ON LOWER(a.search_term) = bst.term
  WHERE a.date >= DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL 13 MONTH)
    AND a.search_term IS NOT NULL
),

-- Monthly aggregation per family × search_type
monthly_agg AS (
  SELECT
    family,
    EXTRACT(YEAR FROM date) AS yr,
    EXTRACT(MONTH FROM date) AS mo,
    search_type,
    SUM(spend) AS spend,
    SUM(clicks) AS clicks,
    SUM(units) AS units,
    SUM(orders) AS orders,
    SUM(sales) AS sales,
    SUM(impressions) AS impressions,
    -- Gross profit for Net ROAS
    SUM((price - cost_per_unit) * units) AS gross_profit,
    COUNT(DISTINCT date) AS active_days
  FROM ads_tagged
  GROUP BY family, yr, mo, search_type
),

-- Current 30d metrics per family × search_type
current_30d AS (
  SELECT
    family,
    search_type,
    SUM(spend) AS spend_30d,
    SUM(clicks) AS clicks_30d,
    SUM(units) AS units_30d,
    COUNT(DISTINCT date) AS days_30d
  FROM ads_tagged
  WHERE date >= DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL 30 DAY)
  GROUP BY family, search_type
)

SELECT
  m.family,
  m.yr,
  m.mo,
  m.search_type,
  m.spend,
  m.clicks,
  m.units,
  m.orders,
  m.sales,
  m.impressions,
  m.active_days,

  -- Derived efficiency metrics
  ROUND(SAFE_DIVIDE(m.spend, NULLIF(m.clicks, 0)), 3) AS cpc,
  ROUND(SAFE_DIVIDE(m.units, NULLIF(m.clicks, 0)) * 100, 2) AS unit_cvr_pct,
  ROUND(SAFE_DIVIDE(m.gross_profit, NULLIF(m.spend, 0)), 2) AS net_roas,
  ROUND(SAFE_DIVIDE(m.sales, NULLIF(m.spend, 0)), 2) AS gross_roas,

  -- Current run rate (trailing 30d)
  ROUND(SAFE_DIVIDE(c.spend_30d, NULLIF(c.days_30d, 0)), 2) AS current_daily_spend,
  ROUND(SAFE_DIVIDE(c.spend_30d, NULLIF(c.clicks_30d, 0)), 3) AS current_cpc,
  c.spend_30d AS current_30d_spend,
  c.units_30d AS current_30d_units

FROM monthly_agg m
LEFT JOIN current_30d c ON m.family = c.family AND m.search_type = c.search_type
WHERE m.family != 'Unknown'
ORDER BY m.family, m.yr, m.mo, m.search_type
