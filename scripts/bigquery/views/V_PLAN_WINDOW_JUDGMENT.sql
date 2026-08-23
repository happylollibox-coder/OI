-- =============================================================================================
-- V_PLAN_WINDOW_JUDGMENT — v27.134 (2026-08-23): ONE ROW PER working-family keyword, carrying the
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
-- THE SIDE (P-1, P-3, P-5, P-14). Rule B judges the window, not the ladder's 90-day record. The
-- arms are tested in this order, and the order is doctrine, not taste:
--   GOOD        min_orders orders IN THE WINDOW and window gross profit per ad dollar at or above
--               the family bar. Order COUNTS are read as observed and are never inflated (P-14a:
--               a count cannot be fractionally corrected); the RETURN is read corrected.
--   HELD_UNSETTLED (P-14b) a keyword that WAS good, THAT SERVED IN THE WINDOW, and now reads
--               not-good while its window has not settled (SP 7 / SB 14 complete days after
--               window_to). It keeps the good side, held. Promotion is allowed on fresh evidence;
--               only demotion waits. This is the ASYMMETRY.
--               THE GUARD REQUIRES SERVICE (v27.134 repair). P-14b exists because sales are still
--               ARRIVING. A keyword that took no spend and no clicks in the window has nothing in
--               flight, so there is no unsettled evidence to wait for and the guard has no basis.
--               Before this repair 11 such rows were held on the good side — where P-4 then forbids
--               re-pricing them — while their own settle_arm_sentence said, correctly, that the
--               settle question does not arise for them. Two published sentences contradicted each
--               other on the same row. Service is now a precondition of the guard, and C17 asserts
--               no HELD_UNSETTLED row has an empty window.
--   GRACE (P-5) a ladder-settled winner (WINNER / PACED_WINNER) with a quiet window keeps the good
--               side for ONE window, held. Ordered AFTER the settle guard so a one-window grace
--               budget is not spent while the evidence is still arriving.
--               GRACE IS ONE WINDOW, NOT A STANDING EXEMPTION (v27.134 repair). P-5 reads "two
--               quiet windows in a row and rule B stands". Before this repair the view implemented
--               the grant and not the limit: a settled winner whose window stayed quiet forever
--               kept the good side forever. Grace is now refused when LAST NIGHT'S LIVE PLAN
--               already granted it (prior_grace, read from FACT_PLAN_NEXT_WEEK), which is the
--               second quiet window in a row. On the first nights the table is empty, nobody has
--               spent a grace, and every eligible winner gets one — the correct bootstrap.
--   LOSING / ONE_ORDER / NO_SALE / NOT_SERVING — the not-good side.
-- decided_by names the ruling that decided the row: P-3, P-14b or P-5. settle_arm names what the
-- correction did: SETTLED, CORRECTED, PROMOTED_ON_FRESH, HELD_UNSETTLED, NOT_CORRECTABLE_NO_GP,
-- UNCORRECTED_NO_CURVE.
--
-- AN ARM MUST NOT CLAIM WORK IT DID NOT DO (v27.134 repair, C17). The correction SCALES GROSS
-- PROFIT. A window with no gross profit at all — money spent, clicks taken, nothing sold — cannot
-- be corrected by any factor, because zero divided by anything is zero. Those rows used to fall
-- into the ELSE branch and print "the window record was corrected for the sales still arriving",
-- which was false on every one of them, and they are EXACTLY the population Ori described when he
-- raised the defect. They now carry their own arm, NOT_CORRECTABLE_NO_GP, and say in words that
-- only the order floor (P-3) or the guard (P-14b) can change their side. Read how many there are
-- and what they carry; do not take a number from this header:
--   SELECT settle_arm, COUNT(*) kw, ROUND(SUM(w_sp)/MAX(window_days), 2) sp_day
--   FROM `onyga-482313.OI.V_PLAN_WINDOW_JUDGMENT` GROUP BY 1 ORDER BY 3 DESC;
--
-- "WAS GOOD" (P-14b) is last night's live-plan side IF THE PLAN HAS SEEN THIS KEYWORD, and only
-- otherwise the ladder's own settled record at or above the bar with min_orders settled orders.
-- v27.134 repair: this used to be an unconditional OR, which the header already described as a
-- fallback. The difference is invisible while FACT_PLAN_NEXT_WEEK is empty and decisive once Task 2
-- fills it: under the OR, a keyword the live plan demoted last night would be re-held every night
-- for as long as its 90-day ladder record cleared the bar, so the guard could never be worked off
-- and a demotion could never stick. prior_seen makes last night's plan the authority once it
-- exists, and leaves the ladder as the bootstrap it was always described to be.
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
-- window, and the acceptance (C10) checks that corrected x settle_factor_eff reconstructs the raw
-- figure, so the correction remains ONE published, reversible division a reader can audit. When
-- every day of a window has the same sign this is ALGEBRAICALLY IDENTICAL to the sketch's sum.
--
-- THE GOOD SIDE CARRIES NO PRICE AND NO SEAT COST (P-4, v27.134 repair, C14). P-4 says the good
-- side is never cut and never re-priced. Before this repair the view published planned_bid and
-- seat_cost_per_day on EVERY row, good side included — an executable price sitting one column away
-- from a sentence reading "The good side is never cut and is not re-priced (P-4)", with only
-- is_candidate between that column and a move, and no acceptance check standing over it. Any
-- consumer that joined planned_bid without re-deriving the side would have re-priced good keywords,
-- some of them DOWN. planned_bid and seat_cost_per_day are now NULL whenever side_b = 'GOOD', and
-- C14 asserts it here, at the layer that publishes the number, rather than in Task 2.
--
-- A CONSEQUENCE ORI MUST SEE BEFORE HE RULES ON P-14, and it is not a bug in this file: the window
-- this view judges ALWAYS ends at window_to = today - 2 (the P-14a fence), and a window settles
-- settle_days AFTER window_to, so `settled` is FALSE on every row every night that the ads pipeline
-- is healthy. P-14b therefore does not delay a demotion — under a rolling window it PREVENTS one:
-- a keyword whose record clears its family bar cannot be moved to the not-good side by rule B at
-- all, whatever the window says, and no "judged again with no guard" date ever arrives, because the
-- next night judges a NEW unsettled window. That pulls rule B (P-1: the window decides the side)
-- back towards plan A (the ladder decides).
-- THE GUARD MOVES MONEY IN BOTH DIRECTIONS, AND BOTH BELONG ON THE PAGE (v27.134 disclosure
-- repair). Every earlier account of P-14b named only the first half: money taken OFF the seat
-- queue. But P-2 defines the pot as what the GOOD side actually spent, so the same held keywords
-- also RAISE the pot — and the allowance is a share of the pot. The guard therefore shrinks the
-- queue and enlarges the loss budget that queue is rationing, at the same time, from the same
-- rows. Read BOTH halves before arguing about the guard; the query is in
-- architecture/NEXT_WEEK_MONEY.md §2 under "THE OPEN QUESTION", and it now prints the pot and the
-- allowance guarded and unguarded, per family and for the book. The one-line fix, if Ori wants the
-- guard to be a DELAY and not a veto: demote on the last window that HAS settled (a second window
-- ending settle_days before window_to) while promoting on the fresh one — that is a change to
-- P-14b's evidence, and nobody has made it.
-- NOT EVERY HELD ROW IS WAITING FOR EVIDENCE. Some held keywords already MET the order floor in the
-- window and still read under their family bar on CORRECTED numbers: they are not quiet, they are
-- losing, and the guard holds them anyway. held_despite_evidence is TRUE on exactly those rows and
-- their sentence says so in those words, so the "we do not know yet" reading is not available for
-- money that the window has already spoken about. Count them and their spend with the query above,
-- grouping by held_despite_evidence.
--
-- A KEYWORD THAT DID NOT SERVE is not a keyword the curve failed on. Where the window holds no day
-- for a keyword there is nothing to correct and nothing in flight, so its empty record is already
-- final: the arm is SETTLED and the row says so in words. Reserving UNCORRECTED_NO_CURVE for rows
-- the curve genuinely could not answer keeps that label meaning something — it is the label that
-- tells Ori the plan is resting on the guard alone.
--
-- PLAN A (shadow, P-9) takes the side from the ladder state alone: WINNER, PACED_WINNER, AT_BAR
-- and the waiting states (TRIAL, PENDING_SETTLE, REVIVED_SETTLING) are its good side; REPRICE,
-- LOSER, FLOOR_PROBATION, PARKED and DEAD are not. The amounts are the same window amounts.
--
-- THE REPAIRED PRICE (P-6) is the ladder's affordable_bid, capped at three 5% steps in either
-- direction from the live bid, floored at the row's own bid_floor (the ONE floor definition,
-- FN_BID_FLOOR through the state table) and ceilinged at the house $2.00 for a raise. The cap
-- constants are mirrored from tools/build_reprice_bulksheet.py so the book and the plan cannot
-- price the same keyword differently. It is published on the NOT-GOOD side only (P-4, above).
-- SEAT COST (P-6) is spend at THAT price, not last window's spend: the window's spend per day
-- scaled linearly by the price change (the same linear bid-to-spend guess the seat register uses
-- on its day-one horizon). A candidate with no window spend is priced at the engine's seat
-- economics — seat_cpc times the register's declared click goal per day.
-- THE PARK PRICE has a fallback and says which one it used (v27.134 repair, C16). Spec §4 step 5
-- parks everything that does not win a seat at the channel park price. T_OOB_SEAT_ECONOMICS only
-- knows the keywords that entered OOB seat economics, so before this repair the park price was
-- NULL on most of the queue — a gap Task 2 would have discovered as a NULL, with no honesty column
-- and no check. bid_park now falls back to the row's OWN bid_floor (the house floor definition,
-- already on every row) and is never below it; bid_park_source declares which source answered
-- (SEAT_ECONOMICS / BID_FLOOR_FALLBACK / NONE) exactly as V_PLAN_SETTLE_COMPLETION.curve_available
-- declares it for the curve. bid_park_seat_econ keeps the raw seat-economics value so the coverage
-- gap stays visible and measurable. WHICH park price the plan SHOULD use is still one of Ori's open
-- rulings (spec §8); this repair makes the queue answerable, it does not make the ruling.
-- RANK (P-7) is dollars at stake times closeness to the bar: window spend per day times corrected
-- return over the bar, ties broken by window clicks then by the keyword key (a total ordering).
-- P-7 SCORES ZERO WHEREVER THERE IS NO GROSS PROFIT, which is most of the queue: closeness to the
-- bar is zero when a keyword sold nothing, so a keyword burning real money with no order ranks
-- below every losing keyword and can never be seated for a repair. That is a property of the
-- formula P-7 declares, not of this file, and it is not silently absorbed: rank_is_degenerate is
-- TRUE on every candidate whose rank is zero, and the SOP publishes the count and the dollars it
-- covers. Ori rules whether that is right (park them) or whether the rank needs a term for money
-- burned with no return; until he does, the ordering falls through to clicks and the keyword key.
--
-- CANDIDACY (§4 step 3). A candidate is a not-good keyword that is not in the holdout AND has
-- something to repair: losing, one order, or spend with no sale. A keyword that took no spend and
-- no clicks in the window has no repair to buy and is NOT a candidate unless the probe list
-- nominates it (LIFT's probes stay a candidate SOURCE under P-11). Otherwise every dormant
-- keyword in the book would queue for a zero-cost seat and bury the ranking the seats exist for.
-- THE HOLDOUT IS NAMED IN WORDS, NOT ONLY IN A COLUMN (v27.134 repair, C15). holdout is TRUE only
-- from the campaign's eligible_from, so a holdout campaign judged BEFORE that date is a candidate
-- today and silent tomorrow. The sentence used to promise those rows a seat with no mention of the
-- holdout, and C13 passed only because no campaign was eligible yet — a vacuous check on exactly
-- the arm that would break. holdout_member is TRUE for membership at any date, the sentence names
-- the holdout and its date wherever it names a seat, and C15 asserts it on the live rows today.
--
-- Planner note: every source here is a snapshot table or a small view. The ceiling views are read
-- only through their T_ tables (T_OOB_SEAT_ECONOMICS, T_LIFT_PROBES), per the house rule.
-- Spec: docs/superpowers/specs/2026-08-23-next-week-money-plan-design.md §3, §3a, §4, P-1..P-14.
-- SOP: architecture/NEXT_WEEK_MONEY.md §2.
-- Acceptance: scripts/bigquery/tests/V_PLAN_WINDOW_JUDGMENT_acceptance.sql.
-- =============================================================================================
CREATE OR REPLACE VIEW `onyga-482313.OI.V_PLAN_WINDOW_JUDGMENT`
OPTIONS (description = "v27.134 (2026-08-23): one row per working-family (HARVEST) keyword — the complete-days window from DE_PLAN_CONFIG for today's calendar state, fenced so no judged day is younger than age 2 (P-10 + P-14a), the keyword's record in it raw AND corrected for settle completion via V_PLAN_SETTLE_COMPLETION, the side rule B gives it (P-1/P-3), the P-14b asymmetric guard (promote on fresh evidence, never demote until the window has settled: SP 7 / SB 14 — and the guard now requires that the keyword actually SERVED in the window, because a keyword with no clicks has no sales in flight), the P-5 grace for ladder-settled winners LIMITED to one window (refused when last night's live plan already granted it), the shadow plan A side from the ladder state (P-9), the repaired price capped at three 5% steps and floored at the row's own bid_floor (P-6) published on the NOT-GOOD side only because P-4 forbids re-pricing the good side, the seat cost at that price, the park price with a declared source and a bid_floor fallback, and the P-7 rank with rank_is_degenerate flagging the rows the formula scores at zero. The correction is ONE reversible division by a published effective factor (settle_factor_eff); a window with no gross profit cannot be corrected at all and says so (NOT_CORRECTABLE_NO_GP) instead of claiming a correction. Publishes settle_arm, decided_by, held_despite_evidence and two plain sentences on every row. Judges only; SP_BUILD_NEXT_WEEK_PLAN does the potting, seating and queueing. Spec P-1..P-14, §3a. SOP: architecture/NEXT_WEEK_MONEY.md")
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
-- P-14b memory AND P-5's one-window limit: what the LIVE plan said last night. Empty on the first
-- night, by design. prior_seen is the "if there is one" the header has always promised: once the
-- plan has judged a keyword, last night's plan is the authority on whether it was good, and the
-- ladder is only the bootstrap for a keyword the plan has never seen.
prior AS (
  SELECT CAST(campaign_id AS STRING) AS cid, CAST(keyword_id AS STRING) AS kid,
         TRUE                        AS prior_seen,
         LOGICAL_OR(side = 'GOOD')   AS prior_good,
         LOGICAL_OR(verdict = 'GRACE') AS prior_grace
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
    COALESCE(pr.prior_seen, FALSE)  AS prior_seen,
    COALESCE(pr.prior_good, FALSE)  AS prior_good,
    COALESCE(pr.prior_grace, FALSE) AS prior_grace,
    (pb.kid IS NOT NULL) AS is_probe,
    se.seat_cpc,
    se.bid_park AS bid_park_seat_econ,
    -- P-11 / §4 step 5: the park price always answers, and always says which source answered.
    -- The house floor (FN_BID_FLOOR, already on the row) is the fallback, and the park is never
    -- below it — a bid under the platform minimum is not a price, it is a rejection.
    CASE
      WHEN se.bid_park IS NOT NULL AND ks.bid_floor IS NOT NULL THEN GREATEST(se.bid_park, ks.bid_floor)
      WHEN se.bid_park IS NOT NULL                              THEN se.bid_park
      WHEN ks.bid_floor IS NOT NULL                             THEN ks.bid_floor
      ELSE NULL
    END AS bid_park,
    CASE
      WHEN se.bid_park IS NOT NULL  THEN 'SEAT_ECONOMICS'
      WHEN ks.bid_floor IS NOT NULL THEN 'BID_FLOOR_FALLBACK'
      ELSE 'NONE'
    END AS bid_park_source,
    (h.cid IS NOT NULL AND t.d_la >= h.eligible_from) AS holdout,
    (h.cid IS NOT NULL)                               AS holdout_member,
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
    -- the keyword took money or attention in the window, so it has sales that may still arrive.
    -- This is the precondition of the P-14b guard (see the header).
    (b.w_sp > 0 OR b.w_clk > 0)                       AS served,
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
    -- "if there is one": last night's plan wins once it exists; the ladder is the bootstrap only.
    IF(d.prior_seen, d.prior_good, d.ladder_settled_good)                       AS was_good
  FROM derived d
),
judged AS (
  SELECT s.*,
    CASE
      WHEN s.good_corrected THEN 'GOOD'
      -- P-14b: the guard needs sales in flight, and sales in flight need service.
      WHEN s.was_good AND NOT s.settled AND s.served THEN 'HELD_UNSETTLED'
      -- P-5: one quiet window, and only one — refused if last night's plan already granted it.
      WHEN s.w_ord < s.min_orders AND s.ladder_state IN ('WINNER', 'PACED_WINNER')
           AND NOT s.prior_grace THEN 'GRACE'
      WHEN s.w_ord >= s.min_orders THEN 'LOSING'
      WHEN s.w_ord = 1 THEN 'ONE_ORDER'
      WHEN s.served THEN 'NO_SALE'
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
    -- the guard is holding money the window has already spoken about, not money awaiting evidence
    (j.verdict = 'HELD_UNSETTLED' AND j.w_ord >= j.min_orders) AS held_despite_evidence,
    CASE
      WHEN j.verdict = 'HELD_UNSETTLED'                     THEN 'HELD_UNSETTLED'
      -- nothing was read, so nothing was corrected and nothing is in flight: a keyword that took
      -- no clicks in the window has no sales arriving later and its empty record is already final.
      -- (The reprice book says the same thing in words on its NOT SERVING rows.)
      WHEN NOT j.served AND j.w_gp = 0                      THEN 'SETTLED'
      WHEN NOT j.settle_curve_available                     THEN 'UNCORRECTED_NO_CURVE'
      WHEN j.good_corrected AND NOT j.good_raw              THEN 'PROMOTED_ON_FRESH'
      WHEN j.settled                                        THEN 'SETTLED'
      -- the correction scales gross profit; a window with none cannot be corrected by any factor
      WHEN j.w_gp = 0                                       THEN 'NOT_CORRECTABLE_NO_GP'
      ELSE 'CORRECTED'
    END AS settle_arm,
    -- P-6: seat cost = spend at the repaired price, per day. P-4: NULL on the good side.
    IF(j.verdict IN ('GOOD', 'HELD_UNSETTLED', 'GRACE'), NULL,
      CASE
        WHEN j.w_sp > 0 AND COALESCE(j.current_bid, 0) > 0
          THEN (j.w_sp / j.window_days) * SAFE_DIVIDE(j.planned_bid_raw, j.current_bid)
        WHEN j.is_probe
          THEN COALESCE(j.seat_cpc, j.bid_floor, 0) * j.click_goal_day
        ELSE 0
      END) AS seat_cost_per_day,
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
  f.served, f.prior_seen, f.prior_good, f.prior_grace, f.held_despite_evidence,
  f.family_bar, f.ret_raw, f.ret_corrected, f.good_raw, f.good_corrected,
  f.ladder_state, f.verdict, f.side_b, f.side_a,
  (f.side_b = 'NOT_GOOD' AND NOT f.holdout
   AND (f.verdict != 'NOT_SERVING' OR f.is_probe)) AS is_candidate,
  f.rank_score,
  -- P-7 scores zero wherever there is no gross profit; say so rather than let a seat walk
  -- silently fall through to the tiebreak. See the header and SOP §2.
  (f.side_b = 'NOT_GOOD' AND NOT f.holdout
   AND (f.verdict != 'NOT_SERVING' OR f.is_probe)
   AND f.rank_score = 0) AS rank_is_degenerate,
  f.current_bid, f.bid_floor,
  f.bid_park, f.bid_park_source, f.bid_park_seat_econ,
  -- P-4: the good side carries no executable price and no seat cost
  IF(f.side_b = 'GOOD', NULL, ROUND(f.planned_bid_raw, 2)) AS planned_bid,
  ROUND(f.seat_cost_per_day, 4) AS seat_cost_per_day,
  f.is_probe, f.holdout, f.holdout_member, f.holdout_eligible_from,
  -- the plain sentence, printed on the book, the panel and the brief
  CASE f.verdict
    WHEN 'GOOD' THEN FORMAT(
      'GOOD on the window — %d orders on $%.2f of ad spend from %t to %t, returning %.2f gross-profit dollars per ad dollar against the %s bar of %.2f. The good side is never cut and is not re-priced (P-4), and this row carries no planned price.',
      f.w_ord, f.w_sp, f.window_from, f.window_to, COALESCE(f.ret_corrected, 0), f.family, f.family_bar)
    WHEN 'HELD_UNSETTLED' THEN
      IF(f.held_despite_evidence,
        FORMAT(
          'HELD, BUT THE WINDOW HAS ALREADY SPOKEN — %d orders on $%.2f of ad spend from %t to %t returning %.2f per ad dollar, CORRECTED for the sales still arriving, against the %s bar of %.2f. That is not a keyword waiting for evidence; it is a keyword whose evidence says LOSING. The guard holds it on the good side anyway (P-14b), where P-4 forbids cutting or re-pricing it. The hold does not expire on its own: the plan judges a NEW unsettled window every night, so it lifts only if Ori rules the guard is a delay rather than a veto (spec P-14, the second defect).',
          f.w_ord, f.w_sp, f.window_from, f.window_to, COALESCE(f.ret_corrected, 0), f.family, f.family_bar),
        FORMAT(
          'HELD — this keyword was good and its window (%t to %t) has not settled, so it is not demoted today (P-14b). %s sales accrue for %d days and this window is due to settle on %t. The hold does not expire on its own: the plan judges a NEW unsettled window every night, so it lifts only if Ori rules the guard is a delay rather than a veto (spec P-14, the second defect).',
          f.window_from, f.window_to, f.channel, f.settle_days, f.settle_due_on))
    WHEN 'GRACE' THEN FORMAT(
      'GRACE — the ladder calls this a settled winner (%s) and its window is quiet (%d order(s) on $%.2f). A proven winner keeps the good side for ONE quiet window (P-5), held, not cut. This is that window: a second quiet window in a row and rule B stands.',
      f.ladder_state, f.w_ord, f.w_sp)
    WHEN 'LOSING' THEN FORMAT(
      'LOSING on the window — %d orders on $%.2f of ad spend returning %.2f per ad dollar, under the %s bar of %.2f. ',
      f.w_ord, f.w_sp, COALESCE(f.ret_corrected, 0), f.family, f.family_bar) || f.seat_clause
    WHEN 'ONE_ORDER' THEN FORMAT(
      'WAITING, one order — one order on $%.2f of ad spend is not evidence whatever the return, so this keyword is on the not-good side. ',
      f.w_sp) || f.seat_clause
    WHEN 'NO_SALE' THEN FORMAT(
      'NO SALE — $%.2f of ad spend and %d clicks from %t to %t bought nothing. ',
      f.w_sp, f.w_clk, f.window_from, f.window_to) || f.seat_clause
    ELSE FORMAT(
      'NOT SERVING — no spend and no clicks from %t to %t. There is nothing to repair and nothing arriving later. ',
      f.window_from, f.window_to) || f.seat_clause
  END AS sentence,
  CASE
    WHEN NOT f.served AND f.w_gp = 0 THEN 'nothing was corrected and nothing is arriving: a keyword that took no clicks in the window has no sales in flight, so the settle question does not arise for this row (P-14a)'
    ELSE CASE f.settle_arm
    WHEN 'PROMOTED_ON_FRESH'      THEN 'the settle correction promoted it: uncorrected it read under the bar, corrected for the sales still arriving it reads at or above it (P-14a)'
    WHEN 'HELD_UNSETTLED'         THEN 'the asymmetric guard decided it: promotion is allowed on fresh evidence, demotion waits for the window to settle (P-14b)'
    WHEN 'UNCORRECTED_NO_CURVE'   THEN 'the settle curve could not answer for this channel and age, so nothing was corrected and the guard alone protects this row (P-14a)'
    WHEN 'NOT_CORRECTABLE_NO_GP'  THEN 'the settle correction could NOT help this row and no correction was applied: it scales gross profit and this window has none, so only the order floor (P-3) or the guard (P-14b) can change this side (P-14a)'
    WHEN 'SETTLED'                THEN 'the window has settled, so the record is read exactly as it stands, with no correction and no guard'
    ELSE 'the window record was corrected for the sales still arriving, using the published settle curve (P-14a)'
    END
  END AS settle_arm_sentence
FROM (
  SELECT f2.*,
    -- what happens to this keyword next, in words — and it names the holdout wherever it names a
    -- seat, because holdout membership silences the plan from eligible_from, not from today (C15).
    CASE
      WHEN f2.holdout THEN FORMAT(
        'Its campaign is in the HOLDOUT arm (from %t), so the plan proposes no move for it at all and it does not compete for a seat.',
        f2.holdout_eligible_from)
      WHEN f2.holdout_member THEN FORMAT(
        'It competes for a seat at the repaired price $%.2f today, but its campaign joins the HOLDOUT arm on %t, after which the plan proposes no move for it.',
        ROUND(f2.planned_bid_raw, 2), f2.holdout_eligible_from)
      WHEN f2.verdict = 'NOT_SERVING' THEN
        'It competes for a seat only if the probe list nominates it.'
      ELSE FORMAT(
        'It competes for a seat at the repaired price $%.2f; if it does not get one it queues at the park price %s.',
        ROUND(f2.planned_bid_raw, 2),
        IF(f2.bid_park IS NULL, '(no park price is published for this keyword)',
           FORMAT('$%.2f (%s)', f2.bid_park, f2.bid_park_source)))
    END AS seat_clause
  FROM final f2
) f
-- house rule: a total ordering, reaching the keyword key
ORDER BY f.family, f.side_b, f.rank_score DESC, f.w_clk DESC, f.campaign_id, f.keyword_id;
