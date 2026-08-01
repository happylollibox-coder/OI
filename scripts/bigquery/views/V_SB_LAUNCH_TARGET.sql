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
         0.80 AS bid_cut, 1.30 AS bid_raise_strong, 1.15 AS bid_raise_weak, 1.10 AS bid_starve, 1.05 AS bid_probe, 0.20 AS bid_min, 1.50 AS bid_max, 2.00 AS bid_hard_cap,
         -- money-bleeder ladder (0 conversions, scaled by clicks) — same as V_LAUNCH_PHASE1
         4 AS bleed_watch_clk, 8 AS bleed_trim_clk, 15 AS bleed_cut_clk, 0.80 AS bid_bleed_trim, 0.60 AS bid_bleed_cut,
         -- LAUNCH CLICK GOAL (Ori 2026-07-24/25): judged on the LAST COMPLETE DAY's clicks (r2_clk), mirroring
         -- V_LAUNCH_PHASE1's t_clk1 — "4 clicks a day" = the most recent full day, not a multi-day average.
         --   r2_clk < 4 → PROBE (+5%) · r2_clk >= 6 → SLOW (−5%, 6+ clicks yesterday, no sale) · 4–5 → HOLD.
         4 AS click_goal_day, 6 AS click_cap_day, 0.95 AS bid_slow,
         -- budget-constrained probing (Ori 2026-07-30): in a capped campaign park the tested,
         -- trim the >$1 eaters, never probe up (under-clicking is the budget dying, not the bid)
         15 AS tested_clk, 0.25 AS bid_park, 1.00 AS big_bid, 0.85 AS bid_big_trim
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
-- Budget + status events via the unified V_SRC interface, campaign_type='SB' (prefer the consolidated
-- layer over raw fivetran; NOT DIM_CAMPAIGN for events — its SCD2 samples 3×/day and drops reverting
-- flips. 2026-07-30, architecture/CAMPAIGN_LAUNCH_RAMP.md §"Status source").
bud AS (
  SELECT campaign_id cid, ARRAY_AGG(budget ORDER BY date DESC LIMIT 1)[OFFSET(0)] AS budget
  FROM `onyga-482313.OI.V_SRC_AmazonAds_campaign_history` WHERE campaign_type='SB' GROUP BY 1
),
h AS (
  SELECT campaign_id cid, DATETIME(date, 'America/Los_Angeles') ts, serving_status
  FROM `onyga-482313.OI.V_SRC_AmazonAds_campaign_history`
  WHERE campaign_type='SB' AND DATE(date, 'America/Los_Angeles') = (SELECT d FROM wm)
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
  -- SB reports ORDERS (attributed_conversions_14_d), not a unit count — surfaced so the per-target drill shows
  -- "N orders" driving the net-ROAS estimate instead of a blank units column (Ori 2026-07-25).
  SELECT keyword_id AS target_id, report_date date, SUM(clicks) clk, SUM(cost) cost, SUM(attributed_sales_14_d) sales, SUM(attributed_conversions_14_d) orders
  FROM `fivetran-hl.amazon_ads.sb_search_term_report`
  WHERE report_date BETWEEN DATE_SUB((SELECT d FROM wm), INTERVAL 2 DAY) AND (SELECT d FROM wm)
  GROUP BY 1, 2
  UNION ALL
  SELECT target_id, report_date, SUM(clicks), SUM(cost), SUM(attributed_sales_14_d), SUM(attributed_conversions_14_d)
  FROM `fivetran-hl.amazon_ads.sb_target_report`
  WHERE report_date BETWEEN DATE_SUB((SELECT d FROM wm), INTERVAL 2 DAY) AND (SELECT d FROM wm)
  GROUP BY 1, 2
),
tsig AS (
  SELECT tgt.target_id,
    SUM(IF(d.date=(SELECT d FROM wm), d.clk,0)) r2_clk, SUM(IF(d.date=(SELECT d FROM wm), d.cost,0)) r2_cost, SUM(IF(d.date=(SELECT d FROM wm), d.sales,0)) r2_sales, SUM(IF(d.date=(SELECT d FROM wm), d.orders,0)) r2_orders,
    SUM(IF(d.date<(SELECT d FROM wm), d.clk,0)) r3_clk, SUM(IF(d.date<(SELECT d FROM wm), d.cost,0)) r3_cost, SUM(IF(d.date<(SELECT d FROM wm), d.sales,0)) r3_sales, SUM(IF(d.date<(SELECT d FROM wm), d.orders,0)) r3_orders,
    SUM(d.clk) clk3, COALESCE(SUM(d.sales),0) sales3,
    -- active click-days = denominator for the real clicks/day rate (a burst on one day must not read as
    -- clk3/3; mirrors V_LAUNCH_PHASE1, Ori 2026-07-25).
    COUNT(DISTINCT IF(d.clk > 0, d.date, NULL)) AS active_days,
    MAX(IF(d.date=(SELECT d FROM wm), SAFE_DIVIDE(d.sales*(1-COALESCE(pr.cost_ratio,0)), NULLIF(d.cost,0)), NULL)) AS k_roas1,
    COALESCE(
      AVG(IF(d.clk>=3 AND d.date<(SELECT d FROM wm), SAFE_DIVIDE(d.sales*(1-COALESCE(pr.cost_ratio,0)), NULLIF(d.cost,0)), NULL)),
      SAFE_DIVIDE(SUM(IF(d.date<(SELECT d FROM wm), d.sales*(1-COALESCE(pr.cost_ratio,0)), 0)), NULLIF(SUM(IF(d.date<(SELECT d FROM wm), d.cost,0)),0))
    ) AS k_roas_prev2
  FROM tgt LEFT JOIN tgtday d ON d.target_id = tgt.target_id
           LEFT JOIN prod pr  ON pr.cid = tgt.cid
  GROUP BY 1
),
t90 AS (
  SELECT target_id, SUM(clk) clk90, SUM(conv) ord90 FROM (
    SELECT keyword_id AS target_id, SUM(clicks) clk, SUM(attributed_conversions_14_d) conv FROM `fivetran-hl.amazon_ads.sb_search_term_report`
    WHERE report_date BETWEEN DATE_SUB((SELECT d FROM wm), INTERVAL 89 DAY) AND (SELECT d FROM wm) GROUP BY 1
    UNION ALL
    SELECT target_id, SUM(clicks), SUM(attributed_conversions_14_d) FROM `fivetran-hl.amazon_ads.sb_target_report`
    WHERE report_date BETWEEN DATE_SUB((SELECT d FROM wm), INTERVAL 89 DAY) AND (SELECT d FROM wm) GROUP BY 1
  ) GROUP BY 1
),
base AS (
  SELECT tgt.cid AS campaign_id, tgt.target_id, tgt.ad_group_id, tgt.target_text, tgt.target_type, tgt.match_type, tgt.bid,
    COALESCE(s.r2_clk,0) r2_clk, COALESCE(s.r2_cost,0) r2_cost, COALESCE(s.r2_sales,0) r2_sales, COALESCE(s.r2_orders,0) r2_orders,
    COALESCE(s.r3_clk,0) r3_clk, COALESCE(s.r3_cost,0) r3_cost, COALESCE(s.r3_sales,0) r3_sales, COALESCE(s.r3_orders,0) r3_orders,
    COALESCE(s.clk3,0) clk3, ROUND(SAFE_DIVIDE(s.clk3, NULLIF(s.active_days,0)),2) AS clk_rate, COALESCE(s.sales3,0) sales3, COALESCE(t9.clk90,0) AS clk90, COALESCE(t9.ord90,0) AS ord90, s.k_roas1, s.k_roas_prev2, pr.cost_ratio,
    COALESCE(d.pd,0) pd, cs.spend_today, cb.budget, cs.c_roas1, cs.c_roas_prev2,
    (COALESCE(d.pd,0) <= x.dark_target AND SAFE_DIVIDE(cs.spend_today, cb.budget) <= x.spend_target) AS starving
  FROM tgt
  CROSS JOIN k x
  LEFT JOIN tsig s  ON s.target_id = tgt.target_id
  LEFT JOIN t90 t9  ON t9.target_id = tgt.target_id
  LEFT JOIN prod pr ON pr.cid = tgt.cid
  LEFT JOIN dark d  ON d.cid = tgt.cid
  LEFT JOIN csig cs ON cs.cid = tgt.cid
  LEFT JOIN bud cb  ON cb.cid = tgt.cid
),
-- 1-day launch cooldown: hold an SB target's suggestion for a day after we upload a change (one per day).
last_change AS (
  SELECT CAST(keyword_id AS STRING) AS target_id,
    DATE_DIFF(CURRENT_DATE('America/Los_Angeles'), MAX(DATE(applied_at, 'America/Los_Angeles')), DAY) AS days_since_suggestion
  FROM `onyga-482313.OI.FACT_PPC_CHANGE_LOG`
  WHERE keyword_id IS NOT NULL AND CAST(keyword_id AS STRING) != ''
  GROUP BY 1
),
baseN AS (
  SELECT b.*, ROUND(GREATEST(SAFE_DIVIDE(b.budget, COUNT(*) OVER (PARTITION BY b.campaign_id) * 4), 0.20), 2) AS aff_cpc,
    SAFE_DIVIDE(
      SUM(IF(COALESCE(b.k_roas1,0) >= 1.0 OR COALESCE(b.k_roas_prev2,0) >= 1.0, b.r2_cost + b.r3_cost, 0)) OVER (PARTITION BY b.campaign_id),
      NULLIF(SUM(b.r2_cost + b.r3_cost) OVER (PARTITION BY b.campaign_id), 0)) AS conv_share
  FROM base b
)
SELECT
  b.campaign_id, b.target_id, b.ad_group_id, b.target_text, b.target_type, b.match_type, b.bid,
  b.r2_clk, ROUND(b.r2_cost,2) r2_spend, ROUND(SAFE_DIVIDE(b.r2_cost,NULLIF(b.r2_clk,0)),2) r2_cpc, ROUND(b.r2_sales,2) r2_sales, CAST(b.r2_orders AS INT64) r2_orders,
  ROUND(SAFE_DIVIDE(b.r2_sales*(1-COALESCE(b.cost_ratio,0)), NULLIF(b.r2_cost,0)),2) r2_roas,
  b.r3_clk, ROUND(b.r3_cost,2) r3_spend, ROUND(SAFE_DIVIDE(b.r3_cost,NULLIF(b.r3_clk,0)),2) r3_cpc, ROUND(b.r3_sales,2) r3_sales, CAST(b.r3_orders AS INT64) r3_orders,
  ROUND(SAFE_DIVIDE(b.r3_sales*(1-COALESCE(b.cost_ratio,0)), NULLIF(b.r3_cost,0)),2) r3_roas,
  -- BID SUGGESTION — identical launch-window model to V_LAUNCH_PHASE1 (Ori 2026-07-21; click-rate control
  -- 2026-07-24). Two regimes split by whether the TARGET converts:
  --   NOT CONVERTING (net ROAS < 1 both windows) → click-rate control toward 4–6 clicks/day:
  --     <4/day → +5% · >6/day → −5% · 4–6/day → HOLD and wait for a sale.
  --     %DARK IS IGNORED here (Ori: "this keyword is not the cause for it being dark") — darkness is a BUDGET
  --     problem. The >6/day targets ARE the cause of capping, and they are exactly what this lowers.
  --   CONVERTING (net ROAS >= 1 either window) → pre-existing logic: hold while capping, else RAISE.
  -- Bleed is stopped by negating non-converting SEARCH TERMS (>=15 clk/0 orders), never by a loss-driven cut.
  CASE
    WHEN COALESCE(lc.days_since_suggestion, 99) < 1 THEN NULL   -- 1-day cooldown: changed today → suppress
    WHEN b.bid IS NULL THEN NULL
    -- NOT CONVERTING → click-rate control only (no %dark term in this branch)
    WHEN NOT (COALESCE(b.k_roas1,0) >= 1.0 OR COALESCE(b.k_roas_prev2,0) >= 1.0) THEN
      CASE
        -- capped campaign: budget-constrained probing (Ori 2026-07-30)
        WHEN b.pd > x.dark_target THEN CASE
          WHEN b.clk90 >= x.tested_clk AND b.ord90 = 0 AND b.bid > x.bid_park + 0.05 THEN x.bid_park
          -- TRIM needs real evidence (4+ clicks yesterday, Ori 2026-08-01); step max(15%, 30% x dark)
          WHEN b.bid > COALESCE(b.aff_cpc, x.big_bid) + 0.05 AND COALESCE(b.r2_clk,0) >= x.click_goal_day
            THEN ROUND(GREATEST(b.bid * LEAST(x.bid_big_trim, 1 - 0.30 * b.pd), COALESCE(b.aff_cpc, x.bid_min)),2)
          -- DARK_BRAKE: campaign-wide, dark-proportional step max(5%, 30% x dark), daily, floor $0.20
          WHEN COALESCE(b.clk3,0) > 0 AND b.bid > x.bid_min + 0.05
            THEN ROUND(GREATEST(b.bid * LEAST(x.bid_slow, 1 - 0.30 * b.pd), x.bid_min),2)
          ELSE b.bid
        END
        WHEN COALESCE(b.r2_clk,0) <  x.click_goal_day THEN ROUND(LEAST(b.bid*x.bid_probe, x.bid_max),2)
        WHEN COALESCE(b.r2_clk,0) >= x.click_cap_day  THEN ROUND(GREATEST(b.bid*x.bid_slow, x.bid_min),2)
        ELSE b.bid   -- inside the 4–6 clicks/day band: hold and wait for a sale
      END
    -- CONVERTING + campaign capping → NEVER raise (Ori 2026-07-30): fit down to realized 3d CPC
    WHEN b.pd > x.dark_target THEN CASE
      WHEN COALESCE(b.conv_share,0) >= 0.80 THEN
        IF(COALESCE(b.r2_clk,0) > 6 AND b.bid > COALESCE(SAFE_DIVIDE(b.r2_cost + b.r3_cost, NULLIF(b.clk3,0)), b.bid) + 0.05,
           ROUND(GREATEST(b.bid * 0.95, SAFE_DIVIDE(b.r2_cost + b.r3_cost, NULLIF(b.clk3,0))), 2), b.bid)
      WHEN COALESCE(b.r2_clk,0) >= x.click_goal_day
        AND SAFE_DIVIDE(b.r2_cost + b.r3_cost, NULLIF(b.clk3,0)) IS NOT NULL
        AND b.bid > SAFE_DIVIDE(b.r2_cost + b.r3_cost, NULLIF(b.clk3,0)) + 0.05
        THEN ROUND(GREATEST(b.bid * x.bid_big_trim, SAFE_DIVIDE(b.r2_cost + b.r3_cost, NULLIF(b.clk3,0))), 2)
      ELSE b.bid END
    -- WINNERS (converting): fund them toward the $2 HARD CAP, not the $1.50 launch cap — a proven
    -- converter has earned the right to bid up past the unproven-target ceiling (Ori 2026-07-24).
    WHEN b.k_roas_prev2 > x.strong_roas AND b.k_roas1 > x.strong_roas THEN ROUND(LEAST(b.bid*x.bid_raise_strong, x.bid_hard_cap),2)
    WHEN b.k_roas1 > x.weak_roas THEN ROUND(LEAST(b.bid*x.bid_raise_weak, x.bid_hard_cap),2)
    -- everything else (>=4 clicks, not selling): HOLD — bid not cut; bad search terms get negated instead
    ELSE b.bid END AS suggested_bid,
  CASE
    WHEN COALESCE(lc.days_since_suggestion, 99) < 1 THEN 'HOLD'   -- 1-day cooldown: changed today → held
    WHEN b.bid IS NULL THEN 'NO_BID'
    WHEN NOT (COALESCE(b.k_roas1,0) >= 1.0 OR COALESCE(b.k_roas_prev2,0) >= 1.0) THEN
      CASE
        WHEN b.pd > x.dark_target THEN CASE
          WHEN b.clk90 >= x.tested_clk AND b.ord90 = 0 AND b.bid > x.bid_park + 0.05 THEN 'PARK'
          WHEN b.bid > COALESCE(b.aff_cpc, x.big_bid) + 0.05 AND COALESCE(b.r2_clk,0) >= x.click_goal_day THEN 'TRIM_BID'
          WHEN COALESCE(b.clk3,0) > 0 AND b.bid > x.bid_min + 0.05 THEN 'DARK_BRAKE'
          ELSE 'HOLD'
        END
        WHEN COALESCE(b.r2_clk,0) <  x.click_goal_day THEN 'PROBE'
        WHEN COALESCE(b.r2_clk,0) >= x.click_cap_day  THEN 'SLOW'
        ELSE 'HOLD'
      END
    WHEN b.pd > x.dark_target THEN CASE
      WHEN COALESCE(b.conv_share,0) >= 0.80 THEN
        IF(COALESCE(b.r2_clk,0) > 6 AND b.bid > COALESCE(SAFE_DIVIDE(b.r2_cost + b.r3_cost, NULLIF(b.clk3,0)), b.bid) + 0.05, 'EASE', 'HOLD')
      WHEN COALESCE(b.r2_clk,0) >= x.click_goal_day AND b.bid > COALESCE(SAFE_DIVIDE(b.r2_cost + b.r3_cost, NULLIF(b.clk3,0)), b.bid) + 0.05 THEN 'FIT_CPC'
      ELSE 'HOLD' END
    WHEN b.k_roas_prev2 > x.strong_roas AND b.k_roas1 > x.strong_roas THEN 'RAISE_STRONG'
    WHEN b.k_roas1 > x.weak_roas THEN 'RAISE_WEAK'
    ELSE 'HOLD' END AS bid_action,
  -- 1-day cooldown reason (mirrors V_RUN_TARGET) so the SB card can show WHY a held target has no suggestion
  IF(COALESCE(lc.days_since_suggestion, 99) < 1, 'changed today — held (one launch suggestion per day)', NULL) AS bid_reason,
  lc.days_since_suggestion AS days_since_suggestion   -- drives the "Already applied" filter (applied = <1d, changed today)
FROM baseN b CROSS JOIN k x
LEFT JOIN last_change lc ON lc.target_id = b.target_id;
