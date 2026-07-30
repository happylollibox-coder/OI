-- V_OOB_SEARCH_TERM — search-term layer of the Out-of-budget phase. Spec: architecture/OOB_BUDGET_PHASE.md §v2.
--
-- One row per (OOB campaign, target, search term) over the last 28 complete days. NEGATE rule
-- (Ori 2026-07-30): >= 10 clicks AND 0 orders, AND the term is not the keyword itself —
--   MANUAL keywords: term != keyword (normalized). A term that IS the keyword is what you bid on;
--     off-keyword traffic eating clicks without converting gets negated (negative exact).
--   AUTO clauses: no term!=keyword test — every auto term differs by construction; the 0-order
--     gate does the work so harvesting isn't killed.
--   PT (product targets): EXCLUDED — the "term" is the targeted ASIN; negating it = pausing the
--     target, which is a bid/state decision, not a negative keyword.
-- Winners (orders > 0) are surfaced and never negated.
CREATE OR REPLACE VIEW `onyga-482313.OI.V_OOB_SEARCH_TERM` AS
WITH wm AS (SELECT LEAST(MAX(date), `onyga-482313.OI.FN_ADS_ANCHOR_CAP`()) AS d
            FROM `onyga-482313.OI.FACT_AMAZON_ADS`),
oob AS (
  SELECT campaign_id FROM `onyga-482313.OI.V_OOB_BUDGET_PHASE`
  WHERE channel = 'SP' AND pct_dark > 10
),
st AS (
  SELECT CAST(a.campaign_id AS STRING) AS campaign_id,
    CAST(a.keyword_id AS STRING) AS keyword_id,
    a.targeting AS target_text, a.SEARCH_TERM AS search_term,
    CASE WHEN LOWER(a.targeting) IN ('close-match','loose-match','substitutes','complements') THEN 'AUTO'
         WHEN LOWER(a.targeting) LIKE 'asin%' THEN 'PT'
         ELSE 'MANUAL' END AS kind,
    SUM(a.Ads_clicks) AS clicks, SUM(a.Ads_orders) AS orders,
    SUM(a.Ads_cost) AS spend, SUM(a.Ads_sales) AS sales, SUM(a.GROSS_PROFIT) AS gp
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` a
  JOIN oob o ON o.campaign_id = CAST(a.campaign_id AS STRING)
  WHERE a.SEARCH_TERM IS NOT NULL AND a.SEARCH_TERM != ''
    AND a.date BETWEEN DATE_SUB((SELECT d FROM wm), INTERVAL 27 DAY) AND (SELECT d FROM wm)
  GROUP BY 1, 2, 3, 4, 5
)
SELECT campaign_id, keyword_id, target_text, search_term, kind,
  clicks, orders, ROUND(spend, 2) AS spend, ROUND(sales, 2) AS sales,
  ROUND(SAFE_DIVIDE(gp, NULLIF(spend, 0)), 2) AS net_roas,
  (LOWER(TRIM(search_term)) = LOWER(TRIM(target_text))) AS term_is_keyword,
  (orders > 0) AS is_winner,
  (clicks >= 10 AND orders = 0 AND kind != 'PT'
   AND (kind = 'AUTO' OR LOWER(TRIM(search_term)) != LOWER(TRIM(target_text)))) AS is_negate
FROM st
WHERE clicks > 0;
