-- V_FAMILY_NET_PROFIT_7D — the family split weight for the budget waterfall.
-- Ori 2026-07-05: weight = daily-average net profit over the last 7 FULL-DATA days (not ads-only,
-- and NOT a naive CURRENT_DATE-7 window that pulls in a half-settled tail day). Anchors on the
-- organic watermark (last complete Seller-Central load) — same anchor as V_SUMMARY_7D / V_DATA_FRESHNESS.
--   • product families → real business net profit/day (gross_margin - ad_cost, incl organic)
--   • Store / Unknown (no product P&L) → fall back to ads net profit/day
CREATE OR REPLACE VIEW `onyga-482313.OI.V_FAMILY_NET_PROFIT_7D` AS
WITH wm AS (
  -- Sessions gate skips mid-sync partial days (orders land before sessions).
  -- Same rule as V_SUMMARY_7D / V_DATA_FRESHNESS / V_PLAN_FORECAST — see architecture/ORDERS_WATERMARK.md.
  SELECT MAX(date) AS d
  FROM (
    SELECT date
    FROM `onyga-482313.OI.FACT_AMAZON_PERFORMANCE_DAILY`
    WHERE Performance_TYPE = 'Organic'
    GROUP BY date
    HAVING SUM(ASIN_SESSIONS) > 0
  )
),
fam AS (SELECT DISTINCT parent_name FROM `onyga-482313.OI.V_CAMPAIGN_FAMILY_MAP`),
product_np AS (   -- product-family real business net profit, avg/day over the 7 full days
  SELECT u.family AS parent_name,
    SUM(u.gross_margin - u.ad_cost) / 7 AS business_net_profit_avg
  FROM `onyga-482313.OI.V_UNIFIED_DAILY` u, wm
  WHERE u.date BETWEEN DATE_SUB(wm.d, INTERVAL 6 DAY) AND wm.d
  GROUP BY u.family
),
ads_np AS (       -- ads net profit per family, same 7 full days (Store/Unknown fallback weight)
  SELECT m.parent_name,
    SUM(a.GROSS_PROFIT - a.Ads_cost) / 7 AS ads_net_profit_avg
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` a, wm
  JOIN `onyga-482313.OI.V_CAMPAIGN_FAMILY_MAP` m ON m.campaign_id = a.campaign_id
  WHERE a.date BETWEEN DATE_SUB(wm.d, INTERVAL 6 DAY) AND wm.d
  GROUP BY m.parent_name
)
SELECT
  f.parent_name,
  ROUND(pn.business_net_profit_avg, 2) AS business_net_profit_avg,
  ROUND(an.ads_net_profit_avg, 2)      AS ads_net_profit_avg,
  GREATEST(COALESCE(pn.business_net_profit_avg, an.ads_net_profit_avg, 0), 0) AS weight
FROM fam f
LEFT JOIN product_np pn ON pn.parent_name = f.parent_name
LEFT JOIN ads_np an     ON an.parent_name = f.parent_name;
