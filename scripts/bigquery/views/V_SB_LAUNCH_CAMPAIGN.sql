-- V_SB_LAUNCH_CAMPAIGN — CAMPAIGN-LEVEL measures + BUDGET suggestion for Sponsored-Brands launch campaigns.
--
-- WHY SB-native, not V_LAUNCH_PHASE1: the SP controller reads SP-only sources for SB (V_TARGET_DAILY budget →
-- NULL, FACT spend → undercounts: VIDEO- BALL $8.67 vs true $14.64, SP campaign_history has 0 SB rows → dark 0).
-- So SB runs the SAME launch-controller budget logic (identical `k` constants + CASE as V_LAUNCH_PHASE1) but on
-- SB-native signals: spend/ROAS from sb_campaign_report, budget + %dark from sb_campaign_history.
--
-- Measures (header): the campaign report is the only complete SB source (per-keyword sb_keyword_report died
-- 2025-12-29; FACT undercounts SB at every grain). r2 = anchor day (FN_ADS_ANCHOR_CAP), r3 = prior 2 days.
-- TOS is NULL — sb_campaign_report's top_of_search field is PLACEMENT MIX (~0.86), not the competitive
-- "Top-of-search IS" Amazon shows (<5%); the true per-keyword IS is only in the dead sb_keyword_report.
-- net ROAS is an ESTIMATE — the SB report has sales but no units/COGS, so gross profit ≈
-- sales × (1 − cost_per_unit/list_price) via the campaign's mapped ASIN. Spec: architecture/CAMPAIGN_LAUNCH_RAMP.md.
CREATE OR REPLACE VIEW `onyga-482313.OI.V_SB_LAUNCH_CAMPAIGN` AS
WITH cfg AS (
  SELECT MAX(IF(config_key='campaign_launch_floor_daily', config_value, NULL)) AS floor_daily
  FROM `onyga-482313.OI.DE_BUDGET_CONFIG`
),
-- Phase-1 constants — IDENTICAL to V_LAUNCH_PHASE1.k (so SB behaves like SP).
k AS (
  SELECT 0.10 AS dark_target, 0.60 AS spend_target, 1.5 AS strong_roas, 1.2 AS weak_roas, 0.9 AS cut_roas, 0.6 AS deep_roas,
         0.90 AS bud_trim, 0.60 AS bud_cut, 2.0 AS bud_cap_weak, 3.0 AS bud_cap_strong
),
wm AS (SELECT LEAST(MAX(report_date), `onyga-482313.OI.FN_ADS_ANCHOR_CAP`()) AS d
       FROM `fivetran-hl.amazon_ads.sb_campaign_report`),
-- SB campaigns inside the launch window (they already appear in V_LAUNCH_PHASE1's universe; keep the SB ones)
sb_new AS (
  SELECT DISTINCT lp.campaign_id, lp.campaign_name, ANY_VALUE(lp.day_of_ramp) day_of_ramp
  FROM `onyga-482313.OI.V_LAUNCH_PHASE1` lp
  JOIN (SELECT DISTINCT CAST(campaign_id AS STRING) cid FROM `onyga-482313.OI.FACT_AMAZON_ADS` WHERE campaign_type = 'SB') ct
    ON ct.cid = lp.campaign_id
  GROUP BY 1, 2
),
-- product cost ratio (cost_per_unit ÷ list price) for the net-ROAS estimate, via the campaign's mapped ASIN
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
-- current daily budget per SB campaign (latest row in sb_campaign_history)
bud AS (
  SELECT CAST(id AS STRING) cid, ARRAY_AGG(budget ORDER BY last_update_date DESC LIMIT 1)[OFFSET(0)] AS budget
  FROM `fivetran-hl.amazon_ads.sb_campaign_history` GROUP BY 1
),
-- %dark today from sb_campaign_history serving_status (Amazon's own out-of-budget verdict; same method as SP)
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
-- per-day campaign rows over the 3-day window (measures + est net ROAS signal)
r AS (
  SELECT CAST(rep.campaign_id AS STRING) cid, rep.report_date date,
    rep.impressions, rep.clicks, rep.cost, rep.attributed_sales_14_d sales, rep.top_of_search_impression_share tos
  FROM `fivetran-hl.amazon_ads.sb_campaign_report` rep
  WHERE rep.report_date BETWEEN DATE_SUB((SELECT d FROM wm), INTERVAL 2 DAY) AND (SELECT d FROM wm)
),
agg AS (
  SELECT cid,
    SUM(IF(date=(SELECT d FROM wm), impressions,0)) r2_impr, SUM(IF(date=(SELECT d FROM wm), clicks,0)) r2_clk,
    SUM(IF(date=(SELECT d FROM wm), cost,0)) r2_cost, SUM(IF(date=(SELECT d FROM wm), sales,0)) r2_sales,
    SUM(IF(date<(SELECT d FROM wm), impressions,0)) r3_impr, SUM(IF(date<(SELECT d FROM wm), clicks,0)) r3_clk,
    SUM(IF(date<(SELECT d FROM wm), cost,0)) r3_cost, SUM(IF(date<(SELECT d FROM wm), sales,0)) r3_sales
  FROM r GROUP BY 1
),
-- campaign net-ROAS signals (est), SP-style: roas_1d = last day; roas_prev2 = mean of the 2 prior days
-- (equal weight, <3-click days ignored, spend-pooled fallback); spend_today = last-day cost.
csig AS (
  SELECT r.cid,
    MAX(IF(r.date=(SELECT d FROM wm), SAFE_DIVIDE(r.sales*(1-COALESCE(pr.cost_ratio,0)), NULLIF(r.cost,0)), NULL)) AS c_roas1,
    COALESCE(
      AVG(IF(r.clicks>=3 AND r.date<(SELECT d FROM wm), SAFE_DIVIDE(r.sales*(1-COALESCE(pr.cost_ratio,0)), NULLIF(r.cost,0)), NULL)),
      SAFE_DIVIDE(SUM(IF(r.date<(SELECT d FROM wm), r.sales*(1-COALESCE(pr.cost_ratio,0)), 0)), NULLIF(SUM(IF(r.date<(SELECT d FROM wm), r.cost,0)),0))
    ) AS c_roas_prev2,
    SUM(IF(r.date=(SELECT d FROM wm), r.cost, 0)) AS spend_today
  FROM r LEFT JOIN prod pr ON pr.cid = r.cid GROUP BY 1
),
base AS (
  SELECT n.campaign_id, n.campaign_name, n.day_of_ramp,
    b.budget AS current_budget, COALESCE(d.pd,0) AS pd, cs.spend_today, cs.c_roas1, cs.c_roas_prev2,
    pr.cost_ratio, a.*  EXCEPT(cid),
    CAST(x2.floor_daily AS FLOAT64) AS floor_daily
  FROM sb_new n
  CROSS JOIN cfg x2
  LEFT JOIN agg a  ON a.cid = n.campaign_id
  LEFT JOIN bud b  ON b.cid = n.campaign_id
  LEFT JOIN dark d ON d.cid = n.campaign_id
  LEFT JOIN csig cs ON cs.cid = n.campaign_id
  LEFT JOIN prod pr ON pr.cid = n.campaign_id
)
SELECT
  b.campaign_id, b.campaign_name, b.day_of_ramp, b.current_budget, ROUND(b.pd*100) AS pct_dark,
  (SELECT d FROM wm) AS anchor_date, b.spend_today,
  ROUND(b.c_roas1,2) AS camp_roas_1d, ROUND(b.c_roas_prev2,2) AS camp_roas_prev2,
  -- row 2 (last day): spend · CPC · clicks · CTR · TOS(NULL) · units(NULL) · net ROAS(est) · ACoS
  ROUND(b.r2_cost,2) r2_spend, ROUND(SAFE_DIVIDE(b.r2_cost,NULLIF(b.r2_clk,0)),2) r2_cpc, b.r2_clk,
  ROUND(100*SAFE_DIVIDE(b.r2_clk,NULLIF(b.r2_impr,0)),2) r2_ctr, CAST(NULL AS INT64) r2_tos,
  ROUND(SAFE_DIVIDE(b.r2_sales*(1-COALESCE(b.cost_ratio,0)), NULLIF(b.r2_cost,0)),2) r2_roas,
  ROUND(100*SAFE_DIVIDE(b.r2_cost,NULLIF(b.r2_sales,0)),0) r2_acos, b.r2_impr,
  -- row 3 (prior 2 days)
  ROUND(b.r3_cost,2) r3_spend, ROUND(SAFE_DIVIDE(b.r3_cost,NULLIF(b.r3_clk,0)),2) r3_cpc, b.r3_clk,
  ROUND(100*SAFE_DIVIDE(b.r3_clk,NULLIF(b.r3_impr,0)),2) r3_ctr, CAST(NULL AS INT64) r3_tos,
  ROUND(SAFE_DIVIDE(b.r3_sales*(1-COALESCE(b.cost_ratio,0)), NULLIF(b.r3_cost,0)),2) r3_roas,
  ROUND(100*SAFE_DIVIDE(b.r3_cost,NULLIF(b.r3_sales,0)),0) r3_acos, b.r3_impr,
  -- BUDGET SUGGESTION — identical CASE to V_LAUNCH_PHASE1 (SB behaves like SP)
  CASE
    WHEN b.spend_today IS NULL OR b.current_budget IS NULL THEN b.current_budget
    WHEN b.pd > x.dark_target AND b.c_roas_prev2 > x.strong_roas THEN ROUND(LEAST(SAFE_DIVIDE(b.current_budget,1-b.pd), b.current_budget*x.bud_cap_strong),2)
    WHEN b.pd > x.dark_target AND b.c_roas1 > x.weak_roas  THEN ROUND(LEAST(SAFE_DIVIDE(b.current_budget,1-b.pd), b.current_budget*x.bud_cap_weak),2)
    WHEN b.pd > x.dark_target AND b.c_roas_prev2 < x.cut_roas THEN ROUND(GREATEST(b.current_budget*x.bud_cut, b.floor_daily),2)
    WHEN b.pd > x.dark_target THEN b.current_budget
    WHEN SAFE_DIVIDE(b.spend_today,b.current_budget) <= x.spend_target THEN b.current_budget
    WHEN b.c_roas_prev2 < x.deep_roas THEN ROUND(GREATEST(b.current_budget*x.bud_cut, b.floor_daily),2)
    WHEN b.c_roas_prev2 < x.cut_roas  THEN ROUND(GREATEST(b.current_budget*x.bud_trim, b.floor_daily),2)
    ELSE b.current_budget END AS suggested_budget,
  CASE
    WHEN b.spend_today IS NULL OR b.current_budget IS NULL THEN 'No budget/spend — hold'
    WHEN b.pd > x.dark_target AND b.c_roas_prev2 > x.strong_roas
      THEN CONCAT('Dark ', CAST(ROUND(b.pd*100) AS STRING), '% · prev-2d ', CAST(ROUND(b.c_roas_prev2,2) AS STRING), '× → raise (cap 3×)')
    WHEN b.pd > x.dark_target AND b.c_roas1 > x.weak_roas
      THEN CONCAT('Dark ', CAST(ROUND(b.pd*100) AS STRING), '% · today ', CAST(ROUND(b.c_roas1,2) AS STRING), '× → raise (cap 2×)')
    WHEN b.pd > x.dark_target AND b.c_roas_prev2 < x.cut_roas
      THEN CONCAT('Dark ', CAST(ROUND(b.pd*100) AS STRING), '% · prev-2d ', CAST(ROUND(b.c_roas_prev2,2) AS STRING), '× losing → cut budget 40% + brake bids')
    WHEN b.pd > x.dark_target
      THEN CONCAT('Dark ', CAST(ROUND(b.pd*100) AS STRING), '% · ROAS mid → hold budget, brake bids −', CAST(ROUND(100*0.30*b.pd) AS STRING), '%')
    WHEN SAFE_DIVIDE(b.spend_today,b.current_budget) <= x.spend_target
      THEN CONCAT('Spent ', CAST(ROUND(100*SAFE_DIVIDE(b.spend_today,b.current_budget)) AS STRING), '% of budget → hold')
    WHEN b.c_roas_prev2 < x.deep_roas
      THEN CONCAT('Prev-2d ', CAST(ROUND(b.c_roas_prev2,2) AS STRING), '× → cut 40% to floor')
    WHEN b.c_roas_prev2 < x.cut_roas
      THEN CONCAT('Prev-2d ', CAST(ROUND(b.c_roas_prev2,2) AS STRING), '× → trim 10%')
    ELSE 'Stable → hold'
  END AS budget_reason
FROM base b CROSS JOIN k x;
