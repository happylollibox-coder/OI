-- =============================================
-- OI Database Project - Q_AMAZON_ADS_SQP_ORDERS_DIFF_BY_ASIN
-- =============================================
--
-- Purpose: Compare SQP total orders vs Amazon Ads view orders by ASIN
--          Shows difference: SQP orders - View orders for each ASIN as columns
-- Project: onyga-482313
-- Dataset: OI
--
-- =============================================

WITH sqp_orders AS (
  SELECT
    Week_End_date AS Reporting_Date,
    SKU AS asin,
    SUM(COALESCE(Purchases_ASIN_Count, 0)) AS sqp_total_orders
  FROM `onyga-482313.OI.SQP_ASIN_View_Simple_Week`
  WHERE SKU IN ('B09XQ56RK5', 'B0C1VLXYBP', 'B0CR6N3WRC', 'B0D7N2MLDP', 'B0D7N31M6S', 
                'B0DJFG5ZJ7', 'B0F4KCCSWN', 'B0F9X95K5H', 'B0F9XDSVYB', 'B0F9XFXQRW')
  GROUP BY Week_End_date, SKU
),
view_orders AS (
  SELECT
    week_end_date AS Reporting_Date,
    asin,
    SUM(COALESCE(orders, 0)) AS view_total_orders
  FROM `onyga-482313.OI.V_AMAZON_ADS_TOP_SEARCH_QUERY_TERMS_WEEKLY`
  WHERE asin IN ('B09XQ56RK5', 'B0C1VLXYBP', 'B0CR6N3WRC', 'B0D7N2MLDP', 'B0D7N31M6S', 
                 'B0DJFG5ZJ7', 'B0F4KCCSWN', 'B0F9X95K5H', 'B0F9XDSVYB', 'B0F9XFXQRW')
  GROUP BY week_end_date, asin
),
combined AS (
  SELECT
    COALESCE(sqp.Reporting_Date, view.Reporting_Date) AS Reporting_Date,
    COALESCE(sqp.asin, view.asin) AS asin,
    COALESCE(sqp.sqp_total_orders, 0) AS sqp_total_orders,
    COALESCE(view.view_total_orders, 0) AS view_total_orders,
    COALESCE(sqp.sqp_total_orders, 0) - COALESCE(view.view_total_orders, 0) AS orders_diff
  FROM sqp_orders sqp
  FULL OUTER JOIN view_orders view
    ON sqp.Reporting_Date = view.Reporting_Date
    AND sqp.asin = view.asin
)
SELECT
  Reporting_Date,
  SUM(CASE WHEN asin = 'B09XQ56RK5' THEN orders_diff ELSE 0 END) AS B09XQ56RK5,
  SUM(CASE WHEN asin = 'B0C1VLXYBP' THEN orders_diff ELSE 0 END) AS B0C1VLXYBP,
  SUM(CASE WHEN asin = 'B0CR6N3WRC' THEN orders_diff ELSE 0 END) AS B0CR6N3WRC,
  SUM(CASE WHEN asin = 'B0D7N2MLDP' THEN orders_diff ELSE 0 END) AS B0D7N2MLDP,
  SUM(CASE WHEN asin = 'B0D7N31M6S' THEN orders_diff ELSE 0 END) AS B0D7N31M6S,
  SUM(CASE WHEN asin = 'B0DJFG5ZJ7' THEN orders_diff ELSE 0 END) AS B0DJFG5ZJ7,
  SUM(CASE WHEN asin = 'B0F4KCCSWN' THEN orders_diff ELSE 0 END) AS B0F4KCCSWN,
  SUM(CASE WHEN asin = 'B0F9X95K5H' THEN orders_diff ELSE 0 END) AS B0F9X95K5H,
  SUM(CASE WHEN asin = 'B0F9XDSVYB' THEN orders_diff ELSE 0 END) AS B0F9XDSVYB,
  SUM(CASE WHEN asin = 'B0F9XFXQRW' THEN orders_diff ELSE 0 END) AS B0F9XFXQRW,
  SUM(orders_diff) AS Total
FROM combined
GROUP BY Reporting_Date
ORDER BY Reporting_Date DESC;
