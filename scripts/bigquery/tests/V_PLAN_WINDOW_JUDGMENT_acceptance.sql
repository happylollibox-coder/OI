-- =============================================================================================
-- V_PLAN_SETTLE_COMPLETION + V_PLAN_WINDOW_JUDGMENT acceptance — v27.135 (2026-08-23); C06
-- restated 2026-10-02 for P-14c (see C06 below); C12 / C22 restated and G1..G4 added 2026-10-02
-- for the judge's memory, v27.156 (see the v27.156 block below).
-- EVERY ROW MUST READ PASS.
--   bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "$(grep -v '^--' FILE)"
-- Spec: docs/superpowers/specs/2026-08-23-next-week-money-plan-design.md P-1, P-3..P-7, P-10, P-14
--       and the §9 guarantees that apply at the JUDGEMENT layer (potting, seating and queueing
--       are Task 2 and are asserted by FACT_PLAN_NEXT_WEEK_acceptance.sql, not here).
--
-- Checks (each is one §9 guarantee or one ruling):
--   C01 P-10 + P-14a: the window is complete days only AND FENCED — window_to = LEAST(watermark-1,
--       CURRENT_DATE('America/Los_Angeles') - 2), the window is exactly window_days long, and no
--       judged day is younger than age 2. The two clauses must be asserted TOGETHER: asserting
--       window_to = watermark - 1 alone goes RED exactly when the fence does its job.
--   C02 §8/P-11: the universe is the HARVEST book, enabled campaigns, no brand defense, no launch.
--   C03 the judgement is a keyword-grain object — one row per (campaign_id, keyword_id).
--   C04 P-9: every row carries a side for BOTH plans and both are declared values.
--   C05 P-14a: the corrected gross profit never flips sign and is never smaller in magnitude than
--       the raw one; the per-day factor floor is in (0, 1]; a row the curve could not answer for
--       says UNCORRECTED_NO_CURVE and carries factor 1.0.
--   C06 P-14b/P-14c, RESTATED 2026-10-02. Until then C06 read P-14b as a VETO: no keyword that
--       was good and served could sit on the not-good side while its window was unsettled. This
--       file was last changed in e007cc5 (v27.138, 2026-08-24), before v27.147 (41d2318, P-14c,
--       ruled by Ori 2026-09-17), and from v27.147 the judge demotes such a row legitimately and
--       publishes why in guard_released_by: HOLD_EXPIRED or LAST_DAY_NOT_STRONG. P-14b/P-14c
--       are a clock and a last-day test, not a veto, so C06 now READS guard_released_by and never
--       re-derives the guard: it counts a row under the guard's preconditions (side_b NOT_GOOD,
--       was_good, served, NOT settled) only when guard_released_by is NULL, UNEXPLAINED or any
--       value outside those two reasons. The HELD_UNSETTLED terms are unchanged: every
--       HELD_UNSETTLED row is on the good side, with a settle-due date in the future AND a
--       window it actually served in. The service clause is the doctrine, not a loophole: the
--       guard exists because sales are still ARRIVING, and a keyword with no clicks in the
--       window has none in flight (v27.134).
--   C07 P-3: a GOOD row has min_orders OBSERVED orders (counts are never inflated) unless the
--       grace or the guard put it there; every row names decided_by.
--   C08 P-6/P-7: every not-good row has a planned price at or above its own floor, a seat cost
--       that is not negative and a rank score that is not NULL.
--   C09 P-14a: the completion curve is monotone in age, above zero and never above 1.
--   C10 P-14a: the correction is exactly ONE published division — corrected x effective factor
--       reconstructs the raw window gross profit, and the effective factor is in (0, 1].
--   C11 every row carries a plain sentence, an arm sentence, a declared settle_arm and a declared
--       park-price source.
--   C12 P-5 as WRITTEN — "one quiet window, held; two quiet windows in a row and rule B stands",
--       asserted on the ARM THAT ANSWERS and not merely on the side. A ladder-settled winner with
--       a quiet window and an unspent grace must read verdict = 'GRACE', and no row reads GRACE
--       with its grace already spent. v27.134 asserted only that such a row was on the good side,
--       which was a tautology under the branch order it shipped: the P-14b guard was tested first
--       and caught 36 of the 39 rows the ruling was written for, so P-5 answered for 3. v27.135
--       tests grace first and C12 now goes red if the guard (or anything else) takes them back.
--   C13 the holdout is never a candidate (house rule, from its eligible_from). NOTE: this check is
--       vacuous whenever no holdout campaign has reached its eligible_from — C15 is the one that
--       bites today, and the two must be read together.
--   C14 P-4: the good side carries NO executable price and NO seat cost. The §9 guarantee "no good
--       keyword has a move" has to be asserted at the layer that PUBLISHES the number, not at the
--       one that consumes it (v27.134: 116 good rows carried a planned_bid, 22 of them a cut).
--   C15 the holdout is named in WORDS wherever a seat is named, at any date. Non-vacuous today:
--       holdout membership is known now and eligible_from is in the future, which is exactly the
--       state C13 cannot see.
--   C16 §4 step 5: every candidate has a park price, at or above its own floor, with a declared
--       source (v27.134: the park price used to be NULL on two thirds of the queue).
--   C17 no arm claims work it did not do — nothing reads CORRECTED with an effective factor of
--       1.0 (the correction scales gross profit and cannot touch a window with none), and nothing
--       reads HELD_UNSETTLED on a window it did not serve in.
--   C18 a seat is promised in WORDS only to a row that actually competes for one. C15 asked only
--       whether the word "holdout" appeared in a sentence that named a seat; it never asked
--       whether the row was a candidate, and the v27.134 seat clause tested holdout membership
--       before it tested service, so 41 dormant keywords were promised a seat their own
--       is_candidate refused them.
--   C19 §9, read honestly: every not-good keyword that is NOT a candidate says so — it takes no
--       seat AND no queue position, and the row says that in words instead of leaving a reader to
--       infer it (195 rows said neither before this check existed).
--   C20 a keyword sitting on the PROTECTED side on a window that took money and sold nothing says
--       so, whichever ruling put it there (P-5 grace or the P-14b guard). Asserting it on the
--       guard alone would let a change to the branch ORDER move the money out from under the
--       disclosure rather than onto it — which is exactly what v27.135's reorder does to 20 rows.
--       "Promotion is allowed on fresh evidence" is a promise the correction cannot keep on a
--       window with no gross profit to scale, and P-4 forbids cutting or re-pricing these rows.
--   C21 P-7's two named factors are each PUBLISHED and their product is the score. The words
--       "dollars at stake x closeness to the bar" describe two independent terms; the arithmetic
--       cancels the spend identically, so the ordering is corrected gross profit alone. The check
--       pins both halves: the factors exist, and rank_score is exactly their product.
--   C22 the GRACE sentence states whether the one-window limit is armed. It is read from
--       FACT_PLAN_NEXT_WEEK; SP_BUILD_NEXT_WEEK_PLAN writes that table nightly, so the flag is
--       FALSE only for a keyword with no partition EARLIER than today and the sentence must name
--       THAT condition — v27.138: it went on saying "no builder writes it until Task 2 ships"
--       after Task 2 had shipped and written a partition, telling Ori the opposite of what the
--       next run does.
--   C23 NEW (v27.138) — the P-14b hold has a CLOCK. was_good reads last night's SIDE and a held
--       row's side is GOOD, while `settled` reads a window that rolls forward nightly, so the
--       guard used to re-arm itself forever: every HELD row must carry the anchor date its hold
--       lifts on, no row may be held past that date, and no expired hold may still read GOOD.
--
-- C06 RESTATEMENT, MEASURED 2026-10-02 (America/Los_Angeles). One script snapshotted the view
-- into a TEMP table (361 rows), numbered it ROW_NUMBER() OVER (ORDER BY campaign_id,
-- keyword_id), doctored one row per copy, and ran the restated C06 expression and the old one
-- over every copy:
--   LIVE: 10 rows under the guard's preconditions, all 10 LAST_DAY_NOT_STRONG (0 HOLD_EXPIRED,
--         0 UNEXPLAINED, 0 NULL); 0 HELD_UNSETTLED rows. Old C06 10 (FAIL); restated C06 0.
--   On the lowest-numbered row with a published release (guard_released_by set to):
--     NC1 NULL                                   -> restated C06 1
--     NC2 'UNEXPLAINED'                          -> restated C06 1
--     NC3 'HOLD_EXPRIED' (a misspelt reason)     -> restated C06 1
--     HC4 'HOLD_EXPIRED' (the other legitimate reason) -> restated C06 0
--   The HELD_UNSETTLED terms are VACUOUS on live (0 held rows), so they were run on the
--   lowest-numbered row that served with no published release, set to settle_arm =
--   HELD_UNSETTLED and side_b = GOOD:
--     NC5 settle_due_on = today                       -> restated C06 1
--     NC6 settle_due_on = today + 7, served = FALSE   -> restated C06 1
--     HC7 settle_due_on = today + 7, served left TRUE -> restated C06 0
--   The old C06 read 10 on every copy except NC5 and NC6 (11 each).
--   The whole file run on 2026-10-02 with C06 restated: 23 rows, every one PASS.
--
-- v27.156 (2026-10-02, piece-1 plan Task 2) — THE JUDGE'S MEMORY: C12 and C22 restated, G1..G4 new.
--   C12 RESTATED for P-17 (grace lasts window_days nightly judgments from the night it was
--       granted): the old two terms stand, because prior_grace now means "the run has lasted its
--       window"; a GRACE row must also carry grace_since / grace_window_days / grace_ends_on with
--       tonight inside the run.
--   C22 RESTATED: every GRACE sentence names its last night ("through <grace_ends_on>") and says
--       SPENT-from or NOT ARMED; the v27.135 wording "grace is now SPENT" (one nightly judgment)
--       is gone.
--   G1  P-17 over the live plan's history AND tonight: no GRACE night falls window_days or more
--       nights after its run's first night, the length read from that first night's row. A run
--       starts after a GOOD night, or ON a night whose row records that a gap cleared the grace
--       memory (memory_cleared_by_gap) — the column the judge reads back as a reset.
--   G2  P-18, READ never re-derived: every HELD row names hold_kept_by and the named reason stands
--       on the row (LAST_DAY with last_day_strong; STRONG_DAY_IN_WINDOW with window_from <=
--       hold_strong_day); no other row names one.
--   G3  fix #16: every HELD row carries hold_since, hold_settles_on and hold_strong_day.
--   G4  P-29, computed HERE from the history and FACT_AMAZON_ADS, never from the view's own flag:
--       no honoured memory (a spent grace, a grace run from before tonight, a hold run from before
--       tonight) whose last night is older than today - window_days - 1 has a window, judged by a
--       night that wrote no row for the keyword and ending before tonight's window_from, that
--       reads GOOD (orders at that night's state floor, raw gross profit per ad dollar at the bar).
-- NEGATIVE CONTROLS: scripts/bigquery/tests/check_judge_memory_controls.py runs THIS file's text
-- with the view and the plan table swapped for temp copies, one copy per control (exit 0 = all
-- as expected). Run 2026-10-02 (Los Angeles) on the deployed v27.156 view, exit 0:
--   LIVE: 27 rows, every one 0.
--   G1: NC_G1_RUN_TOO_LONG (fake keyword, GRACE 09-01 window 3, GRACE 09-04) 1; HC_G1_INSIDE
--       (second GRACE 09-03) 0; HC_G1_GOOD_RESET (GRACE 09-01, GOOD 09-02, GRACE 09-04) 0;
--       HC_G1_GAP_RESET (GRACE 09-01, GRACE 09-10 on a night recording a GRACE clear) 0;
--       NC_G1_NO_RESET (the same with no clear) 1; NC_G1_EMPTY_HISTORY 1 (the emptiness term).
--   G2 (lowest-numbered served row made HELD on the good side): NC_G2_STRONG_DAY_OUT (strong day
--       = window_from - 1) 1; HC_G2_STRONG_DAY_IN (strong day = window_from) 0;
--       NC_G2_NO_REASON (hold_kept_by NULL) 1 — it read 0 on the first draft of G2, whose
--       expression went NULL and dropped out of the COUNTIF; COALESCE added, re-run 1;
--       NC_G2_LAST_DAY_WEAK 1; NC_G2_REASON_UNHELD (a non-HELD row naming LAST_DAY) 1.
--   G3: NC_G3_NO_CLOCK (hold_since NULL) 1; HC_G2_STRONG_DAY_IN 0.
--   G4: NC_G4_DOCTORED_GRACE — keyword 193040325034125 (campaign 130115986205897, the lowest key
--       with a live 08-27 row, no GOOD or GRACE since, and a 3-day window ending 08-27..09-15
--       reading GOOD): its 08-27 row made GRACE and its judgement row made to honour a spent
--       grace -> 1; HC_G4_NOT_HONOURED (same history, row untouched) 0; NC_G4_CLEARED_HONOURED
--       (a row the judge cleared tonight made to honour its grace) 1.
--   C12: NC_C12_RUN_OVER (grace_ends_on = yesterday) 1. C22: NC_C22_NO_END_DATE 1.
--   Doctoring a row to HELD also moves C07 and C14 on those copies (a held row on the good side
--   with a price and a sub-floor order count); the harness prints them and does not assert them.
-- G4 IS NOT VACUOUS ON LIVE (same day, its CTEs run with counting SELECTs): 45 honoured memories
-- (43 grace, 2 hold), 18 of them with gap windows, 540 gap windows read, 9 at the order floor,
-- 0 GOOD.
-- =============================================================================================
WITH j AS (SELECT * FROM `onyga-482313.OI.V_PLAN_WINDOW_JUDGMENT`),
sc AS (SELECT * FROM `onyga-482313.OI.V_PLAN_SETTLE_COMPLETION`),
c01 AS (
  SELECT 'C01 complete days only, no day younger than age 2' AS check_name,
         COUNTIF(window_to != LEAST(DATE_SUB(watermark, INTERVAL 1 DAY),
                                    DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL 2 DAY))
                 OR DATE_DIFF(window_to, window_from, DAY) + 1 != window_days
                 OR DATE_DIFF(CURRENT_DATE('America/Los_Angeles'), window_to, DAY) < 2) AS violations
  FROM j
),
c02 AS (
  SELECT 'C02 HARVEST book only, no brand defense, no launch state',
         COUNTIF(book != 'HARVEST' OR is_brand_defense OR ladder_state = 'LAUNCH_CONTAINED')
  FROM j
),
c03 AS (
  SELECT 'C03 one row per campaign x keyword',
         (SELECT COUNT(*) FROM (SELECT campaign_id, keyword_id FROM j GROUP BY 1, 2 HAVING COUNT(*) > 1))
),
c04 AS (
  SELECT 'C04 both plans carry a declared side',
         COUNTIF(side_b NOT IN ('GOOD','NOT_GOOD') OR side_a NOT IN ('GOOD','NOT_GOOD'))
  FROM j
),
c05 AS (
  SELECT 'C05 P-14a correction is honest (sign, magnitude, factor range, no-curve label)',
         COUNTIF(SIGN(w_gp_corrected) != SIGN(w_gp)
                 OR ABS(w_gp_corrected) < ABS(w_gp) - 0.005
                 OR settle_factor_min <= 0 OR settle_factor_min > 1.0
                 OR (settle_arm = 'UNCORRECTED_NO_CURVE' AND settle_factor_min != 1.0))
  FROM j
),
-- C06, RESTATED 2026-10-02. READS guard_released_by AS PUBLISHED; NEVER RE-DERIVES THE GUARD.
-- A DEMOTION UNDER THE GUARD'S PRECONDITIONS THAT THE JUDGE DID NOT EXPLAIN: a keyword that was
-- good, served and sits on an unsettled window is put on the not-good side on a reason no ruling
-- names. SP_BUILD_NEXT_WEEK_PLAN's P-14b ASSERT counts the NULL case only (it tests IS NULL --
-- read from the procedure, not run here), so an UNEXPLAINED or unrecognised reason goes red
-- here and nowhere in that ASSERT.
-- A HOLD PAST ITS SETTLE-DUE DATE OR ON A WINDOW IT DID NOT SERVE IN: P-4 forbids repricing the
-- good side, so the hold keeps a keyword's price untouched with no clock left, or with no sales
-- in flight to wait for. A HELD ROW OFF THE GOOD SIDE: the row says it is protected while its
-- side says it is not.
c06 AS (
  SELECT 'C06 P-14b/P-14c a demotion under the guard preconditions names the judge release reason; a HELD row is good, served and not yet due',
         COUNTIF((side_b = 'NOT_GOOD' AND was_good AND NOT settled AND served
                  AND COALESCE(guard_released_by, '') NOT IN ('HOLD_EXPIRED', 'LAST_DAY_NOT_STRONG'))
                 OR (settle_arm = 'HELD_UNSETTLED'
                     AND (settle_due_on IS NULL
                          OR settle_due_on <= CURRENT_DATE('America/Los_Angeles')
                          OR side_b != 'GOOD'
                          OR NOT served)))
  FROM j
),
c07 AS (
  SELECT 'C07 P-3 order floor read on observed orders; decided_by always named',
         COUNTIF(decided_by IS NULL
                 OR decided_by NOT IN ('P-3','P-5','P-14b')
                 OR (side_b = 'GOOD' AND w_ord < min_orders AND decided_by NOT IN ('P-5','P-14b')))
  FROM j
),
c08 AS (
  SELECT 'C08 P-6/P-7 candidate price, seat cost and rank are usable',
         COUNTIF(side_b = 'NOT_GOOD'
                 AND (planned_bid IS NULL OR planned_bid < bid_floor - 0.005
                      OR seat_cost_per_day IS NULL OR seat_cost_per_day < 0
                      OR rank_score IS NULL))
  FROM j
),
c09 AS (
  -- an analytic function may not sit inside an aggregate, so the LAG is computed one level down
  SELECT 'C09 the completion curve is monotone in age and never above 1',
         (SELECT COUNTIF(bad) FROM (
            SELECT (sales_completion > 1.0
                    OR sales_completion <= 0
                    OR sales_completion < LAG(sales_completion)
                         OVER (PARTITION BY channel ORDER BY age_days) - 1e-9) AS bad
            FROM sc))
),
c10 AS (
  SELECT 'C10 P-14a the correction is one published division and it reconstructs',
         COUNTIF(settle_factor_eff IS NULL OR settle_factor_eff <= 0 OR settle_factor_eff > 1.0
                 OR ABS(w_gp_corrected * settle_factor_eff - w_gp) > 0.005)
  FROM j
),
c11 AS (
  SELECT 'C11 every row says, in words, which arm decided it',
         COUNTIF(sentence IS NULL OR LENGTH(sentence) < 40
                 OR settle_arm_sentence IS NULL OR LENGTH(settle_arm_sentence) < 40
                 OR settle_arm NOT IN ('SETTLED','CORRECTED','PROMOTED_ON_FRESH',
                                       'HELD_UNSETTLED','NOT_CORRECTABLE_NO_GP',
                                       'UNCORRECTED_NO_CURVE')
                 OR bid_park_source NOT IN ('SEAT_ECONOMICS','BID_FLOOR_FALLBACK','NONE'))
  FROM j
),
c12 AS (
  SELECT 'C12 P-5/P-17 answers for the winner it was written for; a GRACE row is inside its run and grace is never granted once spent',
         COUNTIF((ladder_state IN ('WINNER','PACED_WINNER') AND w_ord < min_orders
                  AND NOT prior_grace AND verdict != 'GRACE')
                 OR (verdict = 'GRACE' AND prior_grace)
                 -- P-17 (v27.156): a GRACE row carries its run, and tonight is inside it
                 OR (verdict = 'GRACE'
                     AND (grace_since IS NULL OR grace_window_days IS NULL OR grace_ends_on IS NULL
                          OR grace_since > CURRENT_DATE('America/Los_Angeles')
                          OR grace_ends_on < CURRENT_DATE('America/Los_Angeles'))))
  FROM j
),
c13 AS (
  SELECT 'C13 the holdout is never a candidate',
         COUNTIF(holdout AND is_candidate)
  FROM j
),
c14 AS (
  SELECT 'C14 P-4 no executable price or seat cost on the good side',
         COUNTIF(side_b = 'GOOD' AND (planned_bid IS NOT NULL OR seat_cost_per_day IS NOT NULL))
  FROM j
),
c15 AS (
  SELECT 'C15 a holdout campaign is never promised a seat in words',
         COUNTIF(holdout_member
                 AND REGEXP_CONTAINS(sentence, r'competes for a seat')
                 AND NOT REGEXP_CONTAINS(sentence, r'(?i)holdout'))
  FROM j
),
c16 AS (
  SELECT 'C16 every candidate has a park price at or above its floor, with a declared source',
         COUNTIF(is_candidate
                 AND (bid_park IS NULL
                      OR bid_park < bid_floor - 0.0001
                      OR bid_park_source = 'NONE'))
  FROM j
),
c17 AS (
  SELECT 'C17 no arm claims work it did not do',
         COUNTIF((settle_arm = 'CORRECTED' AND ABS(settle_factor_eff - 1.0) < 1e-9)
                 OR (settle_arm = 'HELD_UNSETTLED' AND NOT served))
  FROM j
),
c18 AS (
  SELECT 'C18 a seat is promised in words only to a row that competes for one',
         COUNTIF(NOT is_candidate
                 AND REGEXP_CONTAINS(sentence, r'competes for a seat at the repaired price'))
  FROM j
),
c19 AS (
  SELECT 'C19 a not-good keyword with no seat and no queue position says so',
         COUNTIF(side_b = 'NOT_GOOD' AND NOT is_candidate
                 AND NOT REGEXP_CONTAINS(sentence, r'does not compete for a seat'))
  FROM j
),
c20 AS (
  SELECT 'C20 a protected window that sold nothing says it sold nothing',
         COUNTIF(good_side_no_sale AND NOT REGEXP_CONTAINS(sentence, r'SOLD NOTHING'))
  FROM j
),
c21 AS (
  SELECT 'C21 P-7 publishes both named factors and the score is their product',
         COUNTIF(rank_dollars_at_stake IS NULL OR rank_closeness IS NULL
                 OR ABS(rank_score - rank_dollars_at_stake * rank_closeness) > 1e-9)
  FROM j
),
c22 AS (
  SELECT 'C22 the grace sentence names the last night of its run and whether the limit is armed',
         COUNTIF(verdict = 'GRACE'
                 AND NOT (REGEXP_CONTAINS(sentence, r'(NOT ARMED TONIGHT|grace is SPENT)')
                          AND STRPOS(sentence, FORMAT('through %t', grace_ends_on)) > 0))
       + COUNTIF(REGEXP_CONTAINS(sentence, r'no builder writes'))
       -- the v27.135 wording promised ONE nightly judgment of grace; P-17 retired that reading
       + COUNTIF(REGEXP_CONTAINS(sentence, r'grace is now SPENT'))
  FROM j
),
c23 AS (
  SELECT 'C23 P-14b the hold carries a clock: an anchor date, and nothing held past it',
         COUNTIF(verdict = 'HELD_UNSETTLED'
                 AND COALESCE(hold_settles_on, settle_due_on) IS NULL)
       + COUNTIF(verdict = 'HELD_UNSETTLED' AND hold_expired)
       + COUNTIF(hold_expired AND side_b = 'GOOD' AND verdict NOT IN ('GOOD', 'GRACE'))
       + COUNTIF(hold_since IS NOT NULL AND hold_settles_on IS NULL)
  FROM j
),
-- ---------------------------------------------------------------------------------------------
-- G1..G4 (v27.156, piece-1 plan Task 2): THE JUDGE'S MEMORY. hist is the live plan's history
-- before tonight; the clock is the Los Angeles date the plan's as_of is keyed on (plan Task 6
-- moves both to New York).
-- ---------------------------------------------------------------------------------------------
hist AS (
  SELECT CAST(campaign_id AS STRING) AS campaign_id, CAST(keyword_id AS STRING) AS keyword_id,
         as_of, verdict, window_days, window_to, memory_cleared_by_gap
  FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK`
  WHERE is_live_plan AND as_of < CURRENT_DATE('America/Los_Angeles')
),
-- G1: every keyword-night of the history and tonight; a GRACE run starts at the first GRACE after
-- the latest reset at or before that night (a GOOD night: the run may start the night after; a
-- night whose row records that a gap cleared the grace memory: the run may start that night)
g1_nights AS (
  SELECT campaign_id, keyword_id, as_of, verdict, window_days, memory_cleared_by_gap FROM hist
  UNION ALL
  SELECT campaign_id, keyword_id, CURRENT_DATE('America/Los_Angeles'), verdict, window_days,
         memory_cleared_by_gap
  FROM j
),
g1_seg AS (
  SELECT n.*,
         MAX(CASE WHEN verdict = 'GOOD' THEN DATE_ADD(as_of, INTERVAL 1 DAY)
                  WHEN memory_cleared_by_gap IN ('GRACE', 'GRACE_AND_HOLD') THEN as_of END)
           OVER (PARTITION BY campaign_id, keyword_id ORDER BY as_of
                 ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS reset_from
  FROM g1_nights n
),
g1_run AS (
  SELECT s.*,
         MIN(IF(verdict = 'GRACE', as_of, NULL))
           OVER (PARTITION BY campaign_id, keyword_id, reset_from) AS anchor
  FROM g1_seg s
),
g1 AS (
  SELECT 'G1 P-17 a GRACE run never lasts beyond the window_days in force on the night it was granted',
         COUNTIF(r.verdict = 'GRACE'
                 AND (a.window_days IS NULL OR DATE_DIFF(r.as_of, r.anchor, DAY) >= a.window_days))
       -- emptiness: a run over no history and no judgement passes vacuously
       + IF((SELECT COUNT(*) FROM hist) = 0 OR (SELECT COUNT(*) FROM j) = 0, 1, 0)
  FROM g1_run r
  LEFT JOIN g1_nights a
    ON a.campaign_id = r.campaign_id AND a.keyword_id = r.keyword_id AND a.as_of = r.anchor
),
-- G2: the hold names what keeps it, and the named reason stands on the row (READ, never re-derived)
g2 AS (
  SELECT 'G2 P-18 every HELD row is kept by a very good last day or by the very good day that started it still in the window',
         -- COALESCE: a NULL hold_kept_by must count, not drop out of the COUNTIF (NC_G2_NO_REASON
         -- read 0 on the first draft, which lacked it)
         COUNTIF(verdict = 'HELD_UNSETTLED'
                 AND NOT COALESCE((hold_kept_by = 'LAST_DAY' AND last_day_strong)
                                  OR (hold_kept_by = 'STRONG_DAY_IN_WINDOW'
                                      AND window_from <= hold_strong_day), FALSE))
       + COUNTIF(verdict != 'HELD_UNSETTLED' AND hold_kept_by IS NOT NULL)
  FROM j
),
-- G3: fix #16 — the clock is on the row from the first held night
g3 AS (
  SELECT 'G3 fix #16 every HELD row carries hold_since, hold_settles_on and hold_strong_day',
         COUNTIF(verdict = 'HELD_UNSETTLED'
                 AND (hold_since IS NULL OR hold_settles_on IS NULL OR hold_strong_day IS NULL
                      OR hold_since > CURRENT_DATE('America/Los_Angeles')))
  FROM j
),
-- G4: P-29, computed here from the history and the ads record, not read from the view's own flag.
-- A memory the row honours: a spent grace (prior_grace), a grace run from before tonight
-- (verdict GRACE with grace_since earlier than tonight), or a hold run from before tonight
-- (hold_since earlier than tonight). Its last night: the last GRACE night after the latest grace
-- reset, or the keyword's last plan night for a hold run (a hold run reaches it by construction).
g4_mem AS (
  SELECT j.campaign_id, j.keyword_id, j.window_from, j.window_days, j.family_bar, kind
  FROM j,
  UNNEST(ARRAY_CONCAT(
    IF(j.prior_grace
       OR (j.verdict = 'GRACE' AND j.grace_since < CURRENT_DATE('America/Los_Angeles')),
       ['GRACE'], CAST([] AS ARRAY<STRING>)),
    IF(j.hold_since < CURRENT_DATE('America/Los_Angeles'),
       ['HOLD'], CAST([] AS ARRAY<STRING>)))) AS kind
),
g4_last AS (
  SELECT h.campaign_id, h.keyword_id,
         MAX(h.as_of) AS last_night,
         MAX(IF(h.verdict = 'GRACE' AND (r.grace_from IS NULL OR h.as_of >= r.grace_from),
                h.as_of, NULL)) AS last_grace_night
  FROM hist h
  JOIN (SELECT campaign_id, keyword_id,
               MAX(CASE WHEN verdict = 'GOOD' THEN DATE_ADD(as_of, INTERVAL 1 DAY)
                        WHEN memory_cleared_by_gap IN ('GRACE', 'GRACE_AND_HOLD') THEN as_of END)
                 AS grace_from
        FROM hist GROUP BY 1, 2) r USING (campaign_id, keyword_id)
  GROUP BY 1, 2
),
g4_m AS (
  SELECT m.*, IF(m.kind = 'HOLD', l.last_night, l.last_grace_night) AS m_night
  FROM g4_mem m
  JOIN g4_last l USING (campaign_id, keyword_id)
),
g4_gap AS (
  SELECT m.campaign_id, m.keyword_id, m.kind, m.family_bar, gn,
         DATE_SUB(gn, INTERVAL 2 DAY) AS g_to
  FROM g4_m m
  JOIN hist mh
    ON mh.campaign_id = m.campaign_id AND mh.keyword_id = m.keyword_id AND mh.as_of = m.m_night
  CROSS JOIN UNNEST(GENERATE_DATE_ARRAY(DATE_ADD(m.m_night, INTERVAL 1 DAY),
                                        DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL 1 DAY))) AS gn
  LEFT JOIN hist h ON h.campaign_id = m.campaign_id AND h.keyword_id = m.keyword_id AND h.as_of = gn
  WHERE m.m_night < DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL m.window_days + 1 DAY)
    AND h.as_of IS NULL
    AND DATE_SUB(gn, INTERVAL 2 DAY) > mh.window_to
    AND DATE_SUB(gn, INTERVAL 2 DAY) < m.window_from
),
g4_win AS (
  SELECT g.*, c.window_days AS wd_n, c.min_orders AS min_orders_n
  FROM (SELECT g0.*, `onyga-482313.OI.FN_PLAN_CALENDAR_STATE`(g0.gn) AS st FROM g4_gap g0) g
  JOIN (SELECT calendar_state, window_days, min_orders
        FROM `onyga-482313.OI.DE_PLAN_CONFIG` WHERE is_active
        QUALIFY ROW_NUMBER() OVER (PARTITION BY calendar_state ORDER BY updated_at DESC) = 1) c
    ON c.calendar_state = g.st
),
g4_rec AS (
  SELECT w.campaign_id, w.keyword_id, w.kind, w.g_to, w.min_orders_n, w.family_bar,
         COALESCE(SUM(f.Ads_cost), 0) AS sp, COALESCE(SUM(f.Ads_orders), 0) AS ord,
         COALESCE(SUM(f.GROSS_PROFIT), 0) AS gp
  FROM g4_win w
  LEFT JOIN `onyga-482313.OI.FACT_AMAZON_ADS` f
    ON CAST(f.campaign_id AS STRING) = w.campaign_id AND CAST(f.keyword_id AS STRING) = w.keyword_id
   AND f.date BETWEEN DATE_SUB(w.g_to, INTERVAL w.wd_n - 1 DAY) AND w.g_to
  GROUP BY 1, 2, 3, 4, 5, 6
),
g4 AS (
  SELECT 'G4 P-29 no grace or hold memory is honoured across an unwritten gap whose windows read GOOD',
         COUNT(DISTINCT IF(ord >= min_orders_n
                           AND COALESCE(SAFE_DIVIDE(gp, NULLIF(sp, 0)), -1) >= family_bar,
                           CONCAT(campaign_id, '|', keyword_id, '|', kind), NULL))
  FROM g4_rec
)
SELECT check_name, violations, IF(violations = 0, 'PASS', 'FAIL') AS result
FROM (SELECT * FROM c01 UNION ALL SELECT * FROM c02 UNION ALL SELECT * FROM c03
      UNION ALL SELECT * FROM c04 UNION ALL SELECT * FROM c05 UNION ALL SELECT * FROM c06
      UNION ALL SELECT * FROM c07 UNION ALL SELECT * FROM c08 UNION ALL SELECT * FROM c09
      UNION ALL SELECT * FROM c10 UNION ALL SELECT * FROM c11 UNION ALL SELECT * FROM c12
      UNION ALL SELECT * FROM c13 UNION ALL SELECT * FROM c14 UNION ALL SELECT * FROM c15
      UNION ALL SELECT * FROM c16 UNION ALL SELECT * FROM c17 UNION ALL SELECT * FROM c18
      UNION ALL SELECT * FROM c19 UNION ALL SELECT * FROM c20 UNION ALL SELECT * FROM c21
      UNION ALL SELECT * FROM c22 UNION ALL SELECT * FROM c23
      UNION ALL SELECT * FROM g1 UNION ALL SELECT * FROM g2 UNION ALL SELECT * FROM g3
      UNION ALL SELECT * FROM g4)
ORDER BY check_name;
