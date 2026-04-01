-- =============================================
-- OI Database Project - V_AMAZON_ADS_TOP_SEARCH_QUERY_TERMS_WEEKLY
-- =============================================
--
-- Purpose: Weekly aggregated view of Amazon Ads search term performance
--          Matched to SQP weekly grain (ASIN × search_term × week_end_date)
-- Business Logic: Aggregates FACT_AMAZON_ADS by week using DIM_TIME
-- Dependencies: FACT_AMAZON_ADS, DIM_TIME
-- Consumer: SP_LOAD_FACT_AMAZON_SEARCH_PERFORMANCE_WEEKLY (Step 3-5)
-- Project: onyga-482313
-- Dataset: OI
--
-- =============================================

CREATE OR REPLACE VIEW `onyga-482313.OI.V_AMAZON_ADS_TOP_SEARCH_QUERY_TERMS_WEEKLY`
AS
WITH fact_weekly AS (
  SELECT
    td.week_end_date,
    fa.most_advertised_asin_impressions AS asin,
    fa.search_term,
    -- Aggregate measures
    SUM(COALESCE(fa.Ads_impressions, 0)) AS impressions,
    SUM(COALESCE(fa.Ads_clicks, 0))      AS clicks,
    SUM(COALESCE(fa.Ads_orders, 0))      AS orders,
    SUM(COALESCE(fa.Ads_units, 0))       AS units
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` fa
  INNER JOIN `onyga-482313.OI.DIM_TIME` td
    ON fa.date = td.full_date
  WHERE fa.search_term IS NOT NULL
    AND fa.most_advertised_asin_impressions IS NOT NULL
  GROUP BY
    td.week_end_date,
    fa.most_advertised_asin_impressions,
    fa.search_term
)
SELECT
  week_end_date,
  asin,
  search_term,
  -- Ad Key: YYYYMMDD-asin-search_term (matches SQP ad_key format)
  CONCAT(
    FORMAT_DATE('%Y%m%d', week_end_date),
    '-',
    asin,
    '-',
    search_term
  ) AS ad_key,
  -- Factless Key: YYYYMMDD-asin
  CONCAT(
    FORMAT_DATE('%Y%m%d', week_end_date),
    '-',
    asin
  ) AS factless_key,
  -- Fact measures
  impressions,
  clicks,
  orders,
  units
FROM fact_weekly;
