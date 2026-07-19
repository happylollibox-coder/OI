-- V_SB_LAUNCH_TARGET — PER-TARGET measures + BID suggestion for Sponsored-Brands launch campaigns.
-- Covers BOTH keyword-targeted (VIDEO- BALL) and product-targeted (VIDEO- COMP/BALL) SB campaigns — one row
-- per target — so the SB drill mirrors SP's RunTarget (keywords + product/auto targets in one list).
--
-- SOURCES (all current):
--   keyword arm  — list+bid from sb_keyword; per-day clicks/spend/sales from sb_search_term_report (keyword_id).
--   product arm  — list+bid from sb_product_target; per-day + label from sb_target_report (target_id).
-- Runs the SAME launch-controller BID logic as V_LAUNCH_PHASE1 (identical `k` constants + CASE order), on
-- SB-native campaign signals (%dark + budget from sb_campaign_history, campaign net ROAS from sb_campaign_report).
--
-- ⚠️ NO per-target impressions/CTR in the drill. Keyword impressions only survive at search-term grain
-- (undercount); product impressions ARE true (sb_target_report is targeting grain) but the drill stays uniform
-- and shows clicks/spend/sales/net-ROAS only — the campaign header (V_SB_LAUNCH_CAMPAIGN) carries the true CTR.
-- net ROAS is the same ESTIMATE (sales × (1 − cost_ratio); SB reports no units). Spec: architecture/CAMPAIGN_LAUNCH_RAMP.md.
CREATE OR REPLACE VIEW `onyga-482313.OI.V_SB_LAUNCH_TARGET` AS
WITH k AS (
  SELECT 0.10 AS dark_target, 0.60 AS spend_target, 1.5 AS strong_roas, 1.2 AS weak_roas, 0.9 AS cut_roas,
         0.80 AS bid_cut, 1.30 AS bid_raise_strong, 1.15 AS bid_raise_weak, 1.10 AS bid_starve, 0.20 AS bid_min, 1.50 AS bid_max
),
wm AS (SELECT LEAST(MAX(report_date), `onyga-482313.OI.FN_ADS_ANCHOR_CAP`()) AS d
       FROM `fivetran-hl.amazon_ads.sb_search_term_report`),
sb_camp AS (
  SELECT DISTINCT lp.campaign_id
  FROM `onyga-482313.OI.V_LAUNCH_PHASE1` lp
  JOIN (SELECT DISTINCT CAST(campaign_id AS STRING) cid FROM `onyga-482313.OI.FACT_AMAZON_ADS` WHERE campaign_type = 'SB') ct
    ON ct.cid = lp.campaign_id
),
prod AS (
  SELECT CAST(f.campaign_id AS STRING) cid,
    SAFE_DIVIDE(ANY_VALUE(c.cost), NULLIF(ANY_VALUE(p.listing_price_amount), 0)) AS cost_ratio
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` f
  LEFT JOIN `onyga-482313.OI.DIM_PRODUCT` p ON p.asin = f.ASIN_BY_CAMPAIGN_NAME
  LEFT JOIN (SELECT asin, TOTAL_COST_PER_UNIT cost FROM (
      SELECT asin, TOTAL_COST_PER_UNIT, ROW_NUMBER() OVER (PARTITION BY marketplace_id, asin ORDER BY start_date DESC) rn
      FROM `onyga-482313.OI.DIM_COSTS_HISTORY` WHERE marketplace_id='ATVPDKIKX0DER' AND end_date IS NULL) WHERE rn=1) c
    ON c.asin = f.ASIN_BY_CAMPAIGN_NAME
  GROUP BY 1
),
-- ── campaign signals (SP-identical, SB-native) ──
bud AS (
  SELECT CAST(id AS STRING) cid, ARRAY_AGG(budget ORDER BY last_update_date DESC LIMIT 1)[OFFSET(0)] AS budget
  FROM `fivetran-hl.amazon_ads.sb_campaign_history` GROUP BY 1
),
h AS (
  SELECT CAST(id AS STRING) cid, DATETIME(last_update_date, 'America/Los_Angeles') ts, serving_status
  FROM `fivetran-hl.amazon_ads.sb_campaign_history`
  WHERE DATE(last_update_date, 'America/Los_Angeles') = (SELECT d FROM wm)
),
ev AS (
  SELECT cid, ts, serving_status FROM h
  UNION ALL SELECT DISTINCT cid, DATETIME((SELECT d FROM wm), TIME '00:00:00'), 'CAMPAIGN_STATUS_ENABLED' FROM h
),
sqd AS (SELECT cid, ts, serving_status, LEAD(ts) OVER (PARTITION BY cid ORDER BY ts) nxt FROM ev),
dark AS (
  SELECT cid, SUM(IF(serving_status='CAMPAIGN_OUT_OF_BUDGET',
    DATETIME_DIFF(COALESCE(nxt, DATETIME(DATE_ADD((SELECT d FROM wm), INTERVAL 1 DAY))), ts, MINUTE), 0)) / 1440.0 AS pd
  FROM sqd GROUP BY 1
),
cr AS (
  SELECT CAST(campaign_id AS STRING) cid, report_date date, clicks, cost, attributed_sales_14_d sales
  FROM `fivetran-hl.amazon_ads.sb_campaign_report`
  WHERE report_date BETWEEN DATE_SUB((SELECT d FROM wm), INTERVAL 2 DAY) AND (SELECT d FROM wm)
),
csig AS (
  SELECT cr.cid,
    MAX(IF(cr.date=(SELECT d FROM wm), SAFE_DIVIDE(cr.sales*(1-COALESCE(pr.cost_ratio,0)), NULLIF(cr.cost,0)), NULL)) AS c_roas1,
    COALESCE(
      AVG(IF(cr.clicks>=3 AND cr.date<(SELECT d FROM wm), SAFE_DIVIDE(cr.sales*(1-COALESCE(pr.cost_ratio,0)), NULLIF(cr.cost,0)), NULL)),
      SAFE_DIVIDE(SUM(IF(cr.date<(SELECT d FROM wm), cr.sales*(1-COALESCE(pr.cost_ratio,0)), 0)), NULLIF(SUM(IF(cr.date<(SELECT d FROM wm), cr.cost,0)),0))
    ) AS c_roas_prev2,
    SUM(IF(cr.date=(SELECT d FROM wm), cr.cost, 0)) AS spend_today
  FROM cr LEFT JOIN prod pr ON pr.cid = cr.cid GROUP BY 1
),
-- ── unified target list (keyword arm ∪ product arm) ──
pt_label AS (   -- product-target label/type from the (current) target report
  SELECT target_id, ANY_VALUE(targeting_text) txt, ANY_VALUE(targeting_type) typ
  FROM `fivetran-hl.amazon_ads.sb_target_report`
  WHERE report_date >= DATE_SUB((SELECT d FROM wm), INTERVAL 30 DAY)
  GROUP BY 1
),
tgt AS (
  SELECT k.id AS target_id, CAST(k.campaign_id AS STRING) cid, k.ad_group_id,
    k.keyword_text AS target_text, 'KEYWORD' AS target_type, k.match_type, k.bid
  FROM `fivetran-hl.amazon_ads.sb_keyword` k
  WHERE NOT k._fivetran_deleted AND k.state='enabled' AND CAST(k.campaign_id AS STRING) IN (SELECT campaign_id FROM sb_camp)
  UNION ALL
  SELECT pt.id, CAST(pt.campaign_id AS STRING), pt.ad_group_id,
    COALESCE(l.txt, 'product target') AS target_text, 'PRODUCT' AS target_type,
    COALESCE(l.typ, 'TARGETING_EXPRESSION') AS match_type, pt.bid
  FROM `fivetran-hl.amazon_ads.sb_product_target` pt
  LEFT JOIN pt_label l ON l.target_id = pt.id
  WHERE NOT pt._fivetran_deleted AND pt.state='enabled' AND CAST(pt.campaign_id AS STRING) IN (SELECT campaign_id FROM sb_camp)
),
-- ── unified per-day performance (keyword arm from search-term report ∪ product arm from target report) ──
tgtday AS (
  SELECT keyword_id AS target_id, report_date date, SUM(clicks) clk, SUM(cost) cost, SUM(attributed_sales_14_d) sales
  FROM `fivetran-hl.amazon_ads.sb_search_term_report`
  WHERE report_date BETWEEN DATE_SUB((SELECT d FROM wm), INTERVAL 2 DAY) AND (SELECT d FROM wm)
  GROUP BY 1, 2
  UNION ALL
  SELECT target_id, report_date, SUM(clicks), SUM(cost), SUM(attributed_sales_14_d)
  FROM `fivetran-hl.amazon_ads.sb_target_report`
  WHERE report_date BETWEEN DATE_SUB((SELECT d FROM wm), INTERVAL 2 DAY) AND (SELECT d FROM wm)
  GROUP BY 1, 2
),
tsig AS (
  SELECT tgt.target_id,
    SUM(IF(d.date=(SELECT d FROM wm), d.clk,0)) r2_clk, SUM(IF(d.date=(SELECT d FROM wm), d.cost,0)) r2_cost, SUM(IF(d.date=(SELECT d FROM wm), d.sales,0)) r2_sales,
    SUM(IF(d.date<(SELECT d FROM wm), d.clk,0)) r3_clk, SUM(IF(d.date<(SELECT d FROM wm), d.cost,0)) r3_cost, SUM(IF(d.date<(SELECT d FROM wm), d.sales,0)) r3_sales,
    SUM(d.clk) clk3,
    MAX(IF(d.date=(SELECT d FROM wm), SAFE_DIVIDE(d.sales*(1-COALESCE(pr.cost_ratio,0)), NULLIF(d.cost,0)), NULL)) AS k_roas1,
    COALESCE(
      AVG(IF(d.clk>=3 AND d.date<(SELECT d FROM wm), SAFE_DIVIDE(d.sales*(1-COALESCE(pr.cost_ratio,0)), NULLIF(d.cost,0)), NULL)),
      SAFE_DIVIDE(SUM(IF(d.date<(SELECT d FROM wm), d.sales*(1-COALESCE(pr.cost_ratio,0)), 0)), NULLIF(SUM(IF(d.date<(SELECT d FROM wm), d.cost,0)),0))
    ) AS k_roas_prev2
  FROM tgt LEFT JOIN tgtday d ON d.target_id = tgt.target_id
           LEFT JOIN prod pr  ON pr.cid = tgt.cid
  GROUP BY 1
),
base AS (
  SELECT tgt.cid AS campaign_id, tgt.target_id, tgt.ad_group_id, tgt.target_text, tgt.target_type, tgt.match_type, tgt.bid,
    COALESCE(s.r2_clk,0) r2_clk, COALESCE(s.r2_cost,0) r2_cost, COALESCE(s.r2_sales,0) r2_sales,
    COALESCE(s.r3_clk,0) r3_clk, COALESCE(s.r3_cost,0) r3_cost, COALESCE(s.r3_sales,0) r3_sales,
    COALESCE(s.clk3,0) clk3, s.k_roas1, s.k_roas_prev2, pr.cost_ratio,
    COALESCE(d.pd,0) pd, cs.spend_today, cb.budget, cs.c_roas1, cs.c_roas_prev2,
    (COALESCE(d.pd,0) <= x.dark_target AND SAFE_DIVIDE(cs.spend_today, cb.budget) <= x.spend_target) AS starving
  FROM tgt
  CROSS JOIN k x
  LEFT JOIN tsig s  ON s.target_id = tgt.target_id
  LEFT JOIN prod pr ON pr.cid = tgt.cid
  LEFT JOIN dark d  ON d.cid = tgt.cid
  LEFT JOIN csig cs ON cs.cid = tgt.cid
  LEFT JOIN bud cb  ON cb.cid = tgt.cid
)
SELECT
  b.campaign_id, b.target_id, b.ad_group_id, b.target_text, b.target_type, b.match_type, b.bid,
  b.r2_clk, ROUND(b.r2_cost,2) r2_spend, ROUND(SAFE_DIVIDE(b.r2_cost,NULLIF(b.r2_clk,0)),2) r2_cpc, ROUND(b.r2_sales,2) r2_sales,
  ROUND(SAFE_DIVIDE(b.r2_sales*(1-COALESCE(b.cost_ratio,0)), NULLIF(b.r2_cost,0)),2) r2_roas,
  b.r3_clk, ROUND(b.r3_cost,2) r3_spend, ROUND(SAFE_DIVIDE(b.r3_cost,NULLIF(b.r3_clk,0)),2) r3_cpc, ROUND(b.r3_sales,2) r3_sales,
  ROUND(SAFE_DIVIDE(b.r3_sales*(1-COALESCE(b.cost_ratio,0)), NULLIF(b.r3_cost,0)),2) r3_roas,
  -- BID SUGGESTION — identical CASE + order to V_LAUNCH_PHASE1
  CASE
    WHEN b.bid IS NULL THEN NULL
    WHEN b.starving THEN ROUND(LEAST(b.bid*x.bid_starve, x.bid_max),2)
    WHEN b.clk3 < 4 THEN ROUND(LEAST(b.bid*x.bid_raise_weak, x.bid_max),2)
    WHEN b.k_roas_prev2 < x.cut_roas AND b.k_roas1 < x.cut_roas THEN ROUND(GREATEST(b.bid*x.bid_cut, x.bid_min),2)
    WHEN b.pd > x.dark_target AND b.c_roas_prev2 <= x.strong_roas AND b.c_roas1 <= x.weak_roas
         AND (b.k_roas1 >= 1.0 OR b.k_roas_prev2 >= 1.0) THEN b.bid
    WHEN b.pd > x.dark_target AND b.c_roas_prev2 <= x.strong_roas AND b.c_roas1 <= x.weak_roas
      THEN ROUND(GREATEST(b.bid*(1 - 0.30*b.pd), x.bid_min),2)
    WHEN b.k_roas_prev2 > x.strong_roas AND b.k_roas1 > x.strong_roas THEN ROUND(LEAST(b.bid*x.bid_raise_strong, x.bid_max),2)
    WHEN b.k_roas1 > x.weak_roas THEN ROUND(LEAST(b.bid*x.bid_raise_weak, x.bid_max),2)
    ELSE b.bid END AS suggested_bid,
  CASE
    WHEN b.bid IS NULL THEN 'NO_BID'
    WHEN b.starving THEN 'STARVE'
    WHEN b.clk3 < 4 THEN 'PROBE'
    WHEN b.k_roas_prev2 < x.cut_roas AND b.k_roas1 < x.cut_roas THEN 'CUT'
    WHEN b.pd > x.dark_target AND b.c_roas_prev2 <= x.strong_roas AND b.c_roas1 <= x.weak_roas
         AND (b.k_roas1 >= 1.0 OR b.k_roas_prev2 >= 1.0) THEN 'HOLD'
    WHEN b.pd > x.dark_target AND b.c_roas_prev2 <= x.strong_roas AND b.c_roas1 <= x.weak_roas THEN 'BRAKE'
    WHEN b.k_roas_prev2 > x.strong_roas AND b.k_roas1 > x.strong_roas THEN 'RAISE_STRONG'
    WHEN b.k_roas1 > x.weak_roas THEN 'RAISE_WEAK'
    ELSE 'HOLD' END AS bid_action
FROM base b CROSS JOIN k x;
