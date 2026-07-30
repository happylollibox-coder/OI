-- V_OOB_SEARCH_TERM — search-term layer of the Out-of-budget phase. Spec: architecture/OOB_BUDGET_PHASE.md §v2.
--
-- One row per (OOB campaign, target, search term), measured over TWO windows (Ori 2026-07-30:
-- "in order to negate general big words need to check 3 month data; small volume words 28 days
-- are enough"):
--   BIG general word  = >= 30 clicks over 90 complete days ACCOUNT-WIDE (all campaigns, SP+SB —
--     per-slice volume fragments a big word into "small" pieces; caught by Ori 2026-07-30 on
--     "teen girl gifts trendy stuff": 13 clicks in one keyword slice but 693 clicks / 6 orders
--     across 24 campaigns) → negate only if 0 orders over the FULL 90d ACCOUNT-WIDE.
--   SMALL word        = < 30 account-wide clicks/90d → negate at >= 10 clicks AND 0 orders over
--     28d at the (campaign, keyword) slice.
-- Plus the structural rules:
--   MANUAL keywords: term != keyword (normalized). A term that IS the keyword is what you bid on.
--   AUTO clauses: no term!=keyword test — every auto term differs by construction; the 0-order
--     gate does the work so harvesting isn't killed.
--   PT (product targets): EXCLUDED — the "term" is the targeted ASIN; negating it = pausing the
--     target, which is a bid/state decision, not a negative keyword.
-- Winners (orders in 90d) are surfaced and never negated.
CREATE OR REPLACE VIEW `onyga-482313.OI.V_OOB_SEARCH_TERM` AS
WITH wm AS (SELECT LEAST(MAX(date), `onyga-482313.OI.FN_ADS_ANCHOR_CAP`()) AS d
            FROM `onyga-482313.OI.FACT_AMAZON_ADS`),
oob AS (
  SELECT campaign_id FROM `onyga-482313.OI.V_OOB_BUDGET_PHASE`
  WHERE channel = 'SP' AND pct_dark > 10
),
-- SB arm (v2.1): dark SB campaigns' keyword-targeted search terms from sb_search_term_report.
-- kind='SB' behaves like MANUAL for the negate rule (SB keywords are all manual match types);
-- product-targeted SB rows live in sb_target_report where the "term" is the ASIN — excluded, like PT.
oob_sb AS (
  SELECT campaign_id FROM `onyga-482313.OI.V_OOB_BUDGET_PHASE`
  WHERE channel = 'SB' AND pct_dark > 10
),
wm_sb AS (SELECT LEAST(MAX(report_date), `onyga-482313.OI.FN_ADS_ANCHOR_CAP`()) AS d
          FROM `fivetran-hl.amazon_ads.sb_campaign_report`),
sb_kw AS (
  SELECT id, keyword_text FROM `fivetran-hl.amazon_ads.sb_keyword` WHERE NOT _fivetran_deleted
),
sb_st AS (
  SELECT CAST(r.campaign_id AS STRING) AS campaign_id,
    CAST(r.keyword_id AS STRING) AS keyword_id,
    COALESCE(k.keyword_text, CAST(r.keyword_id AS STRING)) AS target_text,
    r.query_term AS search_term, 'SB' AS kind,
    SUM(IF(r.report_date >= DATE_SUB((SELECT d FROM wm_sb), INTERVAL 27 DAY), r.clicks, 0)) AS clicks,
    SUM(IF(r.report_date >= DATE_SUB((SELECT d FROM wm_sb), INTERVAL 27 DAY), r.attributed_conversions_14_d, 0)) AS orders,
    SUM(IF(r.report_date >= DATE_SUB((SELECT d FROM wm_sb), INTERVAL 27 DAY), r.cost, 0)) AS spend,
    SUM(IF(r.report_date >= DATE_SUB((SELECT d FROM wm_sb), INTERVAL 27 DAY), r.attributed_sales_14_d, 0)) AS sales,
    -- gross ROAS only for SB terms (no per-term COGS estimate; the negate rule keys on clicks/orders)
    CAST(NULL AS FLOAT64) AS gp,
    SUM(r.clicks) AS clicks_90d, SUM(r.attributed_conversions_14_d) AS orders_90d, SUM(r.cost) AS spend_90d
  FROM `fivetran-hl.amazon_ads.sb_search_term_report` r
  JOIN oob_sb o ON o.campaign_id = CAST(r.campaign_id AS STRING)
  LEFT JOIN sb_kw k ON k.id = r.keyword_id
  WHERE r.query_term IS NOT NULL AND r.query_term != ''
    AND r.report_date BETWEEN DATE_SUB((SELECT d FROM wm_sb), INTERVAL 89 DAY) AND (SELECT d FROM wm_sb)
  GROUP BY 1, 2, 3, 4, 5
),
-- account-wide 90d volume + orders per TERM (all campaigns, both channels) — the "is it a big
-- general word" test and the big-word order protection both run on THIS, never on the slice.
term_all AS (
  SELECT term, SUM(clk) AS term_clicks_90d, SUM(ord) AS term_orders_90d FROM (
    SELECT LOWER(TRIM(SEARCH_TERM)) AS term, Ads_clicks AS clk, Ads_orders AS ord
    FROM `onyga-482313.OI.FACT_AMAZON_ADS`
    WHERE SEARCH_TERM IS NOT NULL AND SEARCH_TERM != ''
      AND date BETWEEN DATE_SUB((SELECT d FROM wm), INTERVAL 89 DAY) AND (SELECT d FROM wm)
    UNION ALL
    SELECT LOWER(TRIM(query_term)), clicks, attributed_conversions_14_d
    FROM `fivetran-hl.amazon_ads.sb_search_term_report`
    WHERE query_term IS NOT NULL AND query_term != ''
      AND report_date BETWEEN DATE_SUB((SELECT d FROM wm_sb), INTERVAL 89 DAY) AND (SELECT d FROM wm_sb)
  ) GROUP BY 1
),
st AS (
  SELECT CAST(a.campaign_id AS STRING) AS campaign_id,
    CAST(a.keyword_id AS STRING) AS keyword_id,
    a.targeting AS target_text, a.SEARCH_TERM AS search_term,
    CASE WHEN LOWER(a.targeting) IN ('close-match','loose-match','substitutes','complements') THEN 'AUTO'
         WHEN LOWER(a.targeting) LIKE 'asin%' THEN 'PT'
         ELSE 'MANUAL' END AS kind,
    SUM(IF(a.date >= DATE_SUB((SELECT d FROM wm), INTERVAL 27 DAY), a.Ads_clicks, 0)) AS clicks,
    SUM(IF(a.date >= DATE_SUB((SELECT d FROM wm), INTERVAL 27 DAY), a.Ads_orders, 0)) AS orders,
    SUM(IF(a.date >= DATE_SUB((SELECT d FROM wm), INTERVAL 27 DAY), a.Ads_cost, 0)) AS spend,
    SUM(IF(a.date >= DATE_SUB((SELECT d FROM wm), INTERVAL 27 DAY), a.Ads_sales, 0)) AS sales,
    SUM(IF(a.date >= DATE_SUB((SELECT d FROM wm), INTERVAL 27 DAY), a.GROSS_PROFIT, 0)) AS gp,
    SUM(a.Ads_clicks) AS clicks_90d, SUM(a.Ads_orders) AS orders_90d, SUM(a.Ads_cost) AS spend_90d
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` a
  JOIN oob o ON o.campaign_id = CAST(a.campaign_id AS STRING)
  WHERE a.SEARCH_TERM IS NOT NULL AND a.SEARCH_TERM != ''
    AND a.date BETWEEN DATE_SUB((SELECT d FROM wm), INTERVAL 89 DAY) AND (SELECT d FROM wm)
  GROUP BY 1, 2, 3, 4, 5
)
SELECT u.campaign_id, u.keyword_id, u.target_text, u.search_term, u.kind,
  u.clicks, u.orders, ROUND(u.spend, 2) AS spend, ROUND(u.sales, 2) AS sales,
  ROUND(SAFE_DIVIDE(u.gp, NULLIF(u.spend, 0)), 2) AS net_roas,
  u.clicks_90d, u.orders_90d, ROUND(u.spend_90d, 2) AS spend_90d,
  COALESCE(ta.term_clicks_90d, 0) AS term_clicks_90d,
  COALESCE(ta.term_orders_90d, 0) AS term_orders_90d,
  -- BIG general word = sustained ACCOUNT-WIDE volume over 3 months → judged account-wide
  (COALESCE(ta.term_clicks_90d, 0) >= 30) AS is_big,
  (LOWER(TRIM(u.search_term)) = LOWER(TRIM(u.target_text))) AS term_is_keyword,
  (u.orders_90d > 0 OR COALESCE(ta.term_orders_90d, 0) > 0) AS is_winner,
  (u.kind != 'PT'
   AND (u.kind = 'AUTO' OR LOWER(TRIM(u.search_term)) != LOWER(TRIM(u.target_text)))
   AND CASE WHEN COALESCE(ta.term_clicks_90d, 0) >= 30
            -- big word: 3 months, zero orders ANYWHERE account-wide; only flagged in slices with
            -- real presence here (>=3 clicks/90d) so one stray click doesn't spawn a negate row
            THEN COALESCE(ta.term_orders_90d, 0) = 0 AND u.clicks_90d >= 3
            ELSE u.clicks >= 10 AND u.orders = 0 END) AS is_negate    -- small word: 28 days at this slice are enough
FROM (SELECT * FROM st UNION ALL SELECT * FROM sb_st) u
LEFT JOIN term_all ta ON ta.term = LOWER(TRIM(u.search_term))
WHERE u.clicks_90d > 0;
