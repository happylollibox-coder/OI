-- =============================================================================================
-- V_PLAN_SETTLE_COMPLETION + V_PLAN_WINDOW_JUDGMENT acceptance — v27.135 (2026-08-23); C06
-- restated 2026-10-02 for P-14c (see C06 below); C12 / C22 restated and G1..G4 added 2026-10-02
-- for the judge's memory, v27.156 (see the v27.156 block below); C08 / C18 restated and P1..P3
-- added 2026-10-02 for the judge's prices and ranks, v27.157 (see the v27.157 block below); C22
-- restated 2026-10-03 for the GRACE sentence's anchored rule, v27.165 (follow-up F3, see its block below).
-- v27.160 (2026-10-02, piece-1 plan Task 6, P-24): the NIGHT clocks — C12's grace run, G1's history
-- and tonight, G3, G4's memory and gap nights — read the New York date, the date the view's
-- today_plan and FACT_PLAN_NEXT_WEEK.as_of are keyed on from v27.160; C01's fence and C06's settle
-- date stay on Los Angeles. Measured 2026-10-02 (Los Angeles) on a simulated 22:40 Los Angeles pass
-- (the v27.160 view and builder bodies run with the Los Angeles date 10-02, the New York date 10-03
-- and FN_ADS_ANCHOR_CAP 10-02 written in, on a copy of the plan table, OI._tmp_t6_sim_judge /
-- OI._tmp_t6_sim_plan): this file with those dates written in, 30 rows PASS (job
-- t6_jaccsimn_1790996816, 182.0 slot-seconds); the v27.159 file (every clock Los Angeles) on the same
-- tables, G1 6 and G3 2 FAIL, every other row PASS (job t6_jaccsimo_1790996820) — on a night keyed on
-- New York its Los Angeles "tonight" is the night before. check_judge_memory_controls.py on the
-- deployed v27.160 view and the live history (both dates 10-02, after the first v27.160 CALL): exit
-- 0, LIVE 30 checks 0, all 34 copies as expected (job bqjob_r50cef6748812af44_000001a0ffbb3ea6_1,
-- 7,661.3 slot-seconds).
-- v27.161 (2026-10-02, piece-1 plan Task 7, audit fix #18): C02 RESTATED to test the brand-defense
-- DERIVATION (campaign name or experiment strategy) instead of the is_brand_defense column it used
-- to read (see C02 below). On the deployed v27.160 view over the v27.105 ladder snapshot, C02's CTEs
-- run with j = the view read 5 (the five keywords of 92805659761140, of 361 rows; job
-- bqjob_r14efa745090b29e6_000001a0fff6862f_1); after SP_SNAPSHOT_KEYWORD_STATE v27.161 was deployed
-- and called once, 0 of 356 (job bqjob_r459e37318be25532_000001a1000027cc_1). Both runs read the
-- population term through V_BOOK_ASSIGNMENT (28 both times), before c02_pop moved to j's families.
-- check_judge_memory_controls.py (now one script job: --submit, then --collect) on the deployed
-- view after that CALL, job bqjob_rfd55d4d6239c64c_000001a1000386e3_1, 13,281.6 slot-seconds:
-- exit 0, LIVE 30 checks 0, all 37 doctored copies as expected — the 32 earlier ones unchanged, and
-- NC_C02_DOCTORED_NAME (one row's campaign_name + " (Brand Defense)") 1; HC_C02_PRODUCT_DEFENSE
-- (+ " (Product Defense)") 0; NC_C02_STRATEGY (that row's campaign 104973644967484 added to a
-- BRAND_DEFENSE experiment in a copy of DIM_EXPERIMENT_CAMPAIGN) 9 = its 9 universe rows (the first
-- run expected 1 and read 9; the expectation now reads the campaign's row count); HC_C02_OTHER_STRATEGY
-- (a PRODUCT_DEFENSE experiment) 0; NC_C02_NO_POPULATION (an empty ladder snapshot) 1;
-- NC_EMPTY_JUDGEMENT C02 2 (both emptiness terms).
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
--   C22 the GRACE sentence states whether the grace limit is armed (and, from v27.165, the anchored
--       rule of its own run: see the F3 block). It is read from
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
--
-- v27.157 (2026-10-02, piece-1 plan Task 3) — THE JUDGE'S PRICES AND RANKS: C08 and C18 restated,
-- P1..P3 new. 30 checks.
--   C08 RESTATED for P-19: a price under the row's floor is allowed only where planned_bid_basis is
--       P19_HELD_AT_CURRENT and the price is the current bid (a current bid already under the floor,
--       which P-19 holds rather than raises; 5 such rows on 2026-10-02, none a candidate).
--   C18 RESTATED: the seat promise is matched on "competes for a seat" (P-19 / P-25 seat clauses
--       name "its current price" / "LIFT's PROBE_START bid", not "the repaired price").
--   P1  P-19: no non-probe not-good row under the bar is priced above its current bid or costed
--       above its window spend per day; P19_HELD_AT_CURRENT sits only where it is true; a sentence
--       names P-19 exactly where the label does (candidates).
--   P2  P-20: rank_money_burned is published on every candidate and equals its formula, and the
--       view's deployed ORDER BY ranks by GREATEST(rank_score, 0) then rank_money_burned then
--       clicks (read from INFORMATION_SCHEMA.VIEWS: an ORDER BY leaves no trace on a row).
--   P3  P-25: computed from FACT_ENGINE_PROPOSALS itself — a not-good probe with one LIFT
--       PROBE_START bid is priced at it (capped at GREATEST(2.00, current bid)), costed at
--       click_goal_day x it, and a candidate's sentence names it; a probe with none keeps
--       repair_bid_p6 and says so.
--   Emptiness terms: P1 (no priced non-probe not-good row under the bar), P2 (no candidate without a
--   positive score, or no definition read), P3 (no not-good probe with a LIFT price).
-- NEGATIVE CONTROLS (check_judge_memory_controls.py, which now also swaps
-- `onyga-482313.OI.INFORMATION_SCHEMA.VIEWS` for a copy and inlines each copy as one statement).
-- Run 2026-10-02 14:23 UTC on the deployed v27.157 view, exit 0, LIVE 30 checks all 0, the 17
-- Task 2 controls unchanged, and:
--   NC_P1_RAISED (a P6_REPAIR row under the bar, priced current + $0.05) 1; NC_P1_COST_ABOVE_SPEND
--   1; HC_P1_AT_BAR_RAISED (a row at or above the bar raised) 0; NC_P1_LABEL_DISHONEST (that row
--   labelled P19) 2 (it is a candidate: the label and silent-sentence terms both count it);
--   NC_P1_SENTENCE_SILENT 1; NC_EMPTY_JUDGEMENT P1 1, P2 1, P3 1; NC_P2_SWAPPED (two no-positive
--   candidates of one family, rank_money_burned swapped) 2; NC_P2_ORDER_BY_CLICKS (v27.156's ORDER
--   BY) 1; NC_P3_OLD_FORMULA ($0.21, $0.80 a day) 1; NC_P3_SENTENCE_SILENT 1; NC_P3_NO_PRICE_SILENT
--   (keyword renamed, label left P25) 1; HC_P3_NO_PRICE_SAID 0; NC_C08_UNDER_FLOOR 1;
--   NC_C08_SUBFLOOR_UNLABELLED 1; NC_C18_PROMISE ("competes for a seat at its current price" on a
--   non-candidate) 1. The same script on a snapshot of this body run BEFORE deploy read the same,
--   except P2 one higher on every copy: the deployed definition still ordered by clicks.
-- RUN DIRECTLY ON THE DEPLOYED VIEW, 2026-10-02 14:12 UTC: 30 rows, every one PASS — and it cost
-- 1,180,821 slot-seconds over 624 s (job t3_acc_1790950370; bytes 138,149,433), against 75,686 /
-- 165,826 / 78,252 / 234,068 for the v27.156 file's direct runs earlier the same day: every CTE
-- that reads j re-evaluates the view. The controls script reads the view ONCE into a temp table and
-- ran LIVE and 34 doctored copies for 14,145 slot-seconds; prefer it.
--
-- v27.165 (2026-10-03, piece-1 follow-up F3) — C22 RESTATED: a GRACE sentence must carry the anchored
-- rule of its own run, FORMAT('grace lasts %d nightly judgments (the window length in force when it
-- was granted, %t) through %t', grace_window_days, grace_since, grace_ends_on); no sentence may say
-- "ONE quiet window" or "ONE-WINDOW LIMIT"; a NULL sentence on a GRACE row counts; no GRACE row reads
-- 1 (emptiness). The view's GRACE sentence changed with it (V_PLAN_WINDOW_JUDGMENT v27.165).
-- MEASURED 2026-10-03 (Los Angeles and New York both 10-03), C22's CTE run alone on two snapshots of
-- the deployed view, same data (356 rows, 33 GRACE, 13 of them on a 7-night run granted 09-28 under
-- tonight's 3-day window): the v27.160 view (OI._tmp_f3_judge_old) — restated C22 66 (33 rows without
-- the anchored rule + 33 saying "ONE quiet window"), the v27.156 form of C22 (this file at b0ecc08) 0;
-- the v27.165 view (OI._tmp_f3_judge_new) — restated C22 0, v27.156 form 0.
-- check_judge_memory_controls.py on the deployed v27.165 view, job
-- bqjob_r4f85b3c63fa8c3e1_000001a101194d2f_1 (09:30:02 - 09:34:22 UTC, 15,213.5 slot-seconds): exit 0,
-- LIVE 30 checks all 0, all 40 doctored copies as expected. New: NC_C22_ONE_QUIET_WINDOW (row 20's rule
-- put back to the v27.160 words) 2; NC_C22_WRONG_LENGTH (row 20, a 7-night run, saying 3) 1;
-- NC_C22_NO_GRACE_ROW (every GRACE verdict made GOOD) 1; NC_EMPTY_JUDGEMENT C22 1;
-- NC_C22_NO_END_DATE 1. NC_C12_RUN_OVER also read C22 1 (its doctored grace_ends_on no longer matches
-- the sentence's "through" date); printed, not asserted.
-- The NULL term, run as C22's CTE alone on a copy of OI._tmp_f3_judge_new with the lowest-keyed GRACE
-- row's sentence set to NULL: restated C22 1; the v27.156 form 0 (its NOT (...) went NULL and the
-- COUNTIF dropped the row).
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
-- C02 RESTATED v27.161 (2026-10-02, piece-1 plan Task 7, audit fix #18): it tests the DERIVATION,
-- not the column. Until then it read is_brand_defense, the column the view's universe filter reads,
-- so it passed by construction while BOTTLE-VIDEO/PHRASE (Brand Defense) 92805659761140 sat in the
-- universe (5 rows a night in FACT_PLAN_NEXT_WEEK 09-28 .. 10-02, its ladder flag FALSE). It now
-- counts universe rows whose campaign is brand defense by NAME (the name the row carries, or the
-- campaign dimension's current name) or by the STRATEGY of an experiment it sits in
-- (DIM_EXPERIMENT_CAMPAIGN -> DIM_EXPERIMENT.strategy_id = 'BRAND_DEFENSE'), each read here from its
-- own source, never from the flag. PRODUCT_DEFENSE is not brand defense (spec §8; a ruling).
-- Emptiness: no judgement row reads 1, and no keyword the exclusion acts on — a defense campaign's
-- keyword in the latest ladder snapshot, of a HARVEST family the judgement covers, ENABLED campaign,
-- not LAUNCH_CONTAINED — reads 1 (an empty judgement covers no family, so it reads 2).
c02_def AS (
  SELECT CAST(campaign_id AS STRING) AS campaign_id
  FROM `onyga-482313.OI.V_DIM_CAMPAIGN_CURRENT`
  WHERE REGEXP_CONTAINS(UPPER(campaign_name), r'BRAND DEFENSE')
  UNION DISTINCT
  SELECT CAST(ec.campaign_id AS STRING)
  FROM `onyga-482313.OI.DIM_EXPERIMENT_CAMPAIGN` ec
  JOIN `onyga-482313.OI.DIM_EXPERIMENT` e USING (experiment_id)
  WHERE e.strategy_id = 'BRAND_DEFENSE'
),
-- the HARVEST families are read from the judgement's own book column, not from V_BOOK_ASSIGNMENT:
-- that view processes 77,330,550 bytes a read (bq dry run, 2026-10-02), and the controls script
-- runs this file once per copy — with it, the first two v27.161 control runs cost 19,084.8 and
-- 22,462.4 slot-seconds against 7,661.3 for the v27.160 run (460 / 546 against 206 per copy;
-- 104.3 MB per copy against 65.5); without it, 13,281.6 (303 per copy, 64.9 MB per copy).
c02_pop AS (
  SELECT COUNT(*) AS n
  FROM `onyga-482313.OI.FACT_KEYWORD_STATE` s
  JOIN (SELECT DISTINCT family FROM j WHERE book = 'HARVEST') b ON b.family = s.family
  JOIN `onyga-482313.OI.V_DIM_CAMPAIGN_CURRENT` c
    ON CAST(c.campaign_id AS STRING) = CAST(s.campaign_id AS STRING)
   AND UPPER(COALESCE(c.campaign_state, 'ENABLED')) = 'ENABLED'
  WHERE s.snapshot_date = (SELECT MAX(snapshot_date) FROM `onyga-482313.OI.FACT_KEYWORD_STATE`)
    AND s.state != 'LAUNCH_CONTAINED'
    AND CAST(s.campaign_id AS STRING) IN (SELECT campaign_id FROM c02_def)
),
c02 AS (
  SELECT 'C02 HARVEST book only, no brand defense by campaign name or experiment strategy, no launch state',
         COUNTIF(book != 'HARVEST' OR ladder_state = 'LAUNCH_CONTAINED'
                 OR REGEXP_CONTAINS(UPPER(COALESCE(campaign_name, '')), r'BRAND DEFENSE')
                 OR campaign_id IN (SELECT campaign_id FROM c02_def))
       -- emptiness: no judgement, or no defense keyword the exclusion acts on
       + IF(COUNT(*) = 0, 1, 0)
       + IF((SELECT n FROM c02_pop) = 0, 1, 0)
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
-- C08 RESTATED v27.157: a price under the row's floor is allowed on exactly one kind of row — one
-- where P-19 held a current bid that was ALREADY under the floor (raising it to the floor would be
-- the raise P-19 forbids; holding it uploads nothing). READ from planned_bid_basis; P1 checks the
-- basis is honest.
c08 AS (
  SELECT 'C08 P-6/P-7 candidate price, seat cost and rank are usable',
         COUNTIF(side_b = 'NOT_GOOD'
                 AND (planned_bid IS NULL
                      OR (planned_bid < bid_floor - 0.005
                          AND NOT (planned_bid_basis = 'P19_HELD_AT_CURRENT'
                                   AND ABS(planned_bid - current_bid) <= 0.005))
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
                          OR grace_since > CURRENT_DATE('America/New_York')
                          OR grace_ends_on < CURRENT_DATE('America/New_York'))))
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
-- C18 v27.157: the seat clause no longer always says "at the repaired price" (P-19 names the current
-- price, P-25 LIFT's bid), so the promise is matched on "competes for a seat" alone; a row with no
-- seat says "does not compete", which this does not match.
c18 AS (
  SELECT 'C18 a seat is promised in words only to a row that competes for one',
         COUNTIF(NOT is_candidate
                 AND REGEXP_CONTAINS(sentence, r'competes for a seat'))
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
-- C22 RESTATED v27.165 (2026-10-03, piece-1 follow-up F3): a GRACE sentence states the anchored rule
-- with the row's own run — "grace lasts <grace_window_days> nightly judgments (the window length in
-- force when it was granted, <grace_since>) through <grace_ends_on>" — and no sentence says P-5's "ONE
-- quiet window" or "ONE-WINDOW LIMIT" (through v27.160 every GRACE row said "ONE quiet window"; on
-- 2026-10-03, 13 of the 33 beside a run of 7 nights on a 3-day window). COALESCE: a NULL sentence
-- counts. Emptiness: no GRACE row reads 1.
c22 AS (
  SELECT 'C22 the grace sentence states the anchored rule, names the last night of its run and whether the limit is armed',
         COUNTIF(verdict = 'GRACE'
                 AND NOT COALESCE(REGEXP_CONTAINS(sentence, r'(NOT ARMED TONIGHT|grace is SPENT)')
                                  AND STRPOS(sentence, FORMAT(
                                        'grace lasts %d nightly judgments (the window length in force when it was granted, %t) through %t',
                                        grace_window_days, grace_since, grace_ends_on)) > 0, FALSE))
       + COUNTIF(REGEXP_CONTAINS(sentence, r'no builder writes'))
       -- the v27.135 wording promised ONE nightly judgment of grace; P-17 retired that reading
       + COUNTIF(REGEXP_CONTAINS(sentence, r'grace is now SPENT'))
       -- F3: P-5's one-window wording, retired by P-17's anchored run
       + COUNTIF(REGEXP_CONTAINS(sentence, r'ONE quiet window|ONE-WINDOW LIMIT'))
       -- emptiness: a judgement with no GRACE row tests none of the above
       + IF(COUNTIF(verdict = 'GRACE') = 0, 1, 0)
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
-- before tonight; the clock is the date the plan's as_of is keyed on — the New York date since
-- v27.160 (P-24, piece-1 plan Task 6, which moved as_of, the view's today_plan and every night-clock
-- in this file together: C12's grace run, hist and tonight's night in G1, G3, and G4's memory, gap
-- and nights). The ads clock stays on Los Angeles here as in the view: C01's fence, C06's settle date.
-- ---------------------------------------------------------------------------------------------
hist AS (
  SELECT CAST(campaign_id AS STRING) AS campaign_id, CAST(keyword_id AS STRING) AS keyword_id,
         as_of, verdict, window_days, window_to, memory_cleared_by_gap
  FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK`
  WHERE is_live_plan AND as_of < CURRENT_DATE('America/New_York')
),
-- G1: every keyword-night of the history and tonight; a GRACE run starts at the first GRACE after
-- the latest reset at or before that night (a GOOD night: the run may start the night after; a
-- night whose row records that a gap cleared the grace memory: the run may start that night)
g1_nights AS (
  SELECT campaign_id, keyword_id, as_of, verdict, window_days, memory_cleared_by_gap FROM hist
  UNION ALL
  SELECT campaign_id, keyword_id, CURRENT_DATE('America/New_York'), verdict, window_days,
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
                      OR hold_since > CURRENT_DATE('America/New_York')))
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
       OR (j.verdict = 'GRACE' AND j.grace_since < CURRENT_DATE('America/New_York')),
       ['GRACE'], CAST([] AS ARRAY<STRING>)),
    IF(j.hold_since < CURRENT_DATE('America/New_York'),
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
                                        DATE_SUB(CURRENT_DATE('America/New_York'), INTERVAL 1 DAY))) AS gn
  LEFT JOIN hist h ON h.campaign_id = m.campaign_id AND h.keyword_id = m.keyword_id AND h.as_of = gn
  WHERE m.m_night < DATE_SUB(CURRENT_DATE('America/New_York'), INTERVAL m.window_days + 1 DAY)
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
),
-- ---------------------------------------------------------------------------------------------
-- P1..P3 (v27.157, piece-1 plan Task 3): THE JUDGE'S PRICES AND RANKS.
-- ---------------------------------------------------------------------------------------------
-- P1: P-19, no raise below the bar. A not-good row that is not a probe and whose corrected return
-- is under the bar is never priced above its current bid, and never costed above its window spend
-- per day (the seat cost scales with planned / current). The P19_HELD_AT_CURRENT label is honest:
-- it sits only on a non-probe row under the bar, priced at its current bid, whose P-6 price
-- (repair_bid_p6) was a raise. A sentence names P-19 only on such a row, and every candidate on
-- such a row names it.
p1 AS (
  SELECT 'P1 P-19 no not-good row under the bar is priced above its current bid or costed above its spend',
         COUNTIF(side_b = 'NOT_GOOD' AND NOT is_probe AND COALESCE(ret_corrected, 0) < family_bar
                 AND (planned_bid > current_bid + 0.005
                      OR seat_cost_per_day > w_sp / window_days + 0.0001))
       + COUNTIF(planned_bid_basis = 'P19_HELD_AT_CURRENT'
                 AND NOT COALESCE(NOT is_probe AND COALESCE(ret_corrected, 0) < family_bar
                                  AND ABS(planned_bid - current_bid) <= 0.005
                                  AND repair_bid_p6 > current_bid + 0.005, FALSE))
       + COUNTIF(is_candidate AND planned_bid_basis = 'P19_HELD_AT_CURRENT'
                 AND NOT REGEXP_CONTAINS(sentence, r'\(P-19, Ori 2026-10-02\)'))
       + COUNTIF(REGEXP_CONTAINS(sentence, r'\(P-19')
                 AND planned_bid_basis IS DISTINCT FROM 'P19_HELD_AT_CURRENT')
       -- emptiness: a judgement with no priced not-good row under the bar tests nothing
       + IF(COUNTIF(side_b = 'NOT_GOOD' AND NOT is_probe AND COALESCE(ret_corrected, 0) < family_bar
                    AND planned_bid IS NOT NULL) = 0, 1, 0)
  FROM j
),
-- P2: P-20. Every candidate publishes rank_money_burned = spend per day x (1 - return / bar),
-- floored at 0 — so ordering by it orders by money burned with no return — and the view's own
-- ORDER BY (read from its deployed definition) ranks the candidates with no positive P-7 score by
-- it, ahead of clicks. A view's ORDER BY leaves no trace on a row, so the order is read from the
-- definition, as PLAN_CONFIG_acceptance C10 reads the same view's text for literals.
p2_def AS (
  SELECT view_definition FROM `onyga-482313.OI.INFORMATION_SCHEMA.VIEWS`
  WHERE table_name = 'V_PLAN_WINDOW_JUDGMENT'
),
p2 AS (
  SELECT 'P2 P-20 a candidate with no positive score ranks by money burned with no return, ahead of clicks',
         COUNTIF(is_candidate
                 AND (rank_money_burned IS NULL OR rank_money_burned < 0
                      OR ABS(rank_money_burned
                             - (w_sp / window_days)
                               * GREATEST(0, 1 - COALESCE(ret_corrected, 0) / NULLIF(family_bar, 0)))
                         > 1e-9))
       + (SELECT IF(COUNT(*) = 0, 1,
                    COUNTIF(NOT REGEXP_CONTAINS(view_definition,
                      r'ORDER BY\s+f\.family,\s*f\.side_b,\s*GREATEST\(f\.rank_score,\s*0\)\s+DESC,\s*f\.rank_money_burned\s+DESC,\s*f\.w_clk\s+DESC,\s*f\.campaign_id,\s*f\.keyword_id')))
          FROM p2_def)
       -- emptiness: no candidate without a positive score means the order was not exercised
       + IF(COUNTIF(is_candidate AND rank_score <= 0) = 0, 1, 0)
  FROM j
),
-- P3: P-25, computed from LIFT's own nomination, never from the view's probe_start_bid. A not-good
-- probe whose keyword carries ONE PROBE_START bid in the latest FACT_ENGINE_PROPOSALS snapshot is
-- priced at it, capped at GREATEST(2.00, current bid) — 2.00 is the raise_ceiling the judge's k CTE
-- declares, a constant, not a measurement — and costed at click_goal_day x that price, and a
-- candidate's sentence names the bid. A not-good probe with no such bid keeps P-6's price
-- (repair_bid_p6) and its candidate sentence says LIFT holds none.
p3_lift AS (
  SELECT CAST(keyword_id AS STRING) AS keyword_id, MAX(suggested_bid) AS lift_bid
  FROM `onyga-482313.OI.FACT_ENGINE_PROPOSALS`
  WHERE engine = 'LIFT' AND action = 'PROBE_START'
    AND snapshot_date = (SELECT MAX(snapshot_date) FROM `onyga-482313.OI.FACT_ENGINE_PROPOSALS`)
  GROUP BY 1
  HAVING COUNT(DISTINCT suggested_bid) = 1
),
p3_rows AS (
  SELECT j.*, l.lift_bid,
         LEAST(l.lift_bid, GREATEST(2.00, COALESCE(j.current_bid, 2.00))) AS lift_price
  FROM j LEFT JOIN p3_lift l ON l.keyword_id = j.keyword_id
  WHERE j.side_b = 'NOT_GOOD' AND j.is_probe
),
p3 AS (
  SELECT 'P3 P-25 a probe with a LIFT PROBE_START bid opens at it, capped, and is costed there',
         COUNTIF(lift_bid IS NOT NULL
                 AND NOT COALESCE(planned_bid_basis = 'P25_LIFT_PROBE_START'
                                  AND ABS(planned_bid - ROUND(lift_price, 2)) <= 0.005
                                  AND ABS(seat_cost_per_day - click_goal_day * lift_price) <= 0.0001
                                  AND (NOT is_candidate
                                       OR (STRPOS(sentence, 'PROBE_START bid') > 0
                                           AND STRPOS(sentence, FORMAT('$%.2f', ROUND(lift_price, 2))) > 0)),
                                  FALSE))
       + COUNTIF(lift_bid IS NULL
                 AND NOT COALESCE(planned_bid_basis = 'P6_PROBE_NO_LIFT_PRICE'
                                  AND ABS(planned_bid - repair_bid_p6) <= 0.005
                                  AND (NOT is_candidate
                                       OR STRPOS(sentence, 'no single PROBE_START bid') > 0),
                                  FALSE))
       -- emptiness: no not-good probe carries a LIFT price, so the P-25 arm was not exercised.
       -- Red is then a prompt to read FACT_ENGINE_PROPOSALS (LIFT nominated no PROBE_START bid on a
       -- probe of the plan's universe), not proof of a defect.
       + IF(COUNTIF(lift_bid IS NOT NULL) = 0, 1, 0)
  FROM p3_rows
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
      UNION ALL SELECT * FROM g4
      UNION ALL SELECT * FROM p1 UNION ALL SELECT * FROM p2 UNION ALL SELECT * FROM p3)
ORDER BY check_name;
