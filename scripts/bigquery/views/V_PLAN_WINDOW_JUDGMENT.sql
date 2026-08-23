-- =============================================================================================
-- V_PLAN_WINDOW_JUDGMENT — v27.133 (2026-08-23): ONE ROW PER working-family keyword, carrying the
-- window, the window record (raw AND corrected for settle completion), the side BOTH plans give
-- it, the arm that decided it, the repaired price, the seat cost and the rank. It decides nothing
-- about money: the builder (SP_BUILD_NEXT_WEEK_PLAN) does the potting, seating and queueing. This
-- view is the JUDGEMENT, and it is a view so a person can read it at any moment without a pass.
--
-- THE UNIVERSE (spec §8, P-11): the HARVEST book's families, campaigns that are ENABLED today, no
-- brand defense (never judged on profit), no launch-contained keyword (the launch controller owns
-- those). Everything else in the account is outside this plan and is untouched by it.
--
-- THE WINDOW (P-10, P-13, P-14a). window_days complete days ending at
--   window_to = LEAST(watermark - 1, CURRENT_DATE('America/Los_Angeles') - 2)
-- where watermark = LEAST(MAX(date), FN_ADS_ANCHOR_CAP()) over FACT_AMAZON_ADS. The filling day
-- never enters a window (P-10), and neither does a day younger than two: FN_ADS_ANCHOR_CAP()
-- advances to the current LA date at 22:00 LA, so a late-evening run would otherwise admit an
-- age-1 day, whose SPEND the settle curve publishes as materially short of final — understating
-- the pot, the allowance and every seat cost in the same direction, with no error and no log line.
-- Before 22:00 LA the two terms are equal and the fence costs nothing. window_days, the allowance
-- share, the ramp and the ORDER FLOOR all come from DE_PLAN_CONFIG for the state
-- FN_PLAN_CALENDAR_STATE reads today — no setting is a literal in this file.
--
-- THE SIDE (P-1, P-3, P-5, P-14). Rule B judges the window, not the ladder's 90-day record:
--   GOOD        min_orders orders IN THE WINDOW and window gross profit per ad dollar at or above
--               the family bar. Order COUNTS are read as observed and are never inflated (P-14a:
--               a count cannot be fractionally corrected); the RETURN is read corrected.
--   HELD_UNSETTLED (P-14b) a keyword that WAS good and now reads not-good, whose window has not
--               yet settled (SP 7 / SB 14 complete days after window_to). It keeps the good side,
--               held, and carries the date it will be judged again with no guard. Promotion is
--               allowed on fresh evidence; only demotion waits. This is the ASYMMETRY.
--   GRACE (P-5) a ladder-settled winner (WINNER / PACED_WINNER) with a quiet window keeps the
--               good side for one window, held. Ordered AFTER the settle guard so a one-window
--               grace budget is not spent while the evidence is still arriving. (The shipped
--               reprice book, tools/build_reprice_bulksheet.py --rule-b, orders grace BEFORE the
--               guard; both put the row on the good side, so only the NAME of the arm differs.
--               The plan's order is authoritative here and Task 4 aligns the book.)
--   LOSING / ONE_ORDER / NO_SALE / NOT_SERVING — the not-good side.
-- decided_by names the ruling that decided the row: P-3, P-14b or P-5. settle_arm names what the
-- correction did: SETTLED, CORRECTED, PROMOTED_ON_FRESH, HELD_UNSETTLED, UNCORRECTED_NO_CURVE.
--
-- "WAS GOOD" (P-14b) is last night's live-plan side if there is one, or — on the first night, and
-- for a keyword the plan has not seen — the ladder's own settled record at or above the bar with
-- min_orders settled orders. Both are records of a judgement already made, never of today's
-- window. This is the same bootstrap the reprice book declares.
--
-- HOW THE CORRECTION IS APPLIED, and one deliberate departure from the plan's sketch. The sketch
-- summed each day's gross profit divided by that day's own factor. That is right whenever a
-- window's days share a sign, and it is what this view computes in that case — but GROSS_PROFIT
-- can be negative on a day, and a window mixing a corrected positive day with an uncorrected
-- negative one can come out SMALLER in magnitude than the raw window, which breaks the §9
-- guarantee ("never smaller in magnitude") on live data rather than in theory. So the same
-- arithmetic is written as ONE division by a published effective factor:
--   settle_factor_eff = SUM(|gp_d|) / SUM(|gp_d| / f_d)   (a magnitude-weighted harmonic mean)
--   w_gp_corrected    = w_gp / settle_factor_eff
-- With every f_d <= 1 the effective factor is in (0, 1], so the correction can only ever RAISE
-- the magnitude and can never flip the sign — the guarantee holds by construction, for every
-- window, and the acceptance (C10) checks that corrected x factor reconstructs the raw figure, so
-- the correction remains ONE published, reversible division a reader can audit. When every day of
-- a window has the same sign this is ALGEBRAICALLY IDENTICAL to the per-day sum the sketch wrote.
--
-- A CONSEQUENCE ORI MUST SEE BEFORE HE RULES ON P-14, and it is not a bug in this file: the
-- window this view judges ALWAYS ends at window_to = today - 2 (the P-14a fence), and a window
-- settles settle_days AFTER window_to, so `settled` is FALSE on every row every night that the
-- ads pipeline is healthy. P-14b therefore does not delay a demotion — under a rolling window it
-- PREVENTS one: a keyword whose ladder record clears its family bar cannot be moved to the
-- not-good side by rule B at all, whatever the window says, and the "judged again with no guard"
-- date in §3a never arrives because the next night judges a NEW unsettled window. That pulls rule
-- B (P-1: the window decides the side) back towards plan A (the ladder decides). It is built as
-- the ruling is written, it is measured, and it is named here rather than discovered later:
--   SELECT family, side_b, settle_arm, COUNT(*) kw, ROUND(SUM(w_sp)/MAX(window_days), 2) sp_day
--   FROM `onyga-482313.OI.V_PLAN_WINDOW_JUDGMENT` GROUP BY 1, 2, 3 ORDER BY 1, 2, 5 DESC;
-- (the HELD_UNSETTLED rows are the money the guard moves to the good side, where P-4 says it is
-- never cut and never re-priced). The one-line fix, if Ori wants the guard to be a DELAY and not
-- a veto: demote on the last window that HAS settled (a second window ending settle_days before
-- window_to) while promoting on the fresh one — that is a change to P-14b's evidence, and nobody
-- has made it. See architecture/NEXT_WEEK_MONEY.md §2.
--
-- A KEYWORD THAT DID NOT SERVE is not a keyword the curve failed on. Where the window holds no
-- day for a keyword there is nothing to correct and nothing in flight (no clicks, no sales
-- arriving), so its empty record is already final: the arm is SETTLED and the row says so in
-- words. Reserving UNCORRECTED_NO_CURVE for rows the curve genuinely could not answer keeps that
-- label meaning something — it is the label that tells Ori the plan is resting on the guard alone.
--
-- PLAN A (shadow, P-9) takes the side from the ladder state alone: WINNER, PACED_WINNER, AT_BAR
-- and the waiting states (TRIAL, PENDING_SETTLE, REVIVED_SETTLING) are its good side; REPRICE,
-- LOSER, FLOOR_PROBATION, PARKED and DEAD are not. The amounts are the same window amounts.
--
-- THE REPAIRED PRICE (P-6) is the ladder's affordable_bid, capped at three 5% steps in either
-- direction from the live bid, floored at the row's own bid_floor (the ONE floor definition,
-- FN_BID_FLOOR through the state table) and ceilinged at the house $2.00 for a raise. The cap
-- constants are mirrored from tools/build_reprice_bulksheet.py so the book and the plan cannot
-- price the same keyword differently.
-- SEAT COST (P-6) is spend at THAT price, not last window's spend: the window's spend per day
-- scaled linearly by the price change (the same linear bid-to-spend guess the seat register uses
-- on its day-one horizon). A candidate with no window spend is priced at the engine's seat
-- economics — seat_cpc times the register's declared click goal per day.
-- RANK (P-7) is dollars at stake times closeness to the bar: window spend per day times corrected
-- return over the bar, ties broken by window clicks then by the keyword key (a total ordering).
--
-- CANDIDACY (§4 step 3). A candidate is a not-good keyword that is not in the holdout AND has
-- something to repair: losing, one order, or spend with no sale. A keyword that took no spend and
-- no clicks in the window has no repair to buy and is NOT a candidate unless the probe list
-- nominates it (LIFT's probes stay a candidate SOURCE under P-11). Otherwise every dormant
-- keyword in the book would queue for a zero-cost seat and bury the ranking the seats exist for.
--
-- Planner note: every source here is a snapshot table or a small view. The ceiling views are read
-- only through their T_ tables (T_OOB_SEAT_ECONOMICS, T_LIFT_PROBES), per the house rule.
-- Spec: docs/superpowers/specs/2026-08-23-next-week-money-plan-design.md §3, §3a, §4, P-1..P-14.
-- SOP: architecture/NEXT_WEEK_MONEY.md §2.
-- Acceptance: scripts/bigquery/tests/V_PLAN_WINDOW_JUDGMENT_acceptance.sql.
-- =============================================================================================
CREATE OR REPLACE VIEW `onyga-482313.OI.V_PLAN_WINDOW_JUDGMENT`
OPTIONS (description = "v27.133 (2026-08-23): one row per working-family (HARVEST) keyword — the complete-days window from DE_PLAN_CONFIG for today's calendar state, fenced so no judged day is younger than age 2 (P-10 + P-14a), the keyword's record in it raw AND corrected for settle completion via V_PLAN_SETTLE_COMPLETION, the side rule B gives it (P-1/P-3), the P-14b asymmetric guard (promote on fresh evidence, never demote until the window has settled: SP 7 / SB 14), the P-5 grace for ladder-settled winners, the shadow plan A side from the ladder state (P-9), the repaired price capped at three 5% steps and floored at the row's own bid_floor (P-6), the seat cost at that price, and the P-7 rank. The correction is ONE reversible division by a published effective factor (settle_factor_eff, a magnitude-weighted mean of the per-day factors) so it can never shrink or flip a window's gross profit. Publishes settle_arm and decided_by on every row, plus a plain sentence naming the arm. Judges only; SP_BUILD_NEXT_WEEK_PLAN does the potting, seating and queueing. Brand defense, launch-contained keywords and non-enabled campaigns are outside the universe. Spec P-1..P-14, §3a. SOP: architecture/NEXT_WEEK_MONEY.md")
AS
WITH k AS (
  -- P-3/P-13: min_orders is NOT a literal — it is read from DE_PLAN_CONFIG in the cfg CTE below
  -- and joined in. Writing `2 AS min_orders` here would put the order floor in two places that
  -- can disagree, which is the exact defect DE_PLAN_CONFIG exists to prevent.
  SELECT 0.05   AS material_step,     -- mirrored from tools/build_reprice_bulksheet.py MATERIAL_STEP
         3      AS blind_steps,       -- ...and BLIND_STEPS: the engine's blind run before a re-read
         2.00   AS raise_ceiling,     -- the house bid ceiling (GUARDIAN threshold redesign)
         4      AS click_goal_day,    -- mirrored from V_FAMILY_SEAT_REGISTER k.click_goal_day
         7      AS settle_days_sp,    -- SP attribution window, complete days (P-12, P-14b)
         14     AS settle_days_sb     -- SB attribution window, complete days
),
caps AS (
  SELECT k.*,
         POW(1 + k.material_step, k.blind_steps) - 1 AS cap_up,
         1 - POW(1 - k.material_step, k.blind_steps) AS cap_down
  FROM k
),
today AS (
  SELECT CURRENT_DATE('America/Los_Angeles') AS d_la,
         CURRENT_DATE('America/New_York')    AS d_ny
),
cfg AS (
  -- Every setting, min_orders included. Copy this CTE, not a subset of it.
  SELECT calendar_state, window_days, allowance_share, live_plan, ramp_steps, min_orders
  FROM `onyga-482313.OI.DE_PLAN_CONFIG`
  WHERE is_active
  QUALIFY ROW_NUMBER() OVER (PARTITION BY calendar_state ORDER BY updated_at DESC) = 1
),
state AS (
  SELECT `onyga-482313.OI.FN_PLAN_CALENDAR_STATE`(t.d_ny) AS calendar_state
  FROM today t
),
wm AS (
  SELECT LEAST(MAX(date), `onyga-482313.OI.FN_ADS_ANCHOR_CAP`()) AS d
  FROM `onyga-482313.OI.FACT_AMAZON_ADS`
),
win AS (
  -- P-10 + the P-14a FENCE (see the header).
  SELECT s.calendar_state, c.window_days, c.allowance_share, c.live_plan, c.ramp_steps,
         c.min_orders,
         wm.d                                                  AS watermark,
         LEAST(DATE_SUB(wm.d, INTERVAL 1 DAY),
               DATE_SUB(t.d_la, INTERVAL 2 DAY))               AS window_to,
         DATE_SUB(LEAST(DATE_SUB(wm.d, INTERVAL 1 DAY),
                        DATE_SUB(t.d_la, INTERVAL 2 DAY)),
                  INTERVAL c.window_days - 1 DAY)              AS window_from
  FROM state s
  JOIN cfg c USING (calendar_state)
  CROSS JOIN wm
  CROSS JOIN today t
),
books AS (
  SELECT family, book FROM `onyga-482313.OI.V_BOOK_ASSIGNMENT` WHERE book = 'HARVEST'
),
snap AS (
  SELECT MAX(snapshot_date) AS d FROM `onyga-482313.OI.FACT_KEYWORD_STATE`
),
camp AS (
  -- one row per campaign, chosen deterministically (never a pair of ANY_VALUEs)
  SELECT CAST(campaign_id AS STRING) AS cid, campaign_state, daily_budget, portfolio_id
  FROM `onyga-482313.OI.V_DIM_CAMPAIGN_CURRENT`
  QUALIFY ROW_NUMBER() OVER (PARTITION BY CAST(campaign_id AS STRING)
                             ORDER BY effective_from DESC, campaign_name) = 1
),
ks AS (
  SELECT s.*, b.book
  FROM `onyga-482313.OI.FACT_KEYWORD_STATE` s
  JOIN snap ON s.snapshot_date = snap.d
  JOIN books b ON b.family = s.family
  JOIN camp c ON c.cid = CAST(s.campaign_id AS STRING)
  WHERE NOT COALESCE(s.is_brand_defense, FALSE)
    AND s.state != 'LAUNCH_CONTAINED'
    AND UPPER(COALESCE(c.campaign_state, 'ENABLED')) = 'ENABLED'
),
-- the window record, PER DAY, so each day can be corrected at its own age (P-14a)
fdays AS (
  SELECT CAST(f.campaign_id AS STRING) AS cid,
         CAST(f.keyword_id AS STRING)  AS kid,
         f.date,
         f.campaign_type               AS ch,
         SUM(f.Ads_cost)     AS sp,
         SUM(f.Ads_clicks)   AS clk,
         SUM(f.Ads_orders)   AS ord,
         SUM(f.GROSS_PROFIT) AS gp
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` f
  CROSS JOIN win
  WHERE f.date BETWEEN win.window_from AND win.window_to
    AND f.keyword_id IS NOT NULL
  GROUP BY 1, 2, 3, 4
),
rec AS (
  SELECT d.cid, d.kid,
         SUM(d.sp)  AS w_sp,
         SUM(d.clk) AS w_clk,
         SUM(d.ord) AS w_ord,
         SUM(d.gp)  AS w_gp,
         -- P-14a: the magnitude-weighted effective factor (see the header). COALESCE to 1.0 so a
         -- missing curve row can never drop a day out of the sum.
         SUM(ABS(d.gp))                                             AS w_absgp,
         SUM(SAFE_DIVIDE(ABS(d.gp), COALESCE(sc.sales_completion, 1.0))) AS w_absgp_corrected,
         MIN(COALESCE(sc.sales_completion, 1.0))                    AS settle_factor_min,
         LOGICAL_AND(COALESCE(sc.curve_available, FALSE))           AS settle_curve_available,
         MIN(DATE_DIFF(t.d_la, d.date, DAY))                        AS min_age_days
  FROM fdays d
  CROSS JOIN today t
  LEFT JOIN `onyga-482313.OI.V_PLAN_SETTLE_COMPLETION` sc
    ON sc.channel = d.ch
   AND sc.age_days = LEAST(DATE_DIFF(t.d_la, d.date, DAY), 120)
  GROUP BY 1, 2
),
-- P-14b memory: what the LIVE plan said last night. Empty on the first night, by design.
prior AS (
  SELECT CAST(campaign_id AS STRING) AS cid, CAST(keyword_id AS STRING) AS kid,
         LOGICAL_OR(side = 'GOOD') AS prior_good
  FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK`
  WHERE is_live_plan
    AND as_of = (SELECT MAX(as_of) FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK`
                 WHERE is_live_plan AND as_of < (SELECT d_la FROM today))
  GROUP BY 1, 2
),
probes AS (
  SELECT DISTINCT CAST(keyword_id AS STRING) AS kid FROM `onyga-482313.OI.T_LIFT_PROBES`
),
seatecon AS (
  SELECT CAST(campaign_id AS STRING) AS cid, CAST(keyword_id AS STRING) AS kid,
         MAX(seat_cpc) AS seat_cpc, MAX(bid_park) AS bid_park
  FROM `onyga-482313.OI.T_OOB_SEAT_ECONOMICS`
  GROUP BY 1, 2
),
holdout AS (
  SELECT CAST(unit_id AS STRING) AS cid, MIN(eligible_from) AS eligible_from
  FROM `onyga-482313.OI.DE_HOLDOUT_ASSIGNMENT`
  WHERE unit_type = 'CAMPAIGN' AND arm = 'HOLDOUT'
  GROUP BY 1
),
base AS (
  SELECT
    ks.family, ks.book,
    CAST(ks.campaign_id AS STRING) AS campaign_id, ks.campaign_name,
    CAST(ks.keyword_id AS STRING)  AS keyword_id,
    CAST(ks.ad_group_id AS STRING) AS ad_group_id,
    ks.target_text, ks.match_type, ks.channel,
    COALESCE(ks.is_auto, FALSE) AS is_auto, COALESCE(ks.is_pt, FALSE) AS is_pt,
    COALESCE(ks.is_brand_defense, FALSE) AS is_brand_defense,
    ks.state AS ladder_state, ks.current_bid, ks.affordable_bid, ks.bid_floor,
    ks.gp_per_click, ks.settled_ord90, ks.settled_gp90, ks.settled_sp90,
    COALESCE(ks.family_bar, 1.0) AS family_bar,
    win.calendar_state, win.window_days, win.window_from, win.window_to, win.watermark,
    win.allowance_share, win.ramp_steps, win.live_plan,
    cp.daily_budget AS campaign_current_budget, cp.portfolio_id,
    COALESCE(rec.w_sp, 0)  AS w_sp,
    COALESCE(rec.w_clk, 0) AS w_clk,
    COALESCE(rec.w_ord, 0) AS w_ord,
    COALESCE(rec.w_gp, 0)  AS w_gp,
    COALESCE(SAFE_DIVIDE(rec.w_absgp, NULLIF(rec.w_absgp_corrected, 0)), 1.0) AS settle_factor_eff,
    COALESCE(rec.settle_factor_min, 1.0) AS settle_factor_min,
    -- vacuously TRUE when the window holds no day for this keyword: "every day of this window had
    -- a factor" is true of an empty window, and reading it as FALSE would label a keyword that
    -- simply did not serve as one the curve could not answer for — two different things.
    COALESCE(rec.settle_curve_available, TRUE) AS settle_curve_available,
    rec.min_age_days,
    COALESCE(pr.prior_good, FALSE) AS prior_good,
    (pb.kid IS NOT NULL) AS is_probe,
    se.seat_cpc, se.bid_park,
    (h.cid IS NOT NULL AND t.d_la >= h.eligible_from) AS holdout,
    h.eligible_from AS holdout_eligible_from,
    IF(ks.channel = 'SB', caps.settle_days_sb, caps.settle_days_sp) AS settle_days,
    win.min_orders, caps.cap_up, caps.cap_down, caps.raise_ceiling, caps.click_goal_day,
    t.d_la AS today_la
  FROM ks
  CROSS JOIN win
  CROSS JOIN caps
  CROSS JOIN today t
  LEFT JOIN camp cp ON cp.cid = CAST(ks.campaign_id AS STRING)
  LEFT JOIN rec ON rec.cid = CAST(ks.campaign_id AS STRING) AND rec.kid = CAST(ks.keyword_id AS STRING)
  LEFT JOIN prior pr ON pr.cid = CAST(ks.campaign_id AS STRING) AND pr.kid = CAST(ks.keyword_id AS STRING)
  LEFT JOIN probes pb ON pb.kid = CAST(ks.keyword_id AS STRING)
  LEFT JOIN seatecon se ON se.cid = CAST(ks.campaign_id AS STRING) AND se.kid = CAST(ks.keyword_id AS STRING)
  LEFT JOIN holdout h ON h.cid = CAST(ks.campaign_id AS STRING)
),
derived AS (
  SELECT b.*,
    SAFE_DIVIDE(b.w_gp, b.settle_factor_eff)          AS w_gp_corrected,
    SAFE_DIVIDE(b.w_gp, NULLIF(b.w_sp, 0))            AS ret_raw,
    SAFE_DIVIDE(SAFE_DIVIDE(b.w_gp, b.settle_factor_eff), NULLIF(b.w_sp, 0)) AS ret_corrected,
    DATE_ADD(b.window_to, INTERVAL b.settle_days DAY) AS settle_due_on,
    (DATE_DIFF(b.today_la, b.window_to, DAY) >= b.settle_days) AS settled,
    -- the ladder's own settled record, the bootstrap half of "was good" (P-14b)
    (COALESCE(b.settled_ord90, 0) >= b.min_orders
     AND COALESCE(SAFE_DIVIDE(b.settled_gp90, NULLIF(b.settled_sp90, 0)), 0) >= b.family_bar)
      AS ladder_settled_good,
    -- P-6: the repaired price. Cap three 5% steps either way, floor at the row's own floor,
    -- ceiling the house $2.00 on a raise.
    LEAST(
      GREATEST(
        LEAST(
          GREATEST(COALESCE(b.affordable_bid, b.current_bid), b.current_bid * (1 - b.cap_down)),
          b.current_bid * (1 + b.cap_up)),
        COALESCE(b.bid_floor, 0)),
      GREATEST(b.raise_ceiling, b.current_bid))            AS planned_bid_raw
  FROM base b
),
sided AS (
  SELECT d.*,
    (d.w_ord >= d.min_orders AND COALESCE(d.ret_raw, -1)       >= d.family_bar) AS good_raw,
    (d.w_ord >= d.min_orders AND COALESCE(d.ret_corrected, -1) >= d.family_bar) AS good_corrected,
    (d.prior_good OR d.ladder_settled_good)                                     AS was_good
  FROM derived d
),
judged AS (
  SELECT s.*,
    CASE
      WHEN s.good_corrected THEN 'GOOD'
      WHEN s.was_good AND NOT s.settled THEN 'HELD_UNSETTLED'
      WHEN s.w_ord < s.min_orders AND s.ladder_state IN ('WINNER', 'PACED_WINNER') THEN 'GRACE'
      WHEN s.w_ord >= s.min_orders THEN 'LOSING'
      WHEN s.w_ord = 1 THEN 'ONE_ORDER'
      WHEN s.w_sp > 0 OR s.w_clk > 0 THEN 'NO_SALE'
      ELSE 'NOT_SERVING'
    END AS verdict
  FROM sided s
),
final AS (
  SELECT j.*,
    IF(j.verdict IN ('GOOD', 'HELD_UNSETTLED', 'GRACE'), 'GOOD', 'NOT_GOOD') AS side_b,
    IF(j.ladder_state IN ('WINNER', 'PACED_WINNER', 'AT_BAR', 'TRIAL', 'PENDING_SETTLE',
                          'REVIVED_SETTLING'), 'GOOD', 'NOT_GOOD')           AS side_a,
    CASE
      WHEN j.verdict = 'HELD_UNSETTLED' THEN 'P-14b'
      WHEN j.verdict = 'GRACE'          THEN 'P-5'
      ELSE 'P-3'
    END AS decided_by,
    CASE
      WHEN j.verdict = 'HELD_UNSETTLED'                     THEN 'HELD_UNSETTLED'
      -- nothing was read, so nothing was corrected and nothing is in flight: a keyword that took
      -- no clicks in the window has no sales arriving later and its empty record is already final.
      -- (The reprice book says the same thing in words on its NOT SERVING rows.)
      WHEN j.w_sp = 0 AND j.w_clk = 0 AND j.w_gp = 0        THEN 'SETTLED'
      WHEN NOT j.settle_curve_available                     THEN 'UNCORRECTED_NO_CURVE'
      WHEN j.good_corrected AND NOT j.good_raw              THEN 'PROMOTED_ON_FRESH'
      WHEN j.settled                                        THEN 'SETTLED'
      ELSE 'CORRECTED'
    END AS settle_arm,
    -- P-6: seat cost = spend at the repaired price, per day
    CASE
      WHEN j.w_sp > 0 AND COALESCE(j.current_bid, 0) > 0
        THEN (j.w_sp / j.window_days) * SAFE_DIVIDE(j.planned_bid_raw, j.current_bid)
      WHEN j.is_probe
        THEN COALESCE(j.seat_cpc, j.bid_floor, 0) * j.click_goal_day
      ELSE 0
    END AS seat_cost_per_day,
    -- P-7: dollars at stake x closeness to the bar
    (j.w_sp / j.window_days) * COALESCE(SAFE_DIVIDE(j.ret_corrected, NULLIF(j.family_bar, 0)), 0)
      AS rank_score
  FROM judged j
)
SELECT
  f.family, f.book, f.campaign_id, f.campaign_name, f.keyword_id, f.ad_group_id,
  f.target_text, f.match_type, f.channel, f.is_auto, f.is_pt, f.is_brand_defense,
  f.portfolio_id, f.campaign_current_budget,
  f.calendar_state, f.window_days, f.window_from, f.window_to, f.watermark,
  f.allowance_share, f.ramp_steps, f.live_plan, f.min_orders,
  f.w_clk, f.w_ord, f.w_sp, f.w_gp, f.w_gp_corrected,
  f.settle_factor_min, f.settle_factor_eff, f.settle_curve_available, f.min_age_days,
  f.settled, f.settle_due_on, f.settle_days, f.settle_arm, f.decided_by, f.was_good,
  f.family_bar, f.ret_raw, f.ret_corrected, f.good_raw, f.good_corrected,
  f.ladder_state, f.verdict, f.side_b, f.side_a,
  (f.side_b = 'NOT_GOOD' AND NOT f.holdout
   AND (f.verdict != 'NOT_SERVING' OR f.is_probe)) AS is_candidate,
  f.rank_score,
  f.current_bid, f.bid_floor, f.bid_park,
  ROUND(f.planned_bid_raw, 2) AS planned_bid,
  ROUND(f.seat_cost_per_day, 4) AS seat_cost_per_day,
  f.is_probe, f.holdout, f.holdout_eligible_from,
  -- the plain sentence, printed on the book, the panel and the brief
  CASE f.verdict
    WHEN 'GOOD' THEN FORMAT(
      'GOOD on the window — %d orders on $%.2f of ad spend from %t to %t, returning %.2f gross-profit dollars per ad dollar against the %s bar of %.2f. The good side is never cut and is not re-priced (P-4).',
      f.w_ord, f.w_sp, f.window_from, f.window_to, COALESCE(f.ret_corrected, 0), f.family, f.family_bar)
    WHEN 'HELD_UNSETTLED' THEN FORMAT(
      'HELD — this keyword was good and its window (%t to %t) has not settled yet, so it is not demoted today (P-14b). %s sales accrue for %d days; it is judged again on %t with no guard.',
      f.window_from, f.window_to, f.channel, f.settle_days, f.settle_due_on)
    WHEN 'GRACE' THEN FORMAT(
      'GRACE — the ladder calls this a settled winner (%s) and its window is quiet (%d order(s) on $%.2f). A proven winner keeps the good side for one quiet window (P-5), held, not cut.',
      f.ladder_state, f.w_ord, f.w_sp)
    WHEN 'LOSING' THEN FORMAT(
      'LOSING on the window — %d orders on $%.2f of ad spend returning %.2f per ad dollar, under the %s bar of %.2f. It competes for a seat at the repaired price $%.2f.',
      f.w_ord, f.w_sp, COALESCE(f.ret_corrected, 0), f.family, f.family_bar, ROUND(f.planned_bid_raw, 2))
    WHEN 'ONE_ORDER' THEN FORMAT(
      'WAITING, one order — one order on $%.2f of ad spend is not evidence whatever the return, so this keyword is on the not-good side and competes for a seat at $%.2f.',
      f.w_sp, ROUND(f.planned_bid_raw, 2))
    WHEN 'NO_SALE' THEN FORMAT(
      'NO SALE — $%.2f of ad spend and %d clicks from %t to %t bought nothing. It competes for a seat at $%.2f; if it does not get one it queues at the park price.',
      f.w_sp, f.w_clk, f.window_from, f.window_to, ROUND(f.planned_bid_raw, 2))
    ELSE FORMAT(
      'NOT SERVING — no spend and no clicks from %t to %t. There is nothing to repair and nothing arriving later, so it competes for a seat only if the probe list nominates it.',
      f.window_from, f.window_to)
  END AS sentence,
  CASE
    WHEN f.w_sp = 0 AND f.w_clk = 0 AND f.w_gp = 0 THEN 'nothing was corrected and nothing is arriving: a keyword that took no clicks in the window has no sales in flight, so the settle question does not arise for this row (P-14a)'
    ELSE CASE f.settle_arm
    WHEN 'PROMOTED_ON_FRESH'    THEN 'the settle correction promoted it: uncorrected it read under the bar, corrected for the sales still arriving it reads at or above it (P-14a)'
    WHEN 'HELD_UNSETTLED'       THEN 'the asymmetric guard decided it: promotion is allowed on fresh evidence, demotion waits for the window to settle (P-14b)'
    WHEN 'UNCORRECTED_NO_CURVE' THEN 'the settle curve could not answer for this channel and age, so nothing was corrected and the guard alone protects this row (P-14a)'
    WHEN 'SETTLED'              THEN 'the window has settled, so the record is read exactly as it stands, with no correction and no guard'
    ELSE 'the window record was corrected for the sales still arriving, using the published settle curve (P-14a)'
    END
  END AS settle_arm_sentence
FROM final f
-- house rule: a total ordering, reaching the keyword key
ORDER BY f.family, f.side_b, f.rank_score DESC, f.w_clk DESC, f.campaign_id, f.keyword_id;
