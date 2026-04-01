-- =============================================
-- Lollibox ads: monthly trend and Dec 2025 vs Feb 2026 campaign comparison
-- =============================================
--
-- Purpose: Research why Lollibox is not selling well lately.
--          OI has no Feb–Mar 2024 or Feb–Mar 2025 Lollibox ads (Lollibox starts Oct 2025).
--          This query compares available history: Oct 2025–Feb 2026 and Dec vs Feb by campaign.
--
-- Source:  FACT_AMAZON_ADS, Lollibox ASINs (B0C1VLXYBP, B0CR6N3WRC, B09XQ56RK5, B0DJFG5ZJ7)
-- Project: onyga-482313, Dataset: OI
--
-- =============================================

-- -----------------------------------------------------------------------------
-- Part 1: Lollibox monthly trend (Oct 2025 – latest)
-- -----------------------------------------------------------------------------
SELECT
  DATE_TRUNC(fa.date, MONTH) AS month,
  ROUND(SUM(fa.cost), 2)     AS lollibox_spend,
  SUM(fa.orders)             AS lollibox_orders,
  SUM(fa.clicks)             AS lollibox_clicks,
  ROUND(SAFE_DIVIDE(SUM(fa.cost), NULLIF(SUM(fa.clicks), 0)), 2) AS avg_cpc,
  ROUND(SAFE_DIVIDE(SUM(fa.orders), NULLIF(SUM(fa.clicks), 0)) * 100, 2) AS cvr_pct,
  COUNT(DISTINCT fa.campaign_id) AS campaign_count
FROM `onyga-482313.OI.FACT_AMAZON_ADS` fa
WHERE REGEXP_CONTAINS(fa.advertised_asins, r'B0C1VLXYBP|B0CR6N3WRC|B09XQ56RK5|B0DJFG5ZJ7')
GROUP BY 1
ORDER BY 1;


-- -----------------------------------------------------------------------------
-- Part 2: Campaign-level Dec 2025 vs Feb 2026 (what’s missing)
-- -----------------------------------------------------------------------------
SELECT
  fa.campaign_name,
  ROUND(SUM(CASE WHEN fa.date BETWEEN '2025-12-01' AND '2025-12-31' THEN fa.cost ELSE 0 END), 2)   AS dec2025_spend,
  SUM(CASE WHEN fa.date BETWEEN '2025-12-01' AND '2025-12-31' THEN fa.orders ELSE 0 END)            AS dec2025_orders,
  ROUND(SUM(CASE WHEN fa.date >= '2026-02-01' THEN fa.cost ELSE 0 END), 2)                         AS feb2026_spend,
  SUM(CASE WHEN fa.date >= '2026-02-01' THEN fa.orders ELSE 0 END)                                 AS feb2026_orders
FROM `onyga-482313.OI.FACT_AMAZON_ADS` fa
WHERE REGEXP_CONTAINS(fa.advertised_asins, r'B0C1VLXYBP|B0CR6N3WRC|B09XQ56RK5|B0DJFG5ZJ7')
  AND (fa.date BETWEEN '2025-12-01' AND '2025-12-31' OR fa.date >= '2026-02-01')
GROUP BY 1
HAVING dec2025_spend > 0 OR feb2026_spend > 0
ORDER BY dec2025_spend DESC;
