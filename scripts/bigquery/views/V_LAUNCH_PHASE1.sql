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
--   MONEY-BLEEDER (0 conversions over the window, scaled by clicks) — checked FIRST, before starving, so a
--     heavy-spending non-converter is trimmed, NOT raised by the campaign under-spend signal (a campaign can
--     under-spend in total while one target hogs the budget and converts nothing):
--       clk3 4-7,  0 sales → HOLD  (BLEED_WATCH — gather, don't raise, don't cut yet)
--       clk3 >=8,  0 sales → ×0.80 (BLEED_TRIM, -20% — stop the bleed)
--       clk3 >=15, 0 sales → ×0.60 (BLEED_CUT,  -40% — Ori's decision point)
--     Keyed on sales3<=0 (0 conversions), NOT net ROAS — a converting-but-unprofitable target still takes the
--     normal starve/cut path below. clk3<4 (unproven) falls through to PROBE and IS still raised.
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
         0.80 AS bid_cut, 1.30 AS bid_raise_strong, 1.15 AS bid_raise_weak, 1.10 AS bid_starve, 1.05 AS bid_probe,
         0.20 AS bid_min, 1.50 AS bid_max, 2.00 AS bid_hard_cap, 0.90 AS bud_trim, 0.60 AS bud_cut, 2.0 AS bud_cap_weak, 3.0 AS bud_cap_strong,
         -- money-bleeder ladder: a target with enough clicks to judge but ZERO conversions is trimmed, scaled by
         -- clicks — NOT raised by the campaign-level STARVE (a campaign can under-spend in total while one target
         -- hogs the budget and converts nothing). 4-7 clk: watch (gather); >=8: -20%; >=15 (decision pt): -40%.
         4 AS bleed_watch_clk, 8 AS bleed_trim_clk, 15 AS bleed_cut_clk, 0.80 AS bid_bleed_trim, 0.60 AS bid_bleed_cut,
         -- LAUNCH CLICK GOAL (Ori 2026-07-24): "the goal is to get 4 clicks a day and wait for a sell."
         -- ⚠️ Judged on the LAST COMPLETE DAY's clicks (t_clk1), NOT a multi-day average (Ori 2026-07-25:
         -- pointed at last-day 6 then last-day 10 as "reduce"). "clicks a day" = the most recent full day.
         --   t_clk1 < 4 → PROBE (+5%, under-clicked yesterday, buy more) · t_clk1 >= 6 → SLOW (−5%, 6+ clicks
         --   yesterday with no sale — stop over-buying) · 4–5 → HOLD and wait for a sale.
         -- (An earlier attempt averaged clk3 over active days; that still diluted a 10-clicks-yesterday target
         -- with prior lighter days down into the hold band. The last day is the signal.)
         -- click_cap_day: the top of the learning band. Above ~6 clicks/day a NON-CONVERTING keyword is buying
         -- more traffic than it needs to reach a verdict, so the bid comes down (−5%, symmetric with the +5%
         -- probe — a converging controller, not a loss cut). These are also the keywords that actually cap the
         -- campaign's budget, so this replaces the keyword-level DARK BRAKE.
         4 AS click_goal_day, 6 AS click_cap_day, 0.95 AS bid_slow,
         -- BUDGET-CONSTRAINED PROBING (Ori 2026-07-30): in a CAPPED campaign under-clicking is a
         -- budget artifact, not a bid problem ("10 kw × 4 clicks at $1 = $40 on a $10 budget").
         -- Tested keywords (>=15 clicks/90d, no sale) PARK at $0.25 to fund the untested probes;
         -- bids > $1 with clicks TRIM -15%/day toward $1; probe-up only when NOT capped.
         15 AS tested_clk, 0.25 AS bid_park, 1.00 AS big_bid, 0.85 AS bid_big_trim,
         -- BUDGET PROMOTION (Ori 2026-07-24): "when performance is good budget will increase and be more
         -- than low budget, then working campaigns methodology takes over." The launch controller is what
         -- funds a campaign OUT of the low-budget regime — graduation is emergent, not a separate rule:
         -- raise the budget while it performs, and once it clears the cap V_LAUNCH_POPULATION stops
         -- returning it and the coacher picks it up. Steps are deliberately gradual so a campaign ramps
         -- (e.g. $8 → $10 → $12.50 …) rather than jumping straight past the cap on one good day.
         1.25 AS bud_promote_weak, 1.50 AS bud_promote_strong,
         -- Promotion FLOORS (Ori 2026-07-24): a proven campaign shouldn't crawl up from $7 in 25% steps —
         -- a strong performer jumps straight to at least $20, a weak-but-positive one to at least $15.
         -- Note off-season (cap $20) a strong promote lands exactly ON the cap, so it stays in launch one
         -- more day and graduates on the next raise ($20 → $30). That is intentional: it clears the cap by
         -- performing twice, not once.
         20.0 AS bud_floor_strong, 15.0 AS bud_floor_weak
),
-- Anchor "today" on the last complete LA day, never the current (incomplete) one — at 09:00 the current LA
-- day has ~10% of its spend and every signal would read as a false zero. FN_ADS_ANCHOR_CAP() = yesterday
-- normally, but the current LA day once it's within its last 2h (sales effectively done), so a user ahead of
-- LA sees today's date late in the LA evening instead of waiting for LA midnight.
wm AS (SELECT LEAST(MAX(date), `onyga-482313.OI.FN_ADS_ANCHOR_CAP`()) AS d
       FROM `onyga-482313.OI.FACT_AMAZON_ADS`),
-- Enabled campaigns inside the 20-day window (same gate as V_CAMPAIGN_LAUNCH_RAMP)
-- POPULATION (Ori 2026-07-24): no longer "first 20 days" but LOW BUDGET — a campaign is governed by the
-- launch controller while its daily budget sits at/below the low-budget cap (peak $30 / off-season $20).
-- The definition lives in V_LAUNCH_POPULATION so the launch engine, the coacher's is_new_campaign flag and
-- the dashboard's launch-vs-mature split cannot drift apart. It carries 3-day hysteresis: promotion is
-- immediate, demotion needs 3 consecutive days under the cap. See that view's header for the reasoning.
camp AS (
  SELECT campaign_id, created, campaign_name,
         budget_today, low_budget_cap, in_peak
  FROM `onyga-482313.OI.V_LAUNCH_POPULATION`
),
-- %dark today, per LA day (Amazon's own out-of-budget verdict). Source: the UNIFIED SP∪SB event log
-- (V_SRC interface), NOT the raw SP-only campaign_history — a raw read here silently missed every SB
-- campaign's dark time (2026-07-30; see architecture/CAMPAIGN_LAUNCH_RAMP.md §"Status source"). Not
-- DIM_CAMPAIGN either: its SCD2 samples status 3×/day, so flips that revert between loads vanish.
h AS (
  SELECT campaign_id cid, DATETIME(date, 'America/Los_Angeles') ts, serving_status
  FROM `onyga-482313.OI.V_SRC_AmazonAds_campaign_history`
  WHERE DATE(date, 'America/Los_Angeles') = (SELECT d FROM wm)
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
    SUM(a.Ads_sales - COALESCE(pct.tier_cost, a.TOTAL_COST_PER_UNIT)*a.Ads_units) gp, SUM(a.Ads_cost) sp,
    SUM(a.Ads_sales) sales
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` a
  LEFT JOIN `onyga-482313.OI.T_PRICE_COST_TIER` pct
    ON a.Ads_units > 0 AND pct.unit_price = ROUND(SAFE_DIVIDE(a.Ads_sales, a.Ads_units), 2)
  WHERE a.date BETWEEN DATE_SUB((SELECT d FROM wm), INTERVAL (SELECT CAST(roas_days AS INT64)-1 FROM cfg) DAY) AND (SELECT d FROM wm)
  GROUP BY 1, 2, 3
),
tsig AS (
  SELECT cid, targeting, SUM(clk) clk3, SUM(sp) sp3, SUM(IF(date = (SELECT d FROM wm), clk, 0)) clk1, COALESCE(SUM(sales),0) sales3,
    -- days the target actually got clicks in the window — the DENOMINATOR for "clicks per day".
    -- Dividing clk3 by a fixed 3 diluted a burst: a target with 6 clicks on ONE day read as 2/day and
    -- was told to raise, when its real rate is 6/day (Ori 2026-07-25). Rate = clk3 / active click-days.
    COUNT(DISTINCT IF(clk > 0, date, NULL)) AS active_days,
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
-- tested clicks per target over 90d — evidence for the PARK rule (has it had its test?)
t90 AS (
  SELECT CAST(campaign_id AS STRING) cid, targeting, SUM(Ads_clicks) clk90, SUM(Ads_orders) ord90
  FROM `onyga-482313.OI.FACT_AMAZON_ADS`
  WHERE date BETWEEN DATE_SUB((SELECT d FROM wm), INTERVAL 89 DAY) AND (SELECT d FROM wm)
  GROUP BY 1, 2
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
    -- Prefer the live V_TARGET_DAILY budget; fall back to the population's copy so a campaign with no
    -- target rows yet (brand new) still has a budget to reason about instead of NULLing the whole ladder.
    COALESCE(cb.budget, c.budget_today) AS budget,
    c.low_budget_cap, c.in_peak,
    t.keyword_id, t.ad_group_id, t.target_text, t.target_type, t.match_type,
    COALESCE(t.current_bid, agb.default_bid) AS current_bid,
    ts.clk3, ts.sp3, ROUND(SAFE_DIVIDE(ts.sp3, NULLIF(ts.clk3,0)),2) AS cpc3, COALESCE(ts.clk1,0) AS t_clk1, COALESCE(ts.sales3,0) AS t_sales3, COALESCE(ts.eq3_raw, ts.pooled3) AS t_eq3, ts.roas_1d AS t_roas1, ts.roas_prev2 AS t_roas_prev2,
    COALESCE(t90.clk90, 0) AS clk90, COALESCE(t90.ord90, 0) AS ord90,
    -- clicks/day over active days (the real rate) — drives the click-rate controller instead of clk3/3.
    ROUND(SAFE_DIVIDE(ts.clk3, NULLIF(ts.active_days, 0)), 2) AS clk_rate,
    (COALESCE(d.pd,0) <= x.dark_target AND SAFE_DIVIDE(cs.spend_today, cb.budget) <= x.spend_target) AS starving
  FROM camp c
  CROSS JOIN k x
  LEFT JOIN dark d     ON d.cid = c.campaign_id
  LEFT JOIN camp_sig cs ON cs.cid = c.campaign_id
  LEFT JOIN cbud cb    ON cb.cid = c.campaign_id
  LEFT JOIN tgt t      ON t.cid = c.campaign_id
  LEFT JOIN agb        ON agb.ad_group_id = CAST(t.ad_group_id AS STRING)
  LEFT JOIN tsig ts    ON ts.cid = c.campaign_id AND ts.targeting = t.target_text
  LEFT JOIN t90       ON t90.cid = c.campaign_id AND t90.targeting = t.target_text
),
-- affordable CPC (Ori 2026-07-30: TRIM floor must not stop at $1) = budget ÷ (targets × 4-click
-- goal), floored at bid_min. Self-scaling: rich budgets get high aff and are left alone.
baseN AS (
  SELECT b.*, ROUND(GREATEST(SAFE_DIVIDE(b.budget, COUNT(*) OVER (PARTITION BY b.campaign_id) * 4), 0.20), 2) AS aff_cpc,
    SAFE_DIVIDE(
      SUM(IF(COALESCE(b.t_roas1,0) >= 1.0 OR COALESCE(b.t_roas_prev2,0) >= 1.0, b.sp3, 0)) OVER (PARTITION BY b.campaign_id),
      NULLIF(SUM(b.sp3) OVER (PARTITION BY b.campaign_id), 0)) AS conv_share
  FROM base b
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
    -- ═══ PROMOTION: earning its budget → fund it toward graduation ═══
    -- The campaign is USING its budget (spend ratio past the target) AND converting. Raise it. Repeated
    -- daily this walks the budget up until it clears the low-budget cap, at which point the campaign
    -- leaves V_LAUNCH_POPULATION and the working-campaign methodology (coacher) takes over. This is the
    -- ONLY thing that graduates a campaign — without it nothing ever crosses the cap and every campaign
    -- would stay in launch mode forever.
    WHEN b.c_roas_prev2 >= x.strong_roas THEN ROUND(GREATEST(b.budget*x.bud_promote_strong, x.bud_floor_strong),2)
    WHEN b.c_roas1      >= x.weak_roas   THEN ROUND(GREATEST(b.budget*x.bud_promote_weak,   x.bud_floor_weak),2)
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
    WHEN b.c_roas_prev2 >= x.strong_roas
      THEN CONCAT('Using its budget · prev-2d ', CAST(ROUND(b.c_roas_prev2,2) AS STRING),
                  '× → raise to $', CAST(ROUND(GREATEST(b.budget*x.bud_promote_strong, x.bud_floor_strong),2) AS STRING),
                  ' (+50%, min $', CAST(CAST(x.bud_floor_strong AS INT64) AS STRING),
                  ') toward graduation — leaves low-budget mode above $',
                  CAST(CAST(ROUND(b.low_budget_cap) AS INT64) AS STRING))
    WHEN b.c_roas1 >= x.weak_roas
      THEN CONCAT('Using its budget · today ', CAST(ROUND(b.c_roas1,2) AS STRING),
                  '× → raise to $', CAST(ROUND(GREATEST(b.budget*x.bud_promote_weak, x.bud_floor_weak),2) AS STRING),
                  ' (+25%, min $', CAST(CAST(x.bud_floor_weak AS INT64) AS STRING),
                  ') toward graduation — leaves low-budget mode above $',
                  CAST(CAST(ROUND(b.low_budget_cap) AS INT64) AS STRING))
    WHEN b.c_roas_prev2 < x.deep_roas
      THEN CONCAT('Prev-2d ', CAST(ROUND(b.c_roas_prev2,2) AS STRING), '× → cut 40% to floor')
    WHEN b.c_roas_prev2 < x.cut_roas
      THEN CONCAT('Prev-2d ', CAST(ROUND(b.c_roas_prev2,2) AS STRING), '× → trim 10%')
    ELSE 'Stable → hold'
  END AS budget_reason,
  -- BID SUGGESTION (target grain)
  b.keyword_id, b.ad_group_id, b.target_text, b.target_type, b.match_type,
  b.clk3, b.clk_rate, b.t_clk1 AS clk_last_day, ROUND(b.t_roas1,2) AS tgt_roas_1d, ROUND(b.t_eq3,2) AS tgt_eq3, ROUND(b.t_roas_prev2,2) AS tgt_roas_prev2, b.current_bid,
  -- LAUNCH-WINDOW BID MODEL (Ori, 2026-07-21; click-rate control added 2026-07-24).
  -- The purpose is to FIND THE RIGHT BID, not to cut losers. Two regimes, split by whether the KEYWORD converts:
  --
  -- A) NOT CONVERTING (net ROAS < 1 on both recent windows) → pure CLICK-RATE control toward 4–6 clicks/day:
  --      • < 4 clicks/day  → raise +5%  (buy traffic — you cannot get a verdict without clicks)
  --      • > 6 clicks/day  → lower −5%  (buying more traffic than needed to learn; slow the burn)
  --      • 4–6 clicks/day  → HOLD and wait for a sale
  --    %DARK IS DELIBERATELY IGNORED HERE (Ori 2026-07-24: "dark % wont address it because this keyword is not
  --    the cause for it being dark"). Campaign darkness is a BUDGET problem, handled in the budget CASE above.
  --    Braking a 1-click keyword saved nothing on the cap and pushed it further from a verdict. The keywords
  --    that ARE the cause of capping are the >6 clicks/day ones — and those are exactly what this rule lowers,
  --    so capping control is still present, just attributed to the keywords actually buying the volume.
  --
  -- B) CONVERTING (net ROAS >= 1 on either recent window) → the pre-existing logic continues unchanged:
  --    profitable-but-capping → HOLD (raising while dark makes capping worse); selling harder → RAISE.
  --
  -- Losses are never cut at the keyword bid during launch; the money bleed is stopped at the SEARCH-TERM level
  -- (negate non-converting terms at >=15 clicks / 0 orders — V_RUN_SEARCH_TERM), which surgically kills dead
  -- terms while the keyword keeps hunting. Phase 2 (day 20+) makes the final keep/cut call.
  CASE
    WHEN b.current_bid IS NULL THEN NULL
    -- ── A) NOT CONVERTING → click-rate control only (no %dark term anywhere in this branch) ──
    WHEN NOT (COALESCE(b.t_roas1,0) >= 1.0 OR COALESCE(b.t_roas_prev2,0) >= 1.0) THEN
      CASE
        -- CAPPED campaign: budget-constrained probing (Ori 2026-07-30) — park tested, trim big
        -- bids, NEVER probe up (under-clicking here is the budget dying, not the bid too low)
        WHEN b.pd > x.dark_target THEN CASE
          WHEN b.clk90 >= x.tested_clk AND b.ord90 = 0 AND b.current_bid > x.bid_park + 0.05 THEN x.bid_park
          -- TRIM needs real evidence (4+ clicks yesterday, Ori 2026-08-01); step max(15%, 30% x dark)
          WHEN b.current_bid > COALESCE(b.aff_cpc, x.big_bid) + 0.05 AND COALESCE(b.t_clk1,0) >= x.click_goal_day
            THEN ROUND(GREATEST(b.current_bid * LEAST(x.bid_big_trim, 1 - 0.30 * b.pd), COALESCE(b.aff_cpc, x.bid_min)),2)
          -- DARK_BRAKE: campaign-wide, dark-proportional step max(5%, 30% x dark), daily, floor $0.20
          WHEN COALESCE(b.t_clk1,0) >= 1 AND b.current_bid > x.bid_min + 0.05
            THEN ROUND(GREATEST(b.current_bid * LEAST(x.bid_slow, 1 - 0.30 * b.pd), x.bid_min),2)
          ELSE b.current_bid
        END
        WHEN COALESCE(b.t_clk1,0) <  x.click_goal_day THEN ROUND(LEAST(b.current_bid*x.bid_probe, x.bid_max),2)
        WHEN COALESCE(b.t_clk1,0) >= x.click_cap_day  THEN ROUND(GREATEST(b.current_bid*x.bid_slow, x.bid_min),2)
        ELSE b.current_bid   -- last day 4–5 clicks: hold and wait for a sale
      END
    -- ── B) CONVERTING → capped: NEVER raise (Ori 2026-07-30) — fit the bid down to the realized
    -- 3d CPC when clicks are plentiful; the budget raise buys the volume, cheaper clicks buy more.
    WHEN b.pd > x.dark_target THEN CASE
      -- winner-concentrated (>=80% of spend on converters): glide -5%/day (Ori 2026-07-30)
      WHEN COALESCE(b.conv_share,0) >= 0.80 THEN
        IF(COALESCE(b.t_clk1,0) > 6 AND b.cpc3 IS NOT NULL AND b.current_bid > b.cpc3 + 0.05,
           ROUND(GREATEST(b.current_bid * 0.95, b.cpc3), 2), b.current_bid)
      WHEN COALESCE(b.t_clk1,0) >= x.click_goal_day AND b.cpc3 IS NOT NULL AND b.current_bid > b.cpc3 + 0.05
        THEN ROUND(GREATEST(b.current_bid * x.bid_big_trim, b.cpc3), 2)
      ELSE b.current_bid END
    -- WINNERS: fund them. A CONVERTING target raises toward the $2 HARD CAP, not the $1.50 launch cap
    -- (Ori 2026-07-24): the $1.50 cap is a ceiling for UNPROVEN targets; once a target converts it has
    -- earned the right to bid up like the mature coacher. Without this a proven winner whose current bid
    -- already exceeds $1.50 (e.g. a competitor-PT target at $1.82) was "raised" straight down to $1.50.
    WHEN b.t_roas_prev2 > x.strong_roas AND b.t_roas1 > x.strong_roas THEN ROUND(LEAST(b.current_bid*x.bid_raise_strong, x.bid_hard_cap),2)
    WHEN b.t_roas1 > x.weak_roas                               THEN ROUND(LEAST(b.current_bid*x.bid_raise_weak, x.bid_hard_cap),2)
    ELSE b.current_bid END AS suggested_bid,
  CASE
    WHEN b.current_bid IS NULL THEN 'NO_BID'
    WHEN NOT (COALESCE(b.t_roas1,0) >= 1.0 OR COALESCE(b.t_roas_prev2,0) >= 1.0) THEN
      CASE
        WHEN b.pd > x.dark_target THEN CASE
          WHEN b.clk90 >= x.tested_clk AND b.ord90 = 0 AND b.current_bid > x.bid_park + 0.05 THEN 'PARK'
          WHEN b.current_bid > COALESCE(b.aff_cpc, x.big_bid) + 0.05 AND COALESCE(b.t_clk1,0) >= x.click_goal_day THEN 'TRIM_BID'
          WHEN COALESCE(b.t_clk1,0) >= 1 AND b.current_bid > x.bid_min + 0.05 THEN 'DARK_BRAKE'
          ELSE 'HOLD'
        END
        WHEN COALESCE(b.t_clk1,0) <  x.click_goal_day THEN 'PROBE'
        WHEN COALESCE(b.t_clk1,0) >= x.click_cap_day  THEN 'SLOW'
        ELSE 'HOLD'
      END
    WHEN b.pd > x.dark_target THEN CASE
      WHEN COALESCE(b.conv_share,0) >= 0.80 THEN
        IF(COALESCE(b.t_clk1,0) > 6 AND b.cpc3 IS NOT NULL AND b.current_bid > b.cpc3 + 0.05, 'EASE', 'HOLD')
      WHEN COALESCE(b.t_clk1,0) >= x.click_goal_day AND b.cpc3 IS NOT NULL AND b.current_bid > b.cpc3 + 0.05 THEN 'FIT_CPC'
      ELSE 'HOLD' END
    WHEN b.t_roas_prev2 > x.strong_roas AND b.t_roas1 > x.strong_roas THEN 'RAISE_STRONG'
    WHEN b.t_roas1 > x.weak_roas THEN 'RAISE_WEAK'
    ELSE 'HOLD' END AS bid_action
FROM baseN b CROSS JOIN k x CROSS JOIN cfg x2;
