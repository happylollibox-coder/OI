-- V_WEEKLY_RUN_PRODUCT — per-product (family / Store / Unknown) budget-decision panel for Weekly Run Step 2.
-- Metrics are a TRAILING-7-DAY DAILY AVERAGE (recent run-rate, not stale 30/60d) — the current Sun–Sat week
-- is too thin with ads lag, so we use the last 7 days over days-with-data. Shows net profit/day (business,
-- incl organic), ads net ROAS, ads spend/day, current budget, and a suggested daily budget (profit+ROAS rule).
-- Reads the materialized campaign map for attribution. Backend-owned (all-logic-in-backend).
CREATE OR REPLACE VIEW `onyga-482313.OI.V_WEEKLY_RUN_PRODUCT` AS
WITH win AS (
  SELECT DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL 7 DAY) AS d0
),
camps AS (  -- product list + campaign count (incl Store / Unknown)
  SELECT product, COUNT(*) AS campaigns
  FROM `onyga-482313.OI.T_WEEKLY_RUN_CAMPAIGN`
  GROUP BY product
),
ads AS (  -- trailing-7d ads, attributed to product via the campaign map (covers all products)
  SELECT
    c.product,
    SUM(f.GROSS_PROFIT - f.Ads_cost) AS ads_net,
    SUM(f.Ads_cost)                  AS ads_spend,
    SUM(f.GROSS_PROFIT)              AS ads_gp,
    COUNT(DISTINCT f.date)           AS days
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` f
  JOIN `onyga-482313.OI.T_WEEKLY_RUN_CAMPAIGN` c ON c.campaign_id = f.campaign_id
  CROSS JOIN win
  WHERE f.date >= win.d0
  GROUP BY c.product
),
biz AS (  -- trailing-7d business net incl organic, per family (Store/Unknown have none)
  SELECT u.family AS product, SUM(u.sales - u.cogs - u.ad_cost) AS biz_net, COUNT(DISTINCT u.date) AS days
  FROM `onyga-482313.OI.V_UNIFIED_DAILY` u
  CROSS JOIN win
  WHERE u.date >= win.d0
  GROUP BY u.family
),
budget AS (  -- latest set product budget (weekly → daily)
  SELECT product, weekly_budget FROM (
    SELECT parent_name AS product, weekly_budget,
      ROW_NUMBER() OVER (PARTITION BY parent_name ORDER BY week_start DESC) AS rn
    FROM `onyga-482313.OI.DE_PRODUCT_BUDGET`
  ) WHERE rn = 1
)
SELECT
  cp.product,
  cp.campaigns,
  ROUND(SAFE_DIVIDE(a.ads_spend, a.days), 2)                  AS recent_daily_spend,   -- ads spend/day (7d)
  ROUND(SAFE_DIVIDE(a.ads_net, a.days), 2)                    AS ads_net_day,          -- ads net/day (7d)
  ROUND(SAFE_DIVIDE(a.ads_gp, NULLIF(a.ads_spend, 0)), 2)     AS ads_net_roas,         -- ads net ROAS (7d)
  ROUND(SAFE_DIVIDE(b.biz_net, b.days), 2)                    AS net_profit_day,       -- business net/day incl organic (7d)
  ROUND(bud.weekly_budget / 7, 2)                            AS current_daily_budget,
  -- suggested daily budget: grow winners (ROAS ≥ 1.1 & profitable), cut losers, else hold — on the 7d run-rate
  ROUND(SAFE_DIVIDE(a.ads_spend, a.days) * CASE
    WHEN SAFE_DIVIDE(a.ads_gp, NULLIF(a.ads_spend, 0)) >= 1.1
         AND COALESCE(b.biz_net, a.ads_net) > 0 THEN 1.15
    WHEN SAFE_DIVIDE(a.ads_gp, NULLIF(a.ads_spend, 0)) < 1.0
         OR  COALESCE(b.biz_net, a.ads_net) < 0 THEN 0.80
    ELSE 1.0 END, 2)                                         AS suggested_daily_budget
FROM camps cp
LEFT JOIN ads a    USING (product)
LEFT JOIN biz b    USING (product)
LEFT JOIN budget bud USING (product);
