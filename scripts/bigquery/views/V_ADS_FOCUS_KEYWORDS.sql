-- V_ADS_FOCUS_KEYWORDS
-- Pre-ranks keyword targets by weekly net profit.
-- Groups by `targeting` (the bid keyword) instead of `search_term`.
-- Keeps top 10 winners + top 10 losers per week; remainder → __OTHER__.
-- ~21 rows/week × 26 weeks = ~546 rows → safe for Cube.js.

CREATE OR REPLACE VIEW `onyga-482313.OI.V_ADS_FOCUS_KEYWORDS` AS

WITH weekly AS (
  SELECT
    DATE_TRUNC(date, WEEK(SUNDAY))                  AS week_start,
    targeting                                        AS keyword,
    COALESCE(fa.most_advertised_asin_impressions, fa.ASIN_BY_CAMPAIGN_NAME) AS asin,
    SUM(Ads_cost)                                    AS spend,
    SUM(Ads_orders)                                  AS orders,
    SUM(Ads_sales)                                   AS sales,
    SUM(GROSS_PROFIT) - SUM(Ads_cost)                AS net_profit
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` fa
  WHERE (Ads_cost > 0 OR Ads_impressions > 0)
    AND targeting IS NOT NULL
    AND targeting != ''
    AND LOWER(targeting_type) IN ('exact', 'broad', 'phrase')
    AND date >= DATE_SUB(CURRENT_DATE(), INTERVAL 180 DAY)
  GROUP BY 1, 2, 3
),

ranked AS (
  SELECT *,
    ROW_NUMBER() OVER (PARTITION BY week_start ORDER BY net_profit DESC) AS rn_winner,
    ROW_NUMBER() OVER (PARTITION BY week_start ORDER BY net_profit ASC)  AS rn_loser
  FROM weekly
)

SELECT
  r.week_start,
  CASE
    WHEN rn_winner <= 10 AND net_profit > 0 THEN 'winner'
    WHEN rn_loser  <= 10 AND net_profit < 0 THEN 'loser'
    WHEN net_profit > 0 THEN 'other_winners'
    ELSE 'other_losers'
  END                                                                     AS focus_bucket,
  CASE
    WHEN rn_winner <= 10 OR rn_loser <= 10 THEN r.keyword
    ELSE '__OTHER__'
  END                                                                     AS keyword,
  CASE
    WHEN rn_winner <= 10 OR rn_loser <= 10 THEN r.asin
    ELSE NULL
  END                                                                     AS asin,
  CASE
    WHEN rn_winner <= 10 OR rn_loser <= 10 THEN p.product_short_name
    ELSE NULL
  END                                                                     AS product_short_name,
  SUM(r.spend)                                                            AS spend,
  SUM(r.orders)                                                           AS orders,
  SUM(r.sales)                                                            AS sales,
  SUM(r.net_profit)                                                       AS net_profit,
  COUNT(*)                                                                AS keyword_count
FROM ranked r
LEFT JOIN `onyga-482313.OI.DIM_PRODUCT` p ON r.asin = p.asin
GROUP BY 1, 2, 3, 4, 5;
