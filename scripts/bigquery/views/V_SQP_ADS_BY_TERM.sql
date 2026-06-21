-- V_SQP_ADS_BY_TERM
-- Per (search_term, asin, week): real SQP funnel (FACT_AMAZON_SEARCH_PERFORMANCE_WEEKLY)
-- FULL OUTER JOINed to weekly-aggregated paid ads (FACT_AMAZON_ADS).
-- Grain kept at asin so the dashboard can filter by family (parent_name) and roll up.
CREATE OR REPLACE VIEW `onyga-482313.OI.V_SQP_ADS_BY_TERM` AS
WITH sqp AS (
  SELECT
    Reporting_Date                          AS reporting_date,
    DATE_SUB(Reporting_Date, INTERVAL 6 DAY) AS week_start,
    ASIN                                    AS asin,
    LOWER(TRIM(Search_Query))               AS term_key,
    Search_Query                            AS search_term,
    Impressions                             AS impressions,
    Clicks                                  AS clicks,
    Cart_Adds                               AS cart_adds,
    ORDERS                                  AS orders,
    ORGANIC_ORDERS                          AS organic_orders,
    AMAZON_IMPRESSIONS                      AS amazon_impressions,
    AMAZON_Clicks                           AS amazon_clicks,
    AMAZON_Cart_Adds                        AS amazon_cart_adds,
    AMAZON_ORDERS                           AS amazon_orders,
    show_rate_pct,
    estimated_organic_rank,
    organic_rank_zone,
    Search_Query_Score                      AS search_query_score
  FROM `onyga-482313.OI.FACT_AMAZON_SEARCH_PERFORMANCE_WEEKLY`
  WHERE DATA_SOURCE = 'SQP'           -- exclude SCP 'OTHER' aggregate rows
),
ads AS (
  SELECT
    DATE_ADD(DATE_TRUNC(date, WEEK(SUNDAY)), INTERVAL 6 DAY) AS reporting_date,
    COALESCE(most_advertised_asin_impressions, ASIN_BY_CAMPAIGN_NAME) AS asin,
    LOWER(TRIM(search_term))  AS term_key,
    ANY_VALUE(search_term)    AS search_term,
    SUM(Ads_cost)             AS ad_spend,
    SUM(Ads_sales)            AS ad_sales,
    SUM(Ads_units)            AS ad_units,
    SUM(GROSS_PROFIT)         AS ad_gross_profit,
    SUM(Ads_clicks)           AS ad_clicks,
    SUM(Ads_orders)           AS ad_orders,
    SUM(Ads_impressions)      AS ad_impressions
  FROM `onyga-482313.OI.FACT_AMAZON_ADS`
  WHERE search_term IS NOT NULL AND TRIM(search_term) != ''
  GROUP BY reporting_date, asin, term_key
)
SELECT
  COALESCE(s.reporting_date, a.reporting_date)                       AS reporting_date,
  COALESCE(s.week_start, DATE_SUB(a.reporting_date, INTERVAL 6 DAY)) AS week_start,
  COALESCE(s.asin, a.asin)                                           AS asin,
  p.parent_name,
  p.product_short_name,
  COALESCE(s.search_term, a.search_term)                            AS search_term,
  COALESCE(s.term_key, a.term_key)                                  AS term_key,
  -- SQP your funnel
  COALESCE(s.impressions, 0)     AS impressions,
  COALESCE(s.clicks, 0)          AS clicks,
  COALESCE(s.cart_adds, 0)       AS cart_adds,
  COALESCE(s.orders, 0)          AS orders,
  COALESCE(s.organic_orders, 0)  AS organic_orders,
  -- market (NULL on ads-only rows)
  s.amazon_impressions,
  s.amazon_clicks,
  s.amazon_cart_adds,
  s.amazon_orders,
  -- paid
  COALESCE(a.ad_impressions, 0)  AS ad_impressions,
  COALESCE(a.ad_clicks, 0)       AS ad_clicks,
  COALESCE(a.ad_orders, 0)       AS ad_orders,
  COALESCE(a.ad_units, 0)        AS ad_units,
  COALESCE(a.ad_spend, 0)        AS ad_spend,
  COALESCE(a.ad_sales, 0)        AS ad_sales,
  COALESCE(a.ad_gross_profit, 0) AS ad_gross_profit,
  -- SQP derived (NULL on ads-only rows)
  s.show_rate_pct,
  s.estimated_organic_rank,
  s.organic_rank_zone,
  s.search_query_score
FROM sqp s
FULL OUTER JOIN ads a
  ON  s.asin           = a.asin
  AND s.term_key       = a.term_key
  AND s.reporting_date = a.reporting_date
LEFT JOIN `onyga-482313.OI.DIM_PRODUCT` p
  ON COALESCE(s.asin, a.asin) = p.asin;
