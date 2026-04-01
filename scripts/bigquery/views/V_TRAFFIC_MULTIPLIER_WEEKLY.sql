-- =============================================
-- OI Database Project - V_TRAFFIC_MULTIPLIER_WEEKLY View
-- =============================================
--
-- Purpose: Weekly forward-looking traffic multipliers
--          Uses ASIN B0C1VLXYBP only to determine market traffic levels
-- Source: FACT_AMAZON_SEARCH_PERFORMANCE_WEEKLY
-- Project: onyga-482313
-- Dataset: OI
--
-- Logic:
-- - TRAFFIC_MULTIPLIER_THIS_WEEK: this_week / last_week
-- - TRAFFIC_MULTIPLIER_NEXT_WEEK: (next 1 week orders) / this_week
-- - TRAFFIC_MULTIPLIER_NEXT_MONTH: (next 4 weeks orders) / this_week
-- - TRAFFIC_MULTIPLIER_NEXT_3_MONTH: (next 12 weeks orders) / this_week
-- - TRAFFIC_MULTIPLIER_END_OF_YEAR: (remaining to EOY) / this_week
--
-- =============================================

CREATE OR REPLACE VIEW `onyga-482313.OI.V_TRAFFIC_MULTIPLIER_WEEKLY`
AS
WITH weekly_orders_dedup AS (
  -- Deduplicate: AMAZON_ORDERS is same per Search_Query, take one per query for this ASIN
  SELECT
    Reporting_Date,
    Search_Query,
    MAX(AMAZON_ORDERS) AS amazon_orders
  FROM `onyga-482313.OI.FACT_AMAZON_SEARCH_PERFORMANCE_WEEKLY`
  WHERE ASIN = 'B0C1VLXYBP'
    AND EXTRACT(YEAR FROM Reporting_Date) >= 2025
    AND AMAZON_ORDERS IS NOT NULL
  GROUP BY Reporting_Date, Search_Query
),
weekly_totals AS (
  SELECT
    Reporting_Date,
    SUM(amazon_orders) AS total_amazon_orders
  FROM weekly_orders_dedup
  GROUP BY Reporting_Date
),
with_cumsum AS (
  SELECT
    Reporting_Date,
    total_amazon_orders,
    SUM(total_amazon_orders) OVER (
      PARTITION BY EXTRACT(YEAR FROM Reporting_Date)
      ORDER BY Reporting_Date
      ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS cumsum_inclusive,
    SUM(total_amazon_orders) OVER (
      PARTITION BY EXTRACT(YEAR FROM Reporting_Date)
    ) AS total_year_orders,
    FIRST_VALUE(total_amazon_orders) OVER (
      PARTITION BY EXTRACT(YEAR FROM Reporting_Date)
      ORDER BY Reporting_Date
      ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
    ) AS beginning_of_year_orders
  FROM weekly_totals
),
with_lead AS (
  SELECT
    *,
    LAG(total_amazon_orders, 1) OVER (PARTITION BY EXTRACT(YEAR FROM Reporting_Date) ORDER BY Reporting_Date) AS total_amazon_orders_at_week_minus_1,
    LEAD(cumsum_inclusive, 1) OVER (PARTITION BY EXTRACT(YEAR FROM Reporting_Date) ORDER BY Reporting_Date) AS cumsum_at_week_plus_1,
    LEAD(cumsum_inclusive, 4) OVER (PARTITION BY EXTRACT(YEAR FROM Reporting_Date) ORDER BY Reporting_Date) AS cumsum_at_week_plus_4,
    LEAD(cumsum_inclusive, 12) OVER (PARTITION BY EXTRACT(YEAR FROM Reporting_Date) ORDER BY Reporting_Date) AS cumsum_at_week_plus_12
  FROM with_cumsum
)
SELECT
  Reporting_Date,
  total_amazon_orders,
  SAFE_DIVIDE(total_amazon_orders, total_amazon_orders_at_week_minus_1) AS TRAFFIC_MULTIPLIER_THIS_WEEK,
  SAFE_DIVIDE(cumsum_at_week_plus_1 - cumsum_inclusive, total_amazon_orders) AS TRAFFIC_MULTIPLIER_NEXT_WEEK,
  SAFE_DIVIDE(cumsum_at_week_plus_4 - cumsum_inclusive, total_amazon_orders) AS TRAFFIC_MULTIPLIER_NEXT_MONTH,
  SAFE_DIVIDE(cumsum_at_week_plus_12 - cumsum_inclusive, total_amazon_orders) AS TRAFFIC_MULTIPLIER_NEXT_3_MONTH,
  SAFE_DIVIDE(total_year_orders - cumsum_inclusive, total_amazon_orders) AS TRAFFIC_MULTIPLIER_END_OF_YEAR
FROM with_lead
WHERE Reporting_Date <= '2025-12-31';
