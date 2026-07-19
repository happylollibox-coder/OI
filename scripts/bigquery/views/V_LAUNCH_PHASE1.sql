-- V_LAUNCH_PHASE1 — the launch controller for a campaign's first `launch_ramp_days` (20) days.
-- Spec: architecture/CAMPAIGN_LAUNCH_RAMP.md §"Phase 1 — stabilize to profitable".
-- Supersedes the bid/budget ladder that lived in V_CAMPAIGN_LAUNCH_RAMP. Purpose: get a new campaign
-- STABLE (spends its budget across the day, not by lunchtime) and PROFITABLE by day 20, then hand off
-- to the normal coacher. It does NOT negate inside 20 days — a keyword with no sale yet idles cheaply
-- and either converts or is negated by phase 2 on day 21.
--
-- GRAIN: one row per (campaign, target). Budget fields are campaign-level, repeated on every target row
-- (ANY_VALUE-safe: identical across a campaign's rows). Bid fields are target-level.
--
-- SIGNALS (all net ROAS = CORRECTED gross profit / Ads_cost; 1.0 = breakeven). "Corrected" = COGS charged to
-- the product ACTUALLY purchased, identified by sale price via T_PRICE_COST_TIER, not the advertised one — so
-- the decision runs on the same net ROAS ✓ the card shows (advertised-vs-purchased COGS bug; [[project_ads_cogs_price_imputation]]):
--   roas_1d   today's net ROAS (reactive)
--   eq3       equal-weight mean of the last 3 daily net ROAS, ignoring days < 3 clicks (smoothed).
--             Equal weight, NOT spend-pooled, so one bad day counts at full weight — "strong" means
--             CONSISTENTLY good, not "one big day dominated the pool". The <3-click guard stops a
--             1-click fluke day from swinging the mean; the pooled fallback below rescues a keyword
--             whose only qualifying evidence is one low-volume conversion day.
--   pd        %dark: fraction of the day Amazon reported CAMPAIGN_OUT_OF_BUDGET (America/Los_Angeles).
--             The GATE for budget: are we even hitting the cap? No cap hit → no unmet demand → a budget
--             raise is a no-op. Source: campaign_history.serving_status (see V_CAMPAIGN_LAUNCH_RAMP).
--   spend/budget, %active = 1 - pd
--
-- BID (per target, clamp $0.20-$1.50). Order matters — first match wins:
--   starving (pd<=10% AND campaign spend<=60% budget)  → ×1.10   buy traffic even if losing
--   PROBE: clk3 < 4 (too few clicks to judge)          → ×1.15   raise to buy traffic EVEN IF dark — a
--                                                                  starved keyword can't be judged/braked;
--                                                                  under a capped budget this just reallocates
--                                                                  spend to the unproven keyword. Overrides
--                                                                  cut/brake/hold below.
--   CUT only if prev2<0.9 AND roas_1d<0.9              → ×0.80   BOTH must be bad. Either signal OK
--                                                                  spares it: a proven keyword (high prev2)
--                                                                  on one dead day, or a recovering one
--                                                                  (fine today) — neither is cut.
--   DARK BRAKE: campaign dark>10% AND not funded        → ×(1−0.30·%dark)  A campaign capping out that isn't
--     (c_prev2<=1.5 AND c_roas_1d<=1.2)                            good enough for a budget raise must instead
--                                                                  LOWER bids to stop the cap-out — you can't
--                                                                  leave it as-is. SUPPRESSES the raises below
--                                                                  (raising while capping makes dark worse).
--     EXCEPT a profitable target (t_roas1>=1.0 OR         → HOLD   don't cut a good spot while capping — that
--     t_prev2>=1.0)                                                just starves your best target; hold it.
--   strong: prev2 > 1.5 AND roas_1d > 1.5              → ×1.30   BOTH windows profitable (symmetric with
--                                                                  CUT). Won't fund a +30% raise into a
--                                                                  dead last day, even if 2-3d ago was hot.
--   weak:   roas_1d > 1.2                               → ×1.15   reactive nudge on a good last day
--   else hold
--
-- INVARIANT (Ori): dark>10% ⟹ either budget raised (winners) or bids braked (mid/losers) — never "stay as is".
--
-- BUDGET (per campaign):
--   GATE pd<=10% (not maxing → no unmet demand; bids do the work):
--     spend<=60% budget                                → hold    starving, handled by bid ×1.10
--     eq3 < 0.6                                         → GREATEST(budget×0.6, floor)  cut losses
--     eq3 < 0.9                                         → GREATEST(budget×0.9, floor)  trim
--     else hold
--   GATE pd>10% (maxing → real unmet demand). Split by ROAS tier so a capping LOSER isn't funded:
--     prev2 > 1.5  → LEAST(budget/%active, budget×3)    strong: fund to full-day demand, cap 3×
--     roas_1d > 1.2→ LEAST(budget/%active, budget×2)    weak: same, cap 2×
--     prev2 < 0.9  → GREATEST(budget×0.6, floor)        LOSING while capping → cut budget 40% (+ bids brake)
--     else hold                                         genuinely mid (0.9–1.5) → hold budget, bids brake
--
-- WHY A VIEW, NOT A JOB: every signal reads observed history, so the controller replays on each read
-- and is always current. No scheduled SP, no state table. Ori uploads the bulksheet when he sits down.
CREATE OR REPLACE VIEW `onyga-482313.OI.V_LAUNCH_PHASE1` AS
WITH cfg AS (
  SELECT
    MAX(IF(config_key='launch_ramp_days',           config_value, NULL)) AS ramp_days,
    MAX(IF(config_key='campaign_launch_floor_daily', config_value, NULL)) AS floor_daily,
    MAX(IF(config_key='launch_raise_roas',           config_value, NULL)) AS raise_roas,   -- 1.5 strong bar
    MAX(IF(config_key='launch_raise_roas_days',      config_value, NULL)) AS roas_days      -- 3
  FROM `onyga-482313.OI.DE_BUDGET_CONFIG`
),
-- Phase-1 constants. TODO: migrate to DE_BUDGET_CONFIG (launch_dark_target, launch_spend_target,
-- launch_weak_roas, launch_bid_cut/raise_strong/raise_weak/starve, launch_bid_min/max, launch_bud_*).
k AS (
  SELECT 0.10 AS dark_target, 0.60 AS spend_target, 1.5 AS strong_roas, 1.2 AS weak_roas, 0.9 AS cut_roas, 0.6 AS deep_roas,
         0.80 AS bid_cut, 1.30 AS bid_raise_strong, 1.15 AS bid_raise_weak, 1.10 AS bid_starve,
         0.20 AS bid_min, 1.50 AS bid_max, 0.90 AS bud_trim, 0.60 AS bud_cut, 2.0 AS bud_cap_weak, 3.0 AS bud_cap_strong
),
-- Anchor "today" on the last complete LA day, never the current (incomplete) one — at 09:00 the current LA
-- day has ~10% of its spend and every signal would read as a false zero. FN_ADS_ANCHOR_CAP() = yesterday
-- normally, but the current LA day once it's within its last 2h (sales effectively done), so a user ahead of
-- LA sees today's date late in the LA evening instead of waiting for LA midnight.
wm AS (SELECT LEAST(MAX(date), `onyga-482313.OI.FN_ADS_ANCHOR_CAP`()) AS d
       FROM `onyga-482313.OI.FACT_AMAZON_ADS`),
-- Enabled campaigns inside the 20-day window (same gate as V_CAMPAIGN_LAUNCH_RAMP)
camp AS (
  SELECT campaign_id, created, campaign_name FROM (
    SELECT CAST(campaign_id AS STRING) AS campaign_id, MIN(DATE(creation_date)) AS created,
      ARRAY_AGG(state ORDER BY date DESC LIMIT 1)[OFFSET(0)] AS state,
      ARRAY_AGG(campaign_name ORDER BY date DESC LIMIT 1)[OFFSET(0)] AS campaign_name
    FROM `onyga-482313.OI.V_SRC_AmazonAds_campaign_history` GROUP BY 1
  )
  WHERE state = 'ENABLED'
    AND DATE_DIFF((SELECT d FROM wm), created, DAY) < (SELECT CAST(ramp_days AS INT64) FROM cfg)
),
-- %dark today, per LA day (Amazon's own out-of-budget verdict)
h AS (
  SELECT CAST(id AS STRING) cid, DATETIME(last_updated_date, 'America/Los_Angeles') ts, serving_status
  FROM `fivetran-hl.amazon_ads.campaign_history`
  WHERE DATE(last_updated_date, 'America/Los_Angeles') = (SELECT d FROM wm)
),
ev AS (
  SELECT cid, ts, serving_status FROM h
  UNION ALL SELECT DISTINCT cid, DATETIME((SELECT d FROM wm), TIME '00:00:00'), 'ENABLED' FROM h
),
sq AS (SELECT cid, ts, serving_status, LEAD(ts) OVER (PARTITION BY cid ORDER BY ts) nxt FROM ev),
dark AS (
  SELECT cid, SUM(IF(serving_status='CAMPAIGN_OUT_OF_BUDGET',
    DATETIME_DIFF(COALESCE(nxt, DATETIME(DATE_ADD((SELECT d FROM wm), INTERVAL 1 DAY))), ts, MINUTE), 0)) / 1440.0 AS pd
  FROM sq GROUP BY 1
),
-- campaign-day perf over the trailing window. ROAS uses CORRECTED gross profit — COGS charged to the
-- product actually PURCHASED (price-tier), not the advertised one — so the decision matches the card's net ROAS ✓.
cday AS (
  SELECT CAST(a.campaign_id AS STRING) cid, a.date, SUM(a.Ads_clicks) clk,
    SAFE_DIVIDE(SUM(a.Ads_sales - COALESCE(pct.tier_cost, a.TOTAL_COST_PER_UNIT)*a.Ads_units), SUM(a.Ads_cost)) roas,
    SUM(a.Ads_cost) sp
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` a
  LEFT JOIN `onyga-482313.OI.T_PRICE_COST_TIER` pct
    ON a.Ads_units > 0 AND pct.unit_price = ROUND(SAFE_DIVIDE(a.Ads_sales, a.Ads_units), 2)
  WHERE a.date BETWEEN DATE_SUB((SELECT d FROM wm), INTERVAL (SELECT CAST(roas_days AS INT64)-1 FROM cfg) DAY) AND (SELECT d FROM wm)
  GROUP BY 1, 2
),
camp_sig AS (
  SELECT cid,
    ROUND(AVG(IF(clk >= 3, roas, NULL)), 4) AS eq3,
    ROUND(MAX(IF(date = (SELECT d FROM wm), roas, NULL)), 4) AS roas_1d,   -- row 2: last complete day
    -- row 3 / STRONG signal: equal-weight mean of the TWO days before the last (2 & 3 days ago),
    -- non-overlapping with roas_1d. Ignores <3-click days; falls back to the spend-pooled ratio when no
    -- day qualifies (e.g. a 2-day-old campaign with one thin prior day).
    ROUND(COALESCE(
      AVG(IF(clk >= 3 AND date < (SELECT d FROM wm), roas, NULL)),
      SAFE_DIVIDE(SUM(IF(date < (SELECT d FROM wm), roas*sp, 0)), NULLIF(SUM(IF(date < (SELECT d FROM wm), sp, 0)), 0))
    ), 4) AS roas_prev2,
    ROUND(SUM(IF(date = (SELECT d FROM wm), sp, 0)), 2) AS spend_today
  FROM cday GROUP BY 1
),
cbud AS (SELECT campaign_id cid, MAX(campaign_budget) budget FROM `onyga-482313.OI.V_TARGET_DAILY` WHERE date=(SELECT d FROM wm) GROUP BY 1),
-- target-day perf + target signals. ROAS/gp use CORRECTED gross profit (COGS by product actually purchased).
tday AS (
  SELECT CAST(a.campaign_id AS STRING) cid, a.targeting, a.date, SUM(a.Ads_clicks) clk,
    SAFE_DIVIDE(SUM(a.Ads_sales - COALESCE(pct.tier_cost, a.TOTAL_COST_PER_UNIT)*a.Ads_units), SUM(a.Ads_cost)) roas,
    SUM(a.Ads_sales - COALESCE(pct.tier_cost, a.TOTAL_COST_PER_UNIT)*a.Ads_units) gp, SUM(a.Ads_cost) sp
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` a
  LEFT JOIN `onyga-482313.OI.T_PRICE_COST_TIER` pct
    ON a.Ads_units > 0 AND pct.unit_price = ROUND(SAFE_DIVIDE(a.Ads_sales, a.Ads_units), 2)
  WHERE a.date BETWEEN DATE_SUB((SELECT d FROM wm), INTERVAL (SELECT CAST(roas_days AS INT64)-1 FROM cfg) DAY) AND (SELECT d FROM wm)
  GROUP BY 1, 2, 3
),
tsig AS (
  SELECT cid, targeting, SUM(clk) clk3,
    ROUND(AVG(IF(clk >= 3, roas, NULL)), 4) AS eq3_raw,
    ROUND(SAFE_DIVIDE(SUM(gp), NULLIF(SUM(sp),0)), 4) AS pooled3,   -- fallback when no >=3-click day exists
    ROUND(MAX(IF(date = (SELECT d FROM wm), roas, NULL)), 4) AS roas_1d,   -- row 2: last complete day
    -- row 3 / STRONG signal: mean of the two days before the last (2 & 3 days ago), non-overlapping.
    ROUND(COALESCE(
      AVG(IF(clk >= 3 AND date < (SELECT d FROM wm), roas, NULL)),
      SAFE_DIVIDE(SUM(IF(date < (SELECT d FROM wm), gp, 0)), NULLIF(SUM(IF(date < (SELECT d FROM wm), sp, 0)), 0))
    ), 4) AS roas_prev2
  FROM tday GROUP BY 1, 2
),
-- targets carry ids from the ramp view (keyword_id / ad_group_id present for auto expressions too)
tgt AS (
  SELECT campaign_id cid, keyword_id, ANY_VALUE(ad_group_id) ad_group_id, target_text,
    ANY_VALUE(target_type) target_type, ANY_VALUE(match_type) match_type, ANY_VALUE(current_bid) current_bid
  FROM `onyga-482313.OI.V_CAMPAIGN_LAUNCH_RAMP` WHERE keyword_id IS NOT NULL GROUP BY 1, 2, 4
),
-- current ad-group default bid — fallback base ONLY when a target has no per-target bid override
agb AS (SELECT CAST(ad_group_id AS STRING) ad_group_id, ANY_VALUE(default_bid) default_bid
        FROM `onyga-482313.OI.DIM_AD_GROUP` WHERE is_current GROUP BY 1),
base AS (
  SELECT c.campaign_id, c.campaign_name, c.created,
    DATE_DIFF((SELECT d FROM wm), c.created, DAY) + 1 AS day_of_ramp,
    ROUND(COALESCE(d.pd,0), 4) AS pd, cs.eq3 AS c_eq3, cs.roas_1d AS c_roas1, cs.roas_prev2 AS c_roas_prev2, cs.spend_today,
    cb.budget,
    t.keyword_id, t.ad_group_id, t.target_text, t.target_type, t.match_type,
    COALESCE(t.current_bid, agb.default_bid) AS current_bid,
    ts.clk3, COALESCE(ts.eq3_raw, ts.pooled3) AS t_eq3, ts.roas_1d AS t_roas1, ts.roas_prev2 AS t_roas_prev2,
    (COALESCE(d.pd,0) <= x.dark_target AND SAFE_DIVIDE(cs.spend_today, cb.budget) <= x.spend_target) AS starving
  FROM camp c
  CROSS JOIN k x
  LEFT JOIN dark d     ON d.cid = c.campaign_id
  LEFT JOIN camp_sig cs ON cs.cid = c.campaign_id
  LEFT JOIN cbud cb    ON cb.cid = c.campaign_id
  LEFT JOIN tgt t      ON t.cid = c.campaign_id
  LEFT JOIN agb        ON agb.ad_group_id = CAST(t.ad_group_id AS STRING)
  LEFT JOIN tsig ts    ON ts.cid = c.campaign_id AND ts.targeting = t.target_text
)
SELECT
  b.campaign_id, b.campaign_name, b.day_of_ramp,
  ROUND(b.pd*100) AS pct_dark, b.budget AS current_budget, b.spend_today,
  ROUND(b.c_roas1,2) AS camp_roas_1d, ROUND(b.c_eq3,2) AS camp_eq3, ROUND(b.c_roas_prev2,2) AS camp_roas_prev2,
  -- BUDGET SUGGESTION (campaign grain, repeated on each row). STRONG/cut key off roas_prev2 (row 3,
  -- the 2-3-days-ago average); weak keys off roas_1d (row 2, last day) — the two non-overlapping windows.
  CASE
    WHEN b.spend_today IS NULL THEN b.budget
    WHEN b.pd > x.dark_target AND b.c_roas_prev2 > x.strong_roas THEN ROUND(LEAST(SAFE_DIVIDE(b.budget,1-b.pd), b.budget*x.bud_cap_strong),2)
    WHEN b.pd > x.dark_target AND b.c_roas1> x.weak_roas  THEN ROUND(LEAST(SAFE_DIVIDE(b.budget,1-b.pd), b.budget*x.bud_cap_weak),2)
    WHEN b.pd > x.dark_target AND b.c_roas_prev2 < x.cut_roas THEN ROUND(GREATEST(b.budget*x.bud_cut, CAST(x2.floor_daily AS FLOAT64)),2)   -- dark LOSER: cut budget 40% (+ bids brake/cut)
    WHEN b.pd > x.dark_target THEN b.budget   -- dark but genuinely mid (0.9–1.5): hold budget, bids brake
    WHEN SAFE_DIVIDE(b.spend_today,b.budget) <= x.spend_target THEN b.budget
    WHEN b.c_roas_prev2 < x.deep_roas THEN ROUND(GREATEST(b.budget*x.bud_cut, CAST(x2.floor_daily AS FLOAT64)),2)
    WHEN b.c_roas_prev2 < x.cut_roas  THEN ROUND(GREATEST(b.budget*x.bud_trim, CAST(x2.floor_daily AS FLOAT64)),2)
    ELSE b.budget END AS suggested_budget,
  -- Plain-language reason for the budget suggestion (drives the card's row 4).
  CASE
    WHEN b.spend_today IS NULL THEN 'No spend — hold'
    WHEN b.pd > x.dark_target AND b.c_roas_prev2 > x.strong_roas
      THEN CONCAT('Dark ', CAST(ROUND(b.pd*100) AS STRING), '% · prev-2d ', CAST(ROUND(b.c_roas_prev2,2) AS STRING), '× → raise (cap 3×)')
    WHEN b.pd > x.dark_target AND b.c_roas1 > x.weak_roas
      THEN CONCAT('Dark ', CAST(ROUND(b.pd*100) AS STRING), '% · today ', CAST(ROUND(b.c_roas1,2) AS STRING), '× → raise (cap 2×)')
    WHEN b.pd > x.dark_target AND b.c_roas_prev2 < x.cut_roas
      THEN CONCAT('Dark ', CAST(ROUND(b.pd*100) AS STRING), '% · prev-2d ', CAST(ROUND(b.c_roas_prev2,2) AS STRING), '× losing → cut budget 40% + brake bids')
    WHEN b.pd > x.dark_target
      THEN CONCAT('Dark ', CAST(ROUND(b.pd*100) AS STRING), '% · ROAS mid → hold budget, brake bids −', CAST(ROUND(100*0.30*b.pd) AS STRING), '%')
    WHEN SAFE_DIVIDE(b.spend_today,b.budget) <= x.spend_target
      THEN CONCAT('Spent ', CAST(ROUND(100*SAFE_DIVIDE(b.spend_today,b.budget)) AS STRING), '% of budget → hold')
    WHEN b.c_roas_prev2 < x.deep_roas
      THEN CONCAT('Prev-2d ', CAST(ROUND(b.c_roas_prev2,2) AS STRING), '× → cut 40% to floor')
    WHEN b.c_roas_prev2 < x.cut_roas
      THEN CONCAT('Prev-2d ', CAST(ROUND(b.c_roas_prev2,2) AS STRING), '× → trim 10%')
    ELSE 'Stable → hold'
  END AS budget_reason,
  -- BID SUGGESTION (target grain)
  b.keyword_id, b.ad_group_id, b.target_text, b.target_type, b.match_type,
  b.clk3, ROUND(b.t_roas1,2) AS tgt_roas_1d, ROUND(b.t_eq3,2) AS tgt_eq3, ROUND(b.t_roas_prev2,2) AS tgt_roas_prev2, b.current_bid,
  CASE
    WHEN b.current_bid IS NULL THEN NULL
    WHEN b.starving                                             THEN ROUND(LEAST(b.current_bid*x.bid_starve, x.bid_max),2)
    -- PROBE: too few clicks (clk3 < 4) to judge → raise to BUY TRAFFIC even if the campaign is dark. Under
    -- a capped budget this just reallocates the limited spend toward the unproven keyword so it reaches a
    -- decision faster; overrides the dark-brake/cut/hold below (a starved keyword can't be judged or braked).
    WHEN COALESCE(b.clk3,0) < 4                                 THEN ROUND(LEAST(b.current_bid*x.bid_raise_weak, x.bid_max),2)
    WHEN b.t_roas_prev2 < x.cut_roas AND b.t_roas1 < x.cut_roas THEN ROUND(GREATEST(b.current_bid*x.bid_cut, x.bid_min),2)
    -- DARK BRAKE: campaign capping (dark>10%) but ROAS not good enough to fund more budget → reduce bid to
    -- spread spend across the day and stop the cap-out, and SUPPRESS raises (a raise while capping makes it
    -- worse). Reduction scales with darkness: bid × (1 − 0.30·%dark). Floors at bid_min. Placed before the
    -- raise branches so it overrides them; the losing-target CUT above still wins (a harder cut).
    -- EXCEPTION: a PROFITABLE target (net ROAS ≥ 1.0 on either recent window) is NOT braked — cutting a good
    -- spot while capping just starves your best target. It HOLDs (raises still suppressed while dark).
    WHEN b.pd > x.dark_target AND b.c_roas_prev2 <= x.strong_roas AND b.c_roas1 <= x.weak_roas
         AND (b.t_roas1 >= 1.0 OR b.t_roas_prev2 >= 1.0) THEN b.current_bid
    WHEN b.pd > x.dark_target AND b.c_roas_prev2 <= x.strong_roas AND b.c_roas1 <= x.weak_roas
      THEN ROUND(GREATEST(b.current_bid*(1 - 0.30*b.pd), x.bid_min),2)
    WHEN b.t_roas_prev2 > x.strong_roas AND b.t_roas1 > x.strong_roas THEN ROUND(LEAST(b.current_bid*x.bid_raise_strong, x.bid_max),2)
    WHEN b.t_roas1 > x.weak_roas                               THEN ROUND(LEAST(b.current_bid*x.bid_raise_weak, x.bid_max),2)
    ELSE b.current_bid END AS suggested_bid,
  CASE
    WHEN b.current_bid IS NULL THEN 'NO_BID'
    WHEN b.starving THEN 'STARVE'
    WHEN COALESCE(b.clk3,0) < 4 THEN 'PROBE'
    WHEN b.t_roas_prev2 < x.cut_roas AND b.t_roas1 < x.cut_roas THEN 'CUT'
    WHEN b.pd > x.dark_target AND b.c_roas_prev2 <= x.strong_roas AND b.c_roas1 <= x.weak_roas
         AND (b.t_roas1 >= 1.0 OR b.t_roas_prev2 >= 1.0) THEN 'HOLD'
    WHEN b.pd > x.dark_target AND b.c_roas_prev2 <= x.strong_roas AND b.c_roas1 <= x.weak_roas THEN 'BRAKE'
    WHEN b.t_roas_prev2 > x.strong_roas AND b.t_roas1 > x.strong_roas THEN 'RAISE_STRONG'
    WHEN b.t_roas1 > x.weak_roas THEN 'RAISE_WEAK'
    ELSE 'HOLD' END AS bid_action
FROM base b CROSS JOIN k x CROSS JOIN cfg x2;
