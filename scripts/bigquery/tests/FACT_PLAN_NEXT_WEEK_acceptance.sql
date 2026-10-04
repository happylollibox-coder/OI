-- =============================================================================================
-- FACT_PLAN_NEXT_WEEK acceptance — v27.171 (2026-10-03). The spec's §9 guarantees, read on the
-- latest as_of partition (F1 / F2: every night written since the v27.170 deploy; C13: against the
-- judgement that night was built on, T_PLAN_BUILD_JUDGMENT, v27.171). EVERY ROW MUST READ PASS.
--   bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "$(grep -v '^--' FILE)"
-- Spec: docs/superpowers/specs/2026-08-23-next-week-money-plan-design.md §9, P-2, P-4, P-6..P-9,
-- P-12, P-14. Object: scripts/bigquery/procedures/SP_BUILD_NEXT_WEEK_PLAN.sql.
--
-- FOUR CHECKS DEPART FROM THE PLAN'S DRAFT, EACH BECAUSE THE DRAFT WOULD ASSERT SOMETHING THE
-- SPEC DOES NOT SAY (measured against the deployed judgement view before a line of the builder
-- was written; the counts are in the task report, not pinned here):
--   C01 the draft asserted window_to = watermark - 1. That is P-10 WITHOUT the P-14a fence, and
--       it FAILS by construction after 22:00 Los Angeles, when FN_ADS_ANCHOR_CAP() advances and
--       the fence gives up a day. The fence is the house convention, so the check asserts the
--       fence: window_to = LEAST(watermark - 1, as_of - 2) — restated v27.160 to the Los Angeles
--       date of built_at, as_of being the New York date from then (see C01 below).
--   C06 the draft required one of four moves on EVERY not-good row. Spec §9 (v27.135) says the
--       guarantee is about CANDIDATES: a keyword with no spend, no clicks and no probe nomination
--       has nothing to repair, so it takes no seat, no queue position and NO MOVE. The check now
--       reads candidacy, and asserts 'NONE' on the non-candidates rather than a park no one wants.
--   C09 the draft's demotion check omitted the guard's SERVICE clause (v27.134, T1's C17). A
--       keyword that took no spend and no clicks has no sales in flight, so P-14b has no basis
--       and does not fire — and the draft would have failed on exactly those rows.
--   C11 adds the half that protects P-4: a campaign's planned budget may never sit UNDER the
--       good-side spend inside it. A budget cut below the good side is a cut, whatever it is called.
--
-- SIX CHECKS WERE ADDED OR RESTATED IN v27.137, EACH AFTER IT WENT RED ON THE DEPLOYED v27.136
-- PARTITION (the repair pass; the violation counts are in the task report, never pinned here):
--   C10 RESTATED from "every REPRICED seat" to "every SEAT". P-12 says every seat carries a
--       verdict date; the old check asserted the narrowing instead of the ruling, and a seat held
--       at its current price is precisely the parking lot P-12 exists to prevent.
--   C11 GAINS the seats it opened: a campaign's budget may never sit under the spend the plan
--       itself planned inside that campaign (good side + the seats it seated there). Flooring at
--       the good side alone publishes a cap that cannot pay for the plan's own moves.
--   C17 NEW — the plan's seat numbers against DE_FAMILY_SEAT_LEDGER's OPEN rows. A number whose
--       ledger row has closed_on IS NULL has not been freed and may not be reissued to another
--       keyword (§9: "freed numbers reused lowest-first"). C05's uniqueness clause is scoped to
--       the plan's own partition and can never see this.
--   C18 NEW — the seat walk is spec §4.4's FIT TEST, not a prefix stop: after the walk, no queued
--       candidate's seat cost fits the allowance the family has left. A prefix stop halts at the
--       first candidate that does not fit and parks everything behind it, however cheap.
--   C19 NEW — the §9 reconciliation, RESTATED to what the arithmetic can actually guarantee (see
--       the ruling recorded in the SOP): the not-good side's PLANNED spend equals the seats' cost
--       to the cent, and the queue's residual — what parking lowers but does not stop — is
--       published rather than netted to zero and forgotten.
--   C20 NEW — planned_spend_delta_per_day is exactly planned minus current on every row, so a
--       plan that RAISES the not-good side says so in a column and not only in prose.
--   C21 NEW — PAUSE fires only on a keyword the ladder has already closed (§4.5, "paused if
--       already closed"), and a paused row carries no planned bid for a book to upload.
--
-- v27.158 (2026-10-02, piece-1 plan Task 4 — Ori's rulings R1 / R7 / R8 = spec P-15 / P-21 / P-22,
-- audit fixes #11 #12 #15 #24). RESTATED: C03 (the pot counts every GOOD keyword, holdout included),
-- C04 (the ramped allowance is capped at today's not-good spend), C08 (a holdout campaign's cap is
-- not moved, NO_MOVE_HOLDOUT, and every holdout row says it is a measurement control), C11 (the band
-- and the floor at need govern caps the plan MOVES), C15 (pot + not-good = the window spend outside
-- the not-good holdout rows), C16 (ramp_step = LEAST(ramp_steps, plan_uploads_landed)). NEW: M1
-- (allowance <= not-good today), M2 (every cap names its §4.7 rule and follows it), M3 (expected
-- after upload and share_closed recount from the rows). Each restated and new check carries an
-- emptiness term: an empty partition reads 1, not 0.
-- NEGATIVE CONTROLS, run 2026-10-02 (Los Angeles) by scripts/bigquery/tests/check_plan_money_controls.py
-- (this file's own text on doctored copies of the plan's latest two partitions, with the judgement
-- read from the snapshot OI._tmp_t4_judge taken 14:50 UTC: the builder's dry run on that snapshot
-- and the partition the CALL wrote from the deployed view at 15:10 UTC differ only by <= 3e-14 on
-- 12 float columns; exit 0; job bqjob_r6a564fa2d4a74eb9_000001a0fd2fb384_1, 6,729 slot-seconds
-- for LIVE + 20 copies). Run directly on the live partition and the deployed view, 29 rows PASS
-- (job t4_acc_1790953980, 1,247 slot-seconds). Doctored rows were chosen in the live plan B:
--   LIVE: 29 checks, every one 0.
--   NC_EMPTY (no rows): C03 1, C04 1, C08 1, C15 1, C16 1, M1 1, M2 1, M3 1.
--   NC_C03_POT_WITHOUT_HOLDOUT (Bottle's pot put back to v27.157's reading, $0.00): C03 1.
--   NC_C15_NOTGOOD_WITH_HOLDOUT (Bottle's not-good side + its $0.78/day of holdout not-good): C15 1.
--   NC_M1_ABOVE_NOTGOOD (Bottle given the whole target, $6.27 over $0.74 not-good): M1 1, C04 1.
--   NC_C08_HOLDOUT_CAP_MOVED (one holdout row's cap delta +$5.00): C08 1.
--   NC_C08_HOLDOUT_BASIS (one holdout row labelled RAMPED): C08 1.
--   NC_C08_HOLDOUT_SILENT (one GOOD holdout row without "measurement control (HOLDOUT from"): C08 1.
--   NC_C11_MOVED_UNDER_NEED (RAMPED campaign 172872442210536 capped at $1.00): C11 1. LIVE carries 5
--     holdout campaigns whose need is above their unchanged budget, and C11 reads 0 on them.
--   NC_M2_RAMPED_OFF (that campaign's cap + $1.00): M2 1.
--   NC_M2_FLOORED_OFF (FLOORED_AT_NEED campaign 130115986205897's cap + $1.00): M2 1.
--   NC_M2_SENTENCE_SAYS_RAMP (a FLOORED_AT_NEED row saying "the one-third ramp decided it"): M2 1.
--   NC_M3_SEAT_DROPPED (one seat removed): M3 1.
--   NC_M3_QUEUE_DROPPED (the plan's control, one queued row removed): M3 0 — VACUOUS on this
--     partition: every queued candidate is a probe that bought nothing in the window (w_sp 0), so
--     its queue spend is $0.00; NC_M3_QUEUE_UNCOUNTED carries the case.
--   NC_M3_QUEUE_UNCOUNTED (that queued row given $3.00/day more spend than was counted): M3 1.
--   NC_M3_SHARE_OFF (Fresh's share_closed + 0.10 on its live rows): M3 57 (the family term + 56
--     sentences that no longer print it).
--   NC_M3_SENTENCE_SILENT (one row without "Expected after the upload: $"): M3 1.
--   NC_C16_STEP_WITHOUT_UPLOAD (ramp_step 1 with no upload landed): C16 1.
--   NC_C16_SENTENCE (a no-upload row saying "Ramp: step 1"): C16 1.
--   HC_C16_UPLOADS_LANDED (Bottle given 2 landed uploads, step 2 and "Ramp: step 2 of 3" in both
--     plans): C16 0.
--
-- v27.159 (2026-10-02, piece-1 plan Task 5 — Ori's rulings R2 / R6 / R12 / R13 / R15 = spec P-16 /
-- P-20 / P-25 / P-26 / P-28, audit fix #19). RESTATED: C06 and C14 (a seated probe's OPEN_PROBE, an
-- unseated probe's NONE, and a candidate's NONE on nothing else), C12 (OPEN_PROBE under the price
-- ceiling), C17 (the live plan: the register registers plan B's seats), C19 (NONE is a queue move),
-- C23 (number AND occupancy: an incumbent before its date keeps its seat or leaves with
-- LEFT_ALLOWANCE_SHRANK). NEW: T1 (an incumbent keeps its whole contract, or leaves only when the
-- allowance cannot carry it), T2 (seat numbers sticky across an absence), T3 (the question spans the
-- settle horizon), T4 (probes open or take no move, and say so; no row that bought nothing keeps
-- buying clicks), T5 (the builder ranks as the judge orders). Each new check has an emptiness term.
-- The tenure terms are vacuous on the first v27.159 partition by the builder's cutover (no seat
-- written before it carries seat_since); the controls exercise them.
-- RUN 2026-10-02 (Los Angeles) on the live partition written by v27.159 and the deployed view: 34
-- rows PASS (job t5_acc_live_1790990459, 1,513.2 slot-seconds). On the v27.158 partition of the same
-- night (17:03 UTC, judgement snapshot OI._tmp_t5_judge): C14 140, T1 118, T2 1, T3 118, T4 22, T5 61,
-- every other row 0.
-- NEGATIVE CONTROLS, run 2026-10-03 02:01–02:10 UTC by scripts/bigquery/tests/check_plan_seat_controls.py
-- (this file's, PLAN_SEAT_REQUEST_acceptance.sql's and V_ENGINE_HEALTH's c25 own text on doctored,
-- materialized copies of every partition, the latest being the 2026-10-02 partition v27.159 wrote at
-- 01:20 UTC, the judgement read from OI._tmp_t5_judge (C13 reads 0 on LIVE: the partition reproduces
-- it row for row); job bqjob_r4ed37cefafebd407_000001a0ff7ee55d_1, 5,789.9 slot-seconds; exit 0, all
-- 28 copies exercised. A copy whose row to doctor is absent from the partition reads NOT EXERCISED,
-- and the script exits 1):
--   LIVE: 47 readings, every one 0: 34 here, 11 there, and plan_one_move_per_notgood's measured value
--     (HM) and RED status (HS).
--   NC_EMPTY: C23 1, T1 1, T2 1, T3 1, T4 1, T5 1, HS 1.
--   HC_T1_INCUMBENT (a continuing live seat given a coherent contract seated the night before): T1 0,
--     C23 0, T3 0.  NC_T1_PRICE_MOVED (+$0.10): T1 1.  NC_T1_QUESTION_MOVED (+1 click): T1 1.
--   NC_T1_TENURE_WITHOUT_CONTRACT (a NEW seat tagged INCUMBENT): T1 2 (tenure term + sentence term).
--   NC_C23_SEAT_DROPPED (the plan's control: the previous partition holds a seat dated tomorrow, at
--     $0.01 a day, for a keyword tonight's walk queues): C23 1, T1 1.
--   HC_T1_EVICTION_JUSTIFIED (that seat's contract at $1,000 a day, tonight LEFT_ALLOWANCE_SHRANK and
--     "TENURE ENDS EARLY"): C23 0, T1 0.  NC_T1_SHRANK_SILENT (the same without "TENURE ENDS EARLY"):
--     C23 0, T1 1.  NC_T1_EVICTION_UNJUSTIFIED (the justified copy at $0.01 a day): C23 0, T1 1.
--   NC_C23_RENUMBERED (a continuing occupant given number 900): C23 1, T2 1.
--   NC_T2_RETURN_RENUMBERED (a seat back after an absence, its old number honoured, given 901): T2 1.
--   HC_C17_PLAN_A (a plan-A seat given a number the register holds for another keyword): C17 0 (C23
--     and T2 read 1, as they must).  NC_C17_PLAN_B (the same on the live plan): C17 2.
--   NC_T3_CLICKS_DOUBLED (the plan's control): T3 1, S03 1.
--   NC_T4_PROBE_PARKED (an unseated, unserved probe parked with the v27.158 words): T4 1, C14 1.
--   NC_T4_NONE_SILENT (an unseated probe's sentence without "PROBE NOT OPENED TONIGHT; NOTHING
--     UPLOADED"): T4 1.  NC_T4_NONE_PRICED (an unseated probe's NONE with a $0.20 bid): T4 1.
--   NC_T4_OPEN_PROBE_SILENT: T4 1.  NC_C14_PROBE_REPRICED: C14 1.
--   NC_C12_OPEN_PROBE_ABOVE_CEILING (the seated probe priced $0.10 above GREATEST(current bid,
--     $2.00)): C12 1.
--   NC_S07_PROBE_GOAL_NOT_MULTIPLE (the seated probe asking one click more than whole days, its CPC
--     restated so clicks x CPC / horizon still equals its implied spend): S07 1, T3 1, S03 0.
--   NC_C06_NONE_ON_SEAT (a seated non-probe's move NONE): C06 1, C19 1 (NONE is a queue move), HM 1.
--   NC_H_OPEN_PROBE_ON_SEAT (a seated non-probe's move OPEN_PROBE): C14 1, HM 1.
--   NC_C14_PROBE_FLAG_NULL (a seated candidate's is_probe NULL): C14 1.
--   NC_S11_BOGUS_BASIS (a seat's request_basis 'BOGUS'): S11 1, T3 1.
--   NC_T5_RANK_SWAPPED (ranks 1 and 2 of one family): T5 2.
--   NC_S06_HORIZON (a new ordinary seat asking w_clk under HORIZON_WINDOW_RATE): S06 1, T3 1.
--   The script's own guards were controlled the same day on the same job. With the PICK row's
--   probe_open_rn nulled, the four copies that doctor the seated probe read NOT EXERCISED and the
--   script exits 1. With one word of the file's c25 changed, the script reports "the deployed
--   V_ENGINE_HEALTH does not carry this file's c25 text" and exits 1.
--   The first run of the script (commit fef7cd1) had no copy for C12, C19, C14's is_probe term, T1's
--   sentence term, T4's unseated-probe term, S07, S11 or the board. Its four conditional
--   expectations expected 0 when the row they doctor was absent, so a control that tested nothing
--   passed.
--
-- v27.160 (2026-10-02, piece-1 plan Task 6 — Ori's ruling R11 = spec P-24, audit fix #25). RESTATED:
-- C01 (the fence is two days before the LOS ANGELES date of built_at, not before as_of, which is the
-- New York date from v27.160). NEW: K1 (as_of is the New York date of the build on every partition
-- written since the v27.160 deploy, 2026-10-03 02:45:20 UTC), K2 (one calendar state per partition;
-- the latest partition carries its own New York date's state), K3 (no shadow row names a side its
-- side column does not hold; no priced row says it carries no planned price). Each has an emptiness
-- term.
-- RUN 2026-10-02 19:36-19:41 Los Angeles, before deploy: the v27.160 builder body (partition write
-- to a copy, OI._tmp_t6_plan) on the judgement snapshot OI._tmp_t6_judge, K1's cutover set to
-- 02:30 UTC so the copy's partition (built 02:38 UTC) was in scope: 37 rows PASS (job
-- bqjob_r21243ddd93881322_000001a0ffa28d5b_1). The v27.159 partition of 2026-10-02 (built 01:20 UTC,
-- K1's cutover set to 01:00 UTC): K3 244 (118 shadow rows on a side other than the live plan's
-- naming no plan-A side, 110 GOOD rows carrying the not-good side's words, 8 NOT_GOOD rows the good
-- side's, 8 priced rows saying "carries no planned price"), C01 0, K1 0, K2 0 (job
-- bqjob_r6c02f51fa68ccd38_000001a0ffa29e50_1).
-- After deploy, on the live partition the first v27.160 CALL wrote (2026-10-03 02:50:03 UTC): 37 rows
-- PASS (job t6_acc_live1_1790995837, 1,383.0 slot-seconds).
-- NEGATIVE CONTROLS, run 2026-10-03 02:50-02:53 UTC by scripts/bigquery/tests/check_plan_clock_controls.py
-- (this file's and V_ENGINE_HEALTH c23's own text on doctored, materialized copies of every
-- partition, the latest the 2026-10-02 partition of that CALL, the judgement read from the deployed
-- view; job bqjob_r28d04f5d6d9da7e1_000001a0ffabd93a_1, 2,642.4 slot-seconds; exit 0, all 11 copies
-- exercised):
--   LIVE: 39 readings, every one 0 (37 here, and plan_window_complete_days' measured value H23M and
--     RED status H23S).
--   NC_EMPTY: K1 1, K2 1, K3 1, H23S 1.
--   NC_C01_WINDOW_SHIFTED (one live row's window a day earlier, its length kept): C01 1, H23M 1, H23S 1.
--   NC_K1_NOT_NY_DATE (the latest partition stamped as built at 22:40 Los Angeles on its as_of, as a
--     Los Angeles-keyed late pass wrote): K1 1.
--   NC_K2_TWO_STATES (one row given another state): K2 2.
--   NC_K2_REWRITTEN_WHOLE (every row of the latest partition given another state — the 2026-09-30
--     defect): K2 1, from the date term alone.
--   NC_K3_RULE_B_WORDS_ON_GOOD (a plan-A GOOD row given v27.159's sentence: the P-9 prefix + its live
--     row's NOT_GOOD sentence): K3 2.  NC_K3_RULE_B_WORDS_ON_NOT_GOOD (a priced plan-A NOT_GOOD row
--     given v27.159's sentence over a GOOD live row): K3 3.  NC_K3_PRICED_SAYS_NONE: K3 1.
--   NC_K3_FOREIGN_WORDS_SAME_SIDE (a plan-A GOOD row on the live side + "It competes for a seat at
--     $1.00."): K3 1.  NC_K3_NO_SHADOW (no plan-A row): K3 1, C02 1.
-- R11's GUARD, controlled on the builder's own body (the procedure with the plan table swapped for the
-- copy OI._tmp_t6_plan and the judgement for OI._tmp_t6_judge), 2026-10-02 Los Angeles, as_of
-- 2026-10-02: over the copy's BOOST partition of that date it wrote (job
-- bqjob_r6404f94f7c901ee6_000001a0ff9f7e81_1, 627.4 slot-seconds); with that partition set to OFF_PEAK
-- it raised "partition 2026-10-02 was written under OFF_PEAK; tonight reads BOOST; refusing to
-- rewrite (P-24 / R11: ...)" and the OFF_PEAK partition stood, 722 rows, built_at unchanged (job
-- bqjob_r2bb92973bce26f6f_000001a0ffa7a4c2_1, 1,070.2 slot-seconds).
--
-- v27.164 (2026-10-03, piece-1 follow-up F2 — P-16). RESTATED: T1 (an incumbent's cost is its kept
-- price on tonight's window, recounted from the row with click_goal_day read from the judgement; the
-- eviction test reads the same recount) and T3 (implied spend = seat cost on a seat taken tonight
-- only). The file now reads the judgement in two places (C13 and T1's click goal).
-- RUN 2026-10-03, one judgement snapshot OI._tmp_f2_judge (08:48 UTC) under both builder bodies'
-- dry runs (history = the live table before 10-03 + the dry run's 10-03 partition): on the v27.160
-- partition the new T1 reads 99 (69 plan B + 30 plan A incumbents costed by their contract), every
-- other row 0 (job f2_acc_old_1791017575); on the v27.164 partition 37 rows PASS (job
-- f2_acc_new_1791017575), while this file's v27.160 form reads T1 101 and T3 96 there (job
-- f2_accH_new_1791017656). After the v27.164 CALL (job f2_call_1791017831, 08:58 UTC), on the live
-- partition and the deployed view: 37 rows PASS (job f2_acc_live_1791017982, 617.4 slot-seconds,
-- 140,894,039 bytes; the v27.160 form, job f2_accH_live_1791018032: T1 101, T3 96, 5,414.7
-- slot-seconds and the same bytes).
-- NEGATIVE CONTROLS, run 2026-10-03 09:00–09:09 UTC by scripts/bigquery/tests/check_plan_seat_controls.py
-- --judge-table onyga-482313.OI._tmp_f2_judge on every partition, the latest the 10-03 partition of that
-- CALL (job bqjob_r78febaf76288764f_000001a100fdebd9_1, 8,715.2 slot-seconds; exit 0, all 32 copies
-- exercised): LIVE 50 readings 0 (37 here, 11 PLAN_SEAT_REQUEST, HM, HS). The doctored incumbent is
-- LolliME 123153583900193 (plan B), seated 10-02 at $0.70 for $1.3333 a day; on tonight's window at
-- $0.70 it costs $1.57 (a probe's 4 x $0.70 would be $2.80):
--   HC_T1_INCUMBENT (its contract carried on the previous partition, tonight's cost = the recount):
--     T1 0, C23 0, T3 0, S04 0.  NC_T1_PRICE_MOVED: T1 1.  NC_T1_QUESTION_MOVED: T1 1.
--   NC_T1_COST_KEPT_FROM_CONTRACT (contract and tonight's row both at the recount + $0.50, v27.160's
--     rule): T1 1.
--   HC_T1_PROBE_INCUMBENT (made a probe tonight, costed 4 x its kept price): T1 0.
--   NC_T1_PROBE_COSTED_BY_WINDOW (made a probe, costed at its price on the window): T1 1.
--   NC_C23_SEAT_DROPPED (the previous partition seats the queued LolliME probe 207390974307873, dated
--     tomorrow, priced $0.00; tonight queues it): C23 1, T1 1.  HC_T1_EVICTION_JUSTIFIED (priced
--     $1,000,000, tonight LEFT_ALLOWANCE_SHRANK and "TENURE ENDS EARLY"): C23 0, T1 0.
--     NC_T1_SHRANK_SILENT: C23 0, T1 1.  NC_T1_EVICTION_UNJUSTIFIED (priced $0.00): C23 0, T1 1.
--   NC_S04_NEW_SEAT_COST_OFF (a NEW seat's cost + $0.50, LolliME 174400329814141): S04 1, T3 1.
--   NC_EMPTY: S04 1 (its new emptiness term) with C23 T1 T2 T3 T4 T5 HS 1. Every other copy read its
--   expected value (listed above).
--
-- v27.167 (2026-10-03, piece-1 follow-up F8 — P-16). RESTATED: T1 (incumbents leave latest-seated
-- first until the rest fit: in walk 1's order — the previous partition's seat_since, then tonight's
-- rank — no incumbent that left comes before one that kept its seat, the first one that left did not
-- fit what the kept ones leave, and a LEFT_ALLOWANCE_SHRANK sentence says R2's words).
-- RUN 2026-10-03 on the live 10-03 partition (written by v27.164; 0 LEFT_ALLOWANCE_SHRANK rows) and
-- the deployed view: 37 rows PASS (job f8_acc167_live_1791025929, 2,365.3 slot-seconds). On a copy of
-- the judgement snapshot OI._tmp_f8_judge (11:00 UTC) with LolliME's and Fresh's allowance_share 0.25
-- and ramp_steps 1 (OI._tmp_f8_judge_shrunk), under both builder bodies' dry runs (history = the live
-- table before 10-03 + the dry run's 10-03 partition): this form reads 37 PASS on the v27.167
-- partition (job f8_acc167_on_new_shrunk_1791025906) and T1 110 on the v27.164 one (45 incumbents
-- that left before one that kept its seat + 65 TENURE ENDS EARLY sentences in the fit test's words;
-- job f8_acc167_on_old_shrunk_1791025906); the v27.164 form reads T1 59 on the v27.167 partition
-- (later leavers cheap enough to fit the room the kept ones leave; job
-- f8_acc164_on_new_shrunk_1791025906) and 37 PASS on the v27.164 one.
-- NEGATIVE CONTROLS, run 2026-10-03 11:13-11:22 UTC by scripts/bigquery/tests/check_plan_seat_controls.py
-- --judge-table onyga-482313.OI._tmp_f8_judge on every partition, the latest the 10-03 partition
-- (job bqjob_r7aa7d0f7442a1a18_000001a10177bacd_1, 10,719.1 slot-seconds; exit 0, all 35 copies
-- exercised): LIVE 50 readings 0. The eviction copies now doctor a queued row ranked after every kept
-- incumbent of its family (LolliME 207390974307873, rank 56), so its contract dated the night before
-- is the latest seated; NC_C23_SEAT_DROPPED C23 1 T1 1, HC_T1_EVICTION_JUSTIFIED T1 0,
-- NC_T1_SHRANK_SILENT T1 1, NC_T1_EVICTION_UNJUSTIFIED T1 1 as before. New:
--   HC_T1_LATER_LEAVES_BEHIND_EARLIER (that row's contract priced $1,000,000 and a second queued row's,
--     LolliME 273302151474906 at rank 57, priced $0.00, both LEFT_ALLOWANCE_SHRANK): C23 0, T1 0.
--   NC_T1_EARLIER_LEFT_LATER_KEPT (the $1,000,000 contract dated a day before the family's earliest
--     kept incumbent): C23 0, T1 1.
--   NC_T1_SHRANK_OLD_WORDS (the justified eviction in v27.164's sentence): C23 0, T1 1.
--   The v27.164 form of this file on the same three copies (job
--   bqjob_r3e728f553dd863_000001a1017a55a5_1, 1,357.7 slot-seconds): T1 1, 0, 0.
--
-- Follow-up F9 (2026-10-03): NO CHECK CHANGED; M3's control NC_M3_QUEUE_DROPPED (the plan's control) is
-- no longer vacuous. It removed the lowest-numbered queued non-PAUSE row as published; on the 2026-10-02
-- and 2026-10-03 partitions that row had bought nothing in the window ($0.00 queue spend), so it read M3
-- 0 against an expected 0 (the Task 10 proof). check_plan_money_controls.py now injects the money
-- first: HC_M3_QUEUE_COUNTED gives that row $3.00 a day more window spend and restates its plan-B
-- family's expected_after_upload_per_day (+ $3.00 x planned / current bid, 1 with no planned bid),
-- share_closed and both printed figures in every sentence of the family to count it;
-- NC_M3_QUEUE_DROPPED removes the row from that copy. No queued row, or one the injection adds no money
-- to, reads NOT EXERCISED on both (exit 1).
-- RUN on the 2026-10-03 partition (built 08:58:26 UTC by v27.164), judgement snapshot OI._tmp_f8_judge,
-- the script's own text submitted with --nosync (scratchpad wrapper: the script waits synchronously)
-- plus the pre-F9 copy as OLD_..., job bqjob_r25bd2d6619db3273_000001a1019bf35c_1 (11:52:44 - 11:59:20
-- UTC), 120,513.8 slot-seconds (HC_C16_UPLOADS_LANDED alone 50,072.9), 77,265,570 bytes: exit 0, LIVE 37 checks 0, every
-- copy as expected. Injected row: LolliME 207390974307873 (rn 1081, a probe, w_sp $0.00, no planned
-- bid); expected after upload $163.0685 -> $166.0685, share_closed 0.2915 -> 0.2019.
-- HC_M3_QUEUE_COUNTED M3 0 (384.9 slot-seconds; C15 1, C20 1, T5 35 moved, printed: the row's spend
-- moved and nothing else); NC_M3_QUEUE_DROPPED M3 1 (409.4; C13 1, T5 8); the pre-F9 copy on the same
-- job M3 0. M3 alone on copies with the injection moved to the Lollibox queued row (rn 1260, a family
-- with no gap, share_closed NULL): HC 0, NC 1. The guard, controlled: the job's rows re-read with the
-- PICK row's queue_add nulled read both copies NOT EXERCISED and exited 1. The first submission
-- (bqjob_r64c26b87ea73f966_000001a10196bb35_1) inlined the injected copy and failed at it on BigQuery's
-- stage limit; the copy is now materialized once (temp table hq, 1.9 slot-seconds).
--
-- v27.168 (2026-10-03, piece-1 follow-up G1 — P-16). RESTATED: T1's cost recount (inc_cost) branches
-- on the KEPT question's basis — the previous partition's request_basis = 'HORIZON_PROBE_GOAL' costs
-- click_goal_day x kept price, any other basis the kept price on tonight's window — not on tonight's
-- is_probe (v27.164's form). The eviction test reads the same recount.
-- RUN 2026-10-03 (Los Angeles and New York both 10-03), judgement snapshot OI._tmp_g1_judge (12:57 UTC;
-- OI._tmp_g1_judge2, taken with the CALL at 13:03, equal to it to 5.7e-14 on floats):
--   on the live partition (built 13:04:57 UTC by v27.168, job g1_call_1791032624) and the deployed
--   view: 37 rows PASS (job g1_acc_live_1791032787, 1,589.0 slot-seconds, 140,893,843 bytes); the
--   v27.167 form of this file reads T1 1 there, the Fresh incumbent 388620934464557 costed by its window
--   (job g1_accold_live_1791032833, 805.3 slot-seconds).
--   on the v27.167 body's dry run of the same snapshot (history = the live table before 10-03 + that
--   partition, OI._tmp_g1_old): this form reads T1 1 (the same keyword at $1.00 a day), every other
--   row PASS (job g1_acc_new_on_old_1791032862, 236.9 slot-seconds).
-- NEGATIVE CONTROLS: see check_plan_seat_controls.py's header (four G1 copies) and the SOP section
-- "An incumbent is costed by the question it keeps".
--
-- v27.170 (2026-10-03, learning-contract piece 2 Task 3 — Ori's ruling D2 (c)). NEW: F1 (no night
-- written since the v27.170 deploy, 2026-10-03 17:41:54 UTC, INFORMATION_SCHEMA.ROUTINES
-- last_altered, was rewritten after Los Angeles midnight of its as_of; a late first write is
-- allowed — read from the write's own DELETE in INFORMATION_SCHEMA.JOBS_BY_PROJECT: a first write
-- removes nothing) and F2 (every row written since the deploy carries a builder_version, and the
-- deployed builder's on rows written since its deploy). Each has an emptiness term.
-- BEFORE THE FREEZE, F1's text with its cutover set to 2026-10-02 00:00 UTC, on the table as it stood
-- (17:34 UTC): 2 — the 10-02 night (stored write 02:50:03 UTC 10-03, 19:50 Los Angeles; its DELETE
-- removed 722 rows) and the 10-03 night (16:34:13 UTC, 09:34 Los Angeles; 712), both rewrites after
-- Los Angeles midnight of their as_of (job bqjob_r26caffed21880c52_000001a102d4cb72_1, 44.8
-- slot-seconds, 26,042,060 bytes).
-- RUN 2026-10-03 17:51 UTC on the live table and the deployed view: 37 rows PASS, F1 1 and F2 1 from
-- their emptiness terms alone — no night has been written since the deploy (the 10-03 night is
-- frozen; the first is the 10-04 night, at the 05:00 UTC pass of 2026-10-04) — job
-- t3_acc_live_1791049874, 734.4 slot-seconds, 330,785,449 bytes. They read 0 only once that night is
-- written; piece-2 Task 8 re-runs this file.
-- NEGATIVE CONTROLS, run 2026-10-03 17:48-17:51 UTC by scripts/bigquery/tests/check_plan_clock_controls.py
-- --plan-table onyga-482313.OI._tmp_t3_plan --jobs-table-id _tmp_t3_plan --judge-table
-- onyga-482313.OI._tmp_t3_judge: a simulated pass — a copy of the table whose 10-03 night was removed
-- and written again at 17:44:03 UTC (10:44 Los Angeles, its first write, after Los Angeles midnight)
-- by the deployed v27.170 text with the plan table swapped for the copy and the judgement for the
-- snapshot OI._tmp_t3_judge (17:34 UTC); exit 0, all 17 copies exercised (job
-- bqjob_r7d71ccc3fee762d1_000001a102e149e3_1, 5,558.7 slot-seconds, 678,044,832 bytes):
--   LIVE (the late first write): 41 readings 0 (39 here, H23M, H23S).
--   NC_EMPTY: F1 1, F2 1 (with K1 K2 K3 H23S 1).
--   NC_F1_SECOND_WRITE_AFTER_MIDNIGHT (the plan's control: the night's DELETE recorded as removing its
--     712 rows): F1 1.  NC_F1_WRITE_NOT_ON_RECORD (its INSERT removed from the record): F1 1.
--     2026-10-04: this copy read F1 0 on the real 10-04 night (written 05:30:18 UTC = 22:30 Los Angeles
--     the evening before, so a rewrite before midnight); since commit 563a10a it is also restamped
--     00:35 Los Angeles on its own as_of, and reads F1 1 on that night (job
--     bqjob_r7679d928f877cc68_000001a10745edc6_1).
--   HC_F1_REWRITE_BEFORE_MIDNIGHT (that rewrite re-keyed to 10-04 and stamped 22:35 Los Angeles on
--     10-03, its jobs moved with it): F1 0, F2 0.  NC_F1_REWRITE_AT_MIDNIGHT (stamped 00:00 Los Angeles
--     on 10-04): F1 1.
--   NC_F2_NULL (one row NULL): F2 2 (no version, and not the deployed one).  NC_F2_STALE_VERSION (one row
--     'v27.169'): F2 1.
--   Unasserted moves: NC_K1_NOT_NY_DATE and NC_K3_NO_SHADOW also read F1 1 (a night stamped 22:40 Los
--     Angeles has no INSERT in the hour after it; a night with its shadow rows removed no longer has
--     the row count its INSERT wrote).
-- FOLLOW-UP, same day: F1 reads only the nights written in the last 170 days, because
-- INFORMATION_SCHEMA.JOBS keeps 180 days of jobs and an older night would read "not on record" for
-- ever (from about 2027-04-01). Re-run after it: live table 17:57 UTC 37 PASS, F1 1, F2 1 by
-- emptiness (job t3_acc_live2_1791050257, 682.4 slot-seconds, 330,785,449 bytes); the controls, same
-- arguments, exit 0, every reading above unchanged (job bqjob_r60aad232f3626a83_000001a102ea38f4_1,
-- 6,722.0 slot-seconds, 678,044,832 bytes).
--
-- v27.171 (2026-10-03, learning piece 2 Task 3 follow-up 2). C13 RESTATED: it compares the latest
-- night with the judgement that night was BUILT ON (T_PLAN_BUILD_JUDGMENT, written by
-- SP_BUILD_NEXT_WEEK_PLAN v27.171 with the night, keyed on as_of and built_at), not with the live
-- V_PLAN_WINDOW_JUDGMENT, and adds the window and the calendar state to the comparison (see C13).
-- The v27.170 form on the real 10-03 night, against the view at 18:32 UTC: the 05:36:35 UTC write
-- (stored until 08:12, BigQuery time travel) 47, the 16:34:13 UTC write 0 (job
-- c13fix_snap_1791052309, 927.7 slot-seconds, 440,401,920 bytes).
-- SIMULATED 05:00 UTC PASS: a copy of the v27.171 builder wrote the 10-03 night to the copy
-- OI._tmp_c13_plan_old and its judgement to OI._tmp_c13_bj_old, reading OI._tmp_c13_judge_old, the
-- deployed view's text with its Los Angeles date set to 2026-10-02 (window 09-28 .. 09-30; it
-- differs from the stored 05:36:35 write on 3 of 356 live rows, data restated since). On that night
-- the v27.170 form, against the live view (09-29 .. 10-01), reads C13 44 (job
-- c13fix_drift_old_1791052680, 2,196.0 slot-seconds); this form reads C13 0 (job
-- c13fix_drift_new_1791052680, 2,697.2 slot-seconds). Both also read C01 712 and F1 1 there, from the
-- simulation (built_at is 11:34 Los Angeles on 10-03, a window fenced for 10-02; the copy's write is
-- not in FACT_PLAN_NEXT_WEEK's job record).
-- RUN 2026-10-03 18:40 UTC on the live table: 36 rows PASS, C13 1 (the 10-03 night was written at
-- 16:34:13 UTC by v27.169 and no judgement is on record for it), F1 1 and F2 1 (emptiness) — job
-- c13fix_acc_live_1791052823, 2,895.9 slot-seconds, 241,172,480 bytes. The three read 0 only once a
-- night is written by v27.171 (the first is 10-04, at the 05:00 UTC pass of 2026-10-04); not yet run.
-- NEGATIVE CONTROLS, run 2026-10-03 18:40-18:46 UTC by check_plan_clock_controls.py --plan-table
-- onyga-482313.OI._tmp_c13_plan --jobs-table-id _tmp_c13_plan --judge-table
-- onyga-482313.OI._tmp_c13_judge --build-judge-table onyga-482313.OI._tmp_c13_bj: a simulated pass —
-- the copy's 10-03 night removed and written again at 18:38:55 UTC (its first write, after the
-- v27.171 deploy at 18:37:21) by a copy of the deployed v27.171 text, the judgement from the snapshot
-- OI._tmp_c13_judge (18:32 UTC); exit 0, all 25 copies exercised (job
-- bqjob_r2bf99b8d41e5b9f7_000001a10310eb8f_1, 10,134.5 slot-seconds, 3,853,516,800 bytes):
--   LIVE: 41 readings 0.  NC_EMPTY: C13 2 (nothing saved for an empty night, and no live row).
--   NC_C13_VERDICT_MOVED (one live row's verdict changed in the plan) 1; NC_C13_NOT_SAVED (no record)
--   1; NC_C13_OTHER_WRITE (the record stamped one second later) 1; NC_C13_ROW_NOT_SAVED 1;
--   NC_C13_SIDE_DIFFERS 1; NC_C13_CANDIDACY_DIFFERS 1; NC_C13_WINDOW_DIFFERS 1; NC_C13_STATE_DIFFERS 1
--   — no other check moved on any of them. The other copies read as before; C13 now also moves on
--   the copies that re-key or restamp the night (1 on HC_F1_REWRITE_BEFORE_MIDNIGHT,
--   NC_F1_REWRITE_AT_MIDNIGHT and NC_K1_NOT_NY_DATE: no record for the new key) or change its window
--   or state (NC_C01_WINDOW_SHIFTED 1, NC_K2_TWO_STATES 1, NC_K2_REWRITTEN_WHOLE 356); unasserted,
--   printed. HC_F1_REWRITE_BEFORE_MIDNIGHT and NC_F1_REWRITE_AT_MIDNIGHT also read T1 13, as on the
--   v27.170 run (unasserted; the cause was not investigated here).
-- check_plan_seat_controls.py and check_plan_money_controls.py on the real table after the deploy:
-- exit 1 by LIVE alone (non-zero exactly C13 1, F1 1, F2 1), every copy at its expected value (jobs
-- bqjob_r28ce46c4ceeae428_000001a10317178d_1, 8,986.4 slot-seconds; bqjob_r114f15b1e643729a_000001a103173577_1,
-- 949,116.0 slot-seconds).
-- =============================================================================================
WITH p AS (
  SELECT * FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK`
  WHERE as_of = (SELECT MAX(as_of) FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK`)
),
b AS (SELECT * FROM p WHERE is_live_plan),
-- the live judgement view: since v27.171 only T1's click goal reads it (inc_goal); C13 reads the
-- judgement the night was built on (js, below)
j AS (SELECT * FROM `onyga-482313.OI.V_PLAN_WINDOW_JUDGMENT`),
led AS (
  SELECT family, CAST(campaign_id AS STRING) AS campaign_id,
         CAST(keyword_id AS STRING) AS keyword_id, MIN(seat_no) AS seat_no
  FROM `onyga-482313.OI.DE_FAMILY_SEAT_LEDGER`
  WHERE closed_on IS NULL
  GROUP BY 1, 2, 3
),
-- v27.159: the partition before the latest (C23, T1), and each keyword's most recent seat in any
-- partition before the latest (T2) — the builder's own memory (P-16, P-28)
prev AS (
  SELECT * FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK`
  WHERE as_of = (SELECT MAX(as_of) FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK`
                 WHERE as_of < (SELECT MAX(as_of) FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK`))
),
claims AS (
  SELECT plan, family, CAST(campaign_id AS STRING) AS campaign_id,
         CAST(keyword_id AS STRING) AS keyword_id, seat_no AS claim_no, as_of AS claim_as_of
  FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK`
  WHERE as_of < (SELECT MAX(as_of) FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK`) AND seat_no IS NOT NULL
  QUALIFY ROW_NUMBER() OVER (PARTITION BY plan, family, CAST(campaign_id AS STRING),
                                          CAST(keyword_id AS STRING)
                             ORDER BY as_of DESC) = 1
),
-- C01 RESTATED v27.160 (P-24, piece-1 plan Task 6): the fence is two days before the LOS ANGELES
-- date of the build, not before as_of. as_of is the New York date from v27.160, and the ~22:35 Los
-- Angeles pass is already the next New York date: on it as_of - 2 is a day later than the fence the
-- judge applies (window_to = LEAST(watermark - 1, today_la - 2)), and at that hour FN_ADS_ANCHOR_CAP
-- has advanced the watermark to the Los Angeles date (watermark = the build's LA date on all eight
-- partitions built after 22:00 Los Angeles, 2026-08-23 .. 09-30), so the v27.159 form fails every
-- row of such a partition. On a partition keyed on the Los Angeles date the two forms are equal.
-- A build that straddled Los Angeles midnight would read a day off here (built_at is stamped at the
-- INSERT, the judge read its date at the start); no orchestrator pass runs then.
c01 AS (
  SELECT 'C01 window is complete days only and fenced to age 2 on the Los Angeles date of the build (P-10, P-14a, P-24)' AS check_name,
         COUNTIF(window_to != LEAST(DATE_SUB(watermark, INTERVAL 1 DAY),
                                    DATE_SUB(DATE(built_at, 'America/Los_Angeles'), INTERVAL 2 DAY))
                 OR DATE_DIFF(window_to, window_from, DAY) + 1 != window_days) AS violations
  FROM p
),
c02 AS (
  SELECT 'C02 both plans written, one row per plan x campaign x keyword (P-9)',
         (SELECT COUNT(*) FROM (SELECT plan, campaign_id, keyword_id FROM p GROUP BY 1,2,3 HAVING COUNT(*) > 1))
       + (SELECT ABS(2 - COUNT(DISTINCT plan)) FROM p)
       + (SELECT COUNTIF(n != 1) FROM (SELECT plan, COUNT(DISTINCT is_live_plan) n FROM p GROUP BY 1))
       + (SELECT ABS(1 - COUNT(DISTINCT plan)) FROM p WHERE is_live_plan)
),
-- C03 RESTATED v27.158 (2026-10-02, P-15, audit fix #24). The pot is every GOOD keyword's window
-- spend, holdout included. Until v27.157 the check summed `side = 'GOOD' AND NOT holdout` under the
-- label "(P-2)", enforcing the builder's reading (a) while naming the ruling it departed from. The
-- last term is the emptiness term: an empty partition is a failure, not a pass.
c03 AS (
  SELECT 'C03 pot = every GOOD keyword window spend per day, holdout included, to the cent (P-15)',
         (SELECT COUNTIF(ABS(pot_per_day - good_spend) > 0.01)
          FROM (SELECT plan, family, MAX(pot_per_day) pot_per_day,
                       SAFE_DIVIDE(SUM(IF(side = 'GOOD', w_sp, 0)), MAX(window_days)) good_spend
                FROM p GROUP BY 1, 2))
       + (SELECT IF(COUNT(*) = 0, 1, 0) FROM p)
),
-- C04 RESTATED v27.158 (P-21): the ramped allowance is LEAST(not-good today, the P-8 ramp).
c04 AS (
  SELECT 'C04 allowance = share x pot, ramped one step of the gap, never above today not-good spend (P-2, P-8, P-21)',
         (SELECT COUNTIF(ABS(allowance_target_per_day - allowance_share * pot_per_day) > 0.01
                 OR ABS(allowance_ramped_per_day
                        - LEAST(notgood_today_per_day,
                                GREATEST(allowance_share * pot_per_day,
                                         notgood_today_per_day
                                         - (notgood_today_per_day - allowance_share * pot_per_day) / ramp_steps))) > 0.01)
          FROM (SELECT DISTINCT plan, family, allowance_share, pot_per_day, allowance_target_per_day,
                                allowance_ramped_per_day, notgood_today_per_day, ramp_steps FROM p))
       + (SELECT IF(COUNT(*) = 0, 1, 0) FROM p)
),
c05 AS (
  SELECT 'C05 seats fit the ramped allowance; every seat is numbered exactly once (P-2, P-7, P-8)',
         (SELECT COUNTIF(seat_cost > allowance + 0.01)
          FROM (SELECT plan, family, SUM(IF(seat_no IS NOT NULL, seat_cost_per_day, 0)) seat_cost,
                       MAX(allowance_ramped_per_day) allowance
                FROM p GROUP BY 1, 2))
       + (SELECT COUNT(*) FROM (SELECT plan, family, seat_no FROM p
                                WHERE seat_no IS NOT NULL GROUP BY 1,2,3 HAVING COUNT(*) > 1))
       + (SELECT COUNTIF(seat_no IS NOT NULL AND NOT is_candidate) FROM p)
       + (SELECT COUNTIF(seat_no IS NOT NULL AND seat_no < 1) FROM p)
),
-- C06 EXTENDED v27.159 (P-25, audit fix #19): a seated probe's move is OPEN_PROBE and an unseated
-- probe's is NONE, so both join the candidate move list — and a candidate's NONE is an unseated
-- probe's and nobody else's.
c06 AS (
  SELECT 'C06 one move per CANDIDATE, none on the good side, none where there is nothing to repair (P-4, §9, P-25)',
         COUNTIF(side = 'GOOD' AND move != 'NONE')
       + COUNTIF(is_candidate AND move NOT IN ('REPRICE','HOLD_AT_PRICE','OPEN_PROBE','PARK','HOLD_AT_PARK','PAUSE','NONE'))
       + COUNTIF(is_candidate AND move = 'NONE' AND NOT (COALESCE(is_probe, FALSE) AND seat_no IS NULL))
       -- v27.147: scoped to the NOT-GOOD side. The builder tests `side = GOOD -> NONE` before
       -- `holdout -> NONE_HOLDOUT`, and its own assertion (and this check's first term) demand
       -- NONE on every good-side row -- so a GOOD keyword inside a holdout campaign satisfied term
       -- 1 and failed this term at once. Latent since v27.136: no holdout campaign was eligible on
       -- any partition written before 2026-08-29, and the first partition after them became
       -- eligible (2026-09-28) lit 38 rows. A NOT-GOOD holdout row must still say NONE_HOLDOUT:
       -- it would otherwise be a candidate, and the label is what explains its silence.
       + COUNTIF(NOT is_candidate AND holdout AND side = 'NOT_GOOD' AND move != 'NONE_HOLDOUT')
       + COUNTIF(NOT is_candidate AND NOT holdout AND side = 'NOT_GOOD' AND move != 'NONE')
       + COUNTIF(move IS NULL)
  FROM p
),
c07 AS (
  SELECT 'C07 seated <=> a seat number and its seat cost; queued <=> zero planned spend (§4.5)',
         COUNTIF(is_candidate AND seat_no IS NULL AND planned_spend_per_day != 0)
       + COUNTIF(is_candidate AND seat_no IS NOT NULL
                 AND ABS(planned_spend_per_day - seat_cost_per_day) > 0.005)
       + COUNTIF(side = 'GOOD'
                 AND ABS(planned_spend_per_day - SAFE_DIVIDE(w_sp, window_days)) > 0.005)
  FROM p
),
-- C08 EXTENDED v27.158 (audit fix #11): the cap is a move too. A holdout campaign's cap is left
-- where it is (delta 0, basis NO_MOVE_HOLDOUT), no other campaign carries that basis, and every
-- holdout row — the GOOD ones too (move NONE, P-4) — says in words that it is a measurement
-- control and that its cap is unchanged.
-- Vacuous only when no holdout campaign is eligible on the partition (8 were on 2026-10-02).
c08 AS (
  SELECT 'C08 no holdout campaign is repriced, parked, paused, seated or has its cap moved by the plan (house rule, fix #11)',
         COUNTIF(holdout AND move NOT IN ('NONE', 'NONE_HOLDOUT'))
       + COUNTIF(holdout AND seat_no IS NOT NULL)
       + COUNTIF(holdout AND is_candidate)
       + COUNTIF(holdout AND ABS(campaign_planned_budget_delta_per_day) > 0.005)
       + COUNTIF(holdout AND COALESCE(campaign_budget_basis, '') != 'NO_MOVE_HOLDOUT')
       + COUNTIF(NOT COALESCE(holdout, FALSE) AND campaign_budget_basis = 'NO_MOVE_HOLDOUT')
       + COUNTIF(holdout
                 AND (sentence NOT LIKE '%This campaign is a measurement control (HOLDOUT from%'
                      OR sentence NOT LIKE '%CAMPAIGN CAP: unchanged at $% a day — this campaign is in the HOLDOUT arm from%'))
       + IF(COUNT(*) = 0, 1, 0)
  FROM p
),
-- C09, RESTATED v27.147 (2026-09-28). The v27.134 form copied the guard's preconditions and
-- read them as a veto -- the same reading that made the builder refuse every partition from
-- 2026-08-29 to 2026-09-28. The judge reads P-14b as a clock (v27.138) and, since P-14c (Ori,
-- 2026-09-17), grants the hold only on a very good last day. A demotion under the guard's
-- preconditions is legitimate exactly when the judge published why it released the row, so the
-- check reads guard_released_by and never re-derives the guard (P-11: one engine judges).
-- Negative controls 2026-09-28 on a temp copy: one such row with guard_released_by nulled -> 1;
-- one with an unknown reason -> 1; live -> 0.
c09 AS (
  SELECT 'C09 P-14: every row names its arm; a demotion under the guard preconditions carries the judge release reason (HOLD_EXPIRED | LAST_DAY_NOT_STRONG)',
         COUNTIF(settle_arm IS NULL OR decided_by IS NULL
                 OR (side = 'NOT_GOOD' AND was_good AND served AND NOT settled
                     AND guard_released_by IS NULL)
                 OR (guard_released_by IS NOT NULL
                     AND guard_released_by NOT IN ('HOLD_EXPIRED', 'LAST_DAY_NOT_STRONG')))
  FROM b
),
c10 AS (
  SELECT 'C10 P-12: every SEAT carries a verdict date in the future, held or repriced',
         COUNTIF(seat_no IS NOT NULL AND (verdict_date IS NULL OR verdict_date <= as_of))
       + COUNTIF(seat_no IS NULL AND verdict_date IS NOT NULL)
  FROM p
),
-- C11 RESTATED v27.158 (audit fix #11): the band and the floor at need govern a cap the plan
-- MOVES. A cap the plan leaves where it is (NO_MOVE_*) is neither a move into the band nor the
-- plan's squeeze: on the 2026-10-02 partition 5 holdout campaigns' visible spend sat above today's
-- budget, and a holdout cap may not be moved (C08).
c11 AS (
  SELECT "C11 budgets the plan moves: outside the forbidden band, over $1.00, and never under the money the plan can SEE inside them (P-4)",
         (SELECT COUNTIF(campaign_planned_budget > 20.00 AND campaign_planned_budget < 32.00
                         AND campaign_budget_basis NOT IN
                             ('NO_MOVE_UNMEASURED', 'NO_MOVE_BRAND_DEFENSE', 'NO_MOVE_HOLDOUT'))
                + COUNTIF(campaign_planned_budget < 1.00)
                + COUNTIF(campaign_planned_budget IS NULL) FROM p)
       + (SELECT COUNTIF(bud < good_spend - 0.005) + COUNTIF(bud < need - 0.005)
          FROM (SELECT plan, campaign_id, MAX(campaign_planned_budget) bud,
                       MAX(campaign_budget_basis) basis,
                       SUM(IF(side = 'GOOD', planned_spend_per_day, 0)) good_spend,
                       -- v27.138: the plan's own arithmetic counts a queued keyword at ZERO, and
                       -- the plan's own PARK sentence says parking does not stop a spend. Flooring
                       -- at the arithmetic is satisfied by construction; flooring at the MONEY is
                       -- what stops a cap being ramped towards a figure nobody believes.
                       SUM(planned_spend_per_day)
                       + SUM(IF(is_candidate AND seat_no IS NULL AND move != 'PAUSE',
                                COALESCE(SAFE_DIVIDE(w_sp, window_days), 0), 0)) need
                FROM p GROUP BY 1, 2)
          WHERE NOT STARTS_WITH(COALESCE(basis, ''), 'NO_MOVE_'))
),
c12 AS (
  SELECT 'C12 prices: no planned bid below the row floor or above the house ceiling; NONE on the good side (P-4)',
         (SELECT COUNTIF(planned_bid < bid_floor - 0.005
                         OR (planned_bid > current_bid + 0.005 AND planned_bid > 2.005))
          FROM p WHERE move IN ('REPRICE', 'OPEN_PROBE'))   -- v27.159: a probe opens under the same ceiling
       + (SELECT COUNTIF(planned_bid IS NOT NULL OR seat_cost_per_day IS NOT NULL)
          FROM p WHERE side = 'GOOD')
),
-- C13 RESTATED v27.171 (2026-10-03, learning piece 2 Task 3 follow-up 2): the live plan reproduces
-- the judgement ITS NIGHT WAS BUILT ON, read from T_PLAN_BUILD_JUDGMENT — the builder's own read of
-- the view, saved with the night and keyed on its as_of and built_at — not the live view. Under the
-- freeze (v27.170) a night is written on the Los Angeles day before its as_of and stays, while the
-- view's fence (window_to = LEAST(watermark - 1, today_la - 2)) moves at Los Angeles midnight: on the
-- 2026-10-03 night the 05:36:35 UTC write (window 09-28 .. 09-30) and the 16:34:13 UTC write
-- (09-29 .. 10-01) differ on 47 of 356 live rows in side, verdict or is_candidate, with the same 356
-- keys (BigQuery time travel, job c13fix_tt47b_1791052048), so the v27.170 form, read against the
-- view, could pass only between a night's write and Los Angeles midnight. The comparison now also
-- covers the window and calendar state, and uses IS DISTINCT FROM (a NULL on one side counts).
-- Terms: the row-for-row difference (read only when the night's judgement is on record), 1 when it
-- is not on record (a night written before v27.171, or a saved judgement of another write: its
-- built_at differs), and 1 when the live plan is empty.
js AS (
  SELECT s.*
  FROM `onyga-482313.OI.T_PLAN_BUILD_JUDGMENT` s
  JOIN (SELECT as_of, MAX(built_at) AS built_at FROM p GROUP BY as_of) n
    ON s.as_of = n.as_of AND s.built_at = n.built_at
),
c13 AS (
  SELECT 'C13 the live plan reproduces the judgement its night was built on, row for row: side, verdict, candidacy, window, calendar state',
         (SELECT COUNT(*) FROM b FULL OUTER JOIN js s
            ON s.campaign_id = b.campaign_id AND s.keyword_id = b.keyword_id
          WHERE EXISTS (SELECT 1 FROM js)
            AND (b.campaign_id IS NULL OR s.campaign_id IS NULL
                 OR b.side IS DISTINCT FROM s.side_b OR b.verdict IS DISTINCT FROM s.verdict
                 OR b.is_candidate IS DISTINCT FROM s.is_candidate
                 OR b.window_from IS DISTINCT FROM s.window_from
                 OR b.window_to IS DISTINCT FROM s.window_to
                 OR b.calendar_state IS DISTINCT FROM s.calendar_state))
       + (SELECT IF(COUNT(*) = 0, 1, 0) FROM js)
       + (SELECT IF(COUNT(*) = 0, 1, 0) FROM b)
),
-- C14 EXTENDED v27.159 (P-25): a seat's move is REPRICE / HOLD_AT_PRICE, or OPEN_PROBE on a probe;
-- a queue position's is PARK / HOLD_AT_PARK / PAUSE, or NONE on an unseated probe; a probe that is
-- not closed takes exactly the probe move for where it stands; and every candidate carries is_probe.
c14 AS (
  SELECT 'C14 every candidate has exactly ONE of a seat or a queue position; a probe opens on a seat and takes no move without one (§9, P-25)',
         COUNTIF(is_candidate AND seat_no IS NULL AND move NOT IN ('PARK','HOLD_AT_PARK','PAUSE','NONE'))
       + COUNTIF(is_candidate AND seat_no IS NOT NULL AND move NOT IN ('REPRICE','HOLD_AT_PRICE','OPEN_PROBE'))
       + COUNTIF(is_candidate AND rank_no IS NULL)
       + COUNTIF(is_candidate AND is_probe AND COALESCE(ladder_state, '') != 'DEAD'
                 AND seat_no IS NOT NULL AND move != 'OPEN_PROBE')
       + COUNTIF(is_candidate AND is_probe AND COALESCE(ladder_state, '') != 'DEAD'
                 AND seat_no IS NULL AND move != 'NONE')
       + COUNTIF(move = 'OPEN_PROBE' AND NOT (is_candidate AND COALESCE(is_probe, FALSE) AND seat_no IS NOT NULL))
       + COUNTIF(is_candidate AND is_probe IS NULL)
  FROM p
),
-- C15 RESTATED v27.158 (P-15): pot (every GOOD row, holdout included) + not-good (holdout excluded)
-- = the window spend of every row except the not-good holdout rows.
c15 AS (
  SELECT 'C15 pot + not-good = the window spend per day outside the not-good holdout rows, to the cent (P-15)',
         (SELECT COUNTIF(ABS(pot + notgood - total) > 0.01)
          FROM (SELECT plan, family, MAX(pot_per_day) pot, MAX(notgood_today_per_day) notgood,
                       SAFE_DIVIDE(SUM(IF(COALESCE(holdout, FALSE) AND side = 'NOT_GOOD', 0, w_sp)),
                                   MAX(window_days)) total
                FROM p GROUP BY 1, 2))
       + (SELECT IF(COUNT(*) = 0, 1, 0) FROM p)
),
-- C16 RESTATED v27.158 (audit fix #15): ramp_step counts plan uploads that LANDED, so it is
-- LEAST(ramp_steps, plan_uploads_landed), 0 when none has; plan_uploads_landed is one number per
-- family; and the sentence says "no step taken yet" exactly on the rows whose family has none.
-- Until v27.157 it was a calendar count of windows (ramp_step >= 1 was asserted here).
c16 AS (
  SELECT 'C16 the ramp step counts plan uploads that landed, inside its bounds, and the settings are the declared ones (fix #15)',
         (SELECT COUNTIF(ramp_step IS NULL OR ramp_step < 0 OR ramp_step > ramp_steps OR ramp_steps < 1
                         OR plan_uploads_landed IS NULL OR plan_uploads_landed < 0
                         OR ramp_step != LEAST(ramp_steps, plan_uploads_landed)
                         OR allowance_share <= 0 OR allowance_share > 1
                         OR calendar_state IS NULL OR sentence IS NULL OR family IS NULL)
                + COUNTIF((plan_uploads_landed = 0) != (sentence LIKE '%Ramp: no step taken yet%'))
          FROM p)
       + (SELECT COUNTIF(n > 1)
          FROM (SELECT family, COUNT(DISTINCT plan_uploads_landed) n FROM p GROUP BY 1))
       + (SELECT IF(COUNT(*) = 0, 1, 0) FROM p)
),
-- C17 RESTATED v27.159: on the LIVE plan. DE_FAMILY_SEAT_LEDGER registers plan B's seats only
-- (SP_MAINTAIN_FAMILY_SEATS reads plan A for agreement_tier, never for numbers), and the shadow plan
-- now numbers its own seats; until v27.158 the register's numbers also bound plan A, and a plan-A
-- seat renumbered by the register is what refused the builder on 2026-09-29 (SOP §3, "Seat numbers").
c17 AS (
  SELECT 'C17 no seat number the register still holds OPEN for another keyword is reissued on the live plan, and a keyword it holds carries its number (§9)',
         (SELECT COUNT(*)
          FROM b JOIN led l ON l.family = b.family AND l.seat_no = b.seat_no
          WHERE b.seat_no IS NOT NULL AND l.keyword_id != b.keyword_id)
       + (SELECT COUNT(*)
          FROM b JOIN led l ON l.family = b.family
                           AND l.campaign_id = b.campaign_id AND l.keyword_id = b.keyword_id
          WHERE b.seat_no IS NOT NULL AND l.seat_no != b.seat_no)
),
c18 AS (
  SELECT 'C18 the seat walk is a FIT TEST: no queued candidate fits the allowance left over (§4.4)',
         (SELECT COUNTIF(min_queued_cost <= allowance - seat_cost + 0.0001)
          FROM (SELECT plan, family,
                       MAX(allowance_ramped_per_day) AS allowance,
                       SUM(IF(seat_no IS NOT NULL, seat_cost_per_day, 0)) AS seat_cost,
                       -- a keyword the ladder has closed is not seatable at any price (v27.138)
                       MIN(IF(is_candidate AND seat_no IS NULL AND ladder_state != 'DEAD',
                              seat_cost_per_day, NULL))
                         AS min_queued_cost
                FROM p GROUP BY 1, 2)
          WHERE min_queued_cost IS NOT NULL)
),
c19 AS (
  SELECT "C19 §9 reconciliation as the arithmetic can hold it: not-good PLANNED spend = the seats' cost",
         (SELECT COUNTIF(ABS(notgood_planned - seat_cost) > 0.01)
          FROM (SELECT plan, family,
                       SUM(IF(side = 'NOT_GOOD' AND NOT holdout AND is_candidate,
                              planned_spend_per_day, 0)) AS notgood_planned,
                       SUM(IF(seat_no IS NOT NULL, seat_cost_per_day, 0)) AS seat_cost
                FROM p GROUP BY 1, 2))
       + (SELECT COUNTIF(is_candidate AND (seat_no IS NOT NULL) = (move IN ('PARK','HOLD_AT_PARK','PAUSE','NONE')))
          FROM p)
),
c20 AS (
  SELECT "C20 the plan says on the row whether it RAISES or cuts each keyword's spend",
         COUNTIF(planned_spend_delta_per_day IS NULL)
       + COUNTIF(ABS(planned_spend_delta_per_day
                     - (planned_spend_per_day - COALESCE(SAFE_DIVIDE(w_sp, window_days), 0))) > 0.005)
  FROM p
),
c21 AS (
  SELECT 'C21 PAUSE only on a keyword the ladder has already closed, and it carries no bid (§4.5)',
         COUNTIF(move = 'PAUSE' AND ladder_state != 'DEAD')
       + COUNTIF(move = 'PAUSE' AND planned_bid IS NOT NULL)
  FROM p
),
-- C22 IS C21'S MISSING CONVERSE. C21 only ever tested "PAUSE implies closed", which is the
-- direction that passed; nothing tested "closed implies not seated", and on the v27.137 partition
-- ten closed keywords held seats, held family allowance and were published with an executable bid
-- while a single closed keyword that did not fit was told a closed keyword is stopped, not
-- re-priced. Same class of narrowing as the "every REPRICED seat" C10 blessed a pass earlier.
c22 AS (
  SELECT 'C22 a keyword the ladder has CLOSED takes no seat, holds no allowance and carries no price (§4.5)',
         COUNTIF(ladder_state = 'DEAD' AND seat_no IS NOT NULL)
       + COUNTIF(ladder_state = 'DEAD' AND planned_bid IS NOT NULL)
       + COUNTIF(ladder_state = 'DEAD' AND is_candidate AND move != 'PAUSE')
       + COUNTIF(ladder_state = 'DEAD' AND seat_cost_per_day > 0 AND seat_no IS NOT NULL)
  FROM p
),
-- C23: §9's "seat numbers stable across days for continuing occupants". C05 checks uniqueness
-- inside ONE partition and C17 checks non-collision with the register; neither can see a seat
-- being re-numbered from one night to the next, which is what happened to every seat the register
-- does not hold an open row for. The exception is narrow: the register holds the OLD number open for
-- a DIFFERENT keyword (the register wins, §9).
-- EXTENDED v27.159 (P-16, Ori 2026-10-02, R2): FROM NUMBER TO OCCUPANCY. A seat of the previous
-- partition written under P-16 (seat_since), whose verdict date is after the latest as_of and whose
-- keyword is still a candidate (not closed), holds a seat on the latest partition — or carries
-- seat_tenure LEFT_ALLOWANCE_SHRANK (T1 checks that the allowance really could not carry it). Seats
-- written before v27.159 carry no seat_since and are not contracts (the builder's cutover), so on the
-- first v27.159 partition this term is vacuous by construction; the negative controls exercise it.
c23 AS (
  SELECT 'C23 §9 + P-16: a continuing occupant keeps its seat number from one night to the next, and an incumbent before its date keeps the seat',
         (SELECT COUNT(*)
          FROM p JOIN (
            SELECT plan, family, CAST(campaign_id AS STRING) campaign_id,
                   CAST(keyword_id AS STRING) keyword_id, MIN(seat_no) seat_no
            FROM prev
            WHERE seat_no IS NOT NULL
            GROUP BY 1, 2, 3, 4) h
            USING (plan, family, campaign_id, keyword_id)
          WHERE p.seat_no IS NOT NULL AND h.seat_no != p.seat_no
            AND NOT EXISTS (SELECT 1 FROM led l
                            WHERE l.family = p.family AND l.seat_no = h.seat_no
                              AND l.keyword_id != p.keyword_id))
       + (SELECT COUNT(*)
          FROM prev h JOIN p USING (plan, family, campaign_id, keyword_id)
          WHERE h.seat_no IS NOT NULL AND h.seat_since IS NOT NULL AND h.verdict_date > p.as_of
            AND p.is_candidate AND COALESCE(p.ladder_state, '') != 'DEAD'
            AND p.seat_no IS NULL AND COALESCE(p.seat_tenure, '') != 'LEFT_ALLOWANCE_SHRANK')
       + (SELECT IF(COUNT(*) = 0, 1, 0) FROM p)
),
-- C24: the two house rules the budget step broke. "Unmeasured never reads as bad" and "brand
-- defense is never judged on profit" (spec §8). On the v27.137 partition 19 campaigns whose every
-- keyword took no click and spent nothing in the window were ramped one third of the way towards
-- ZERO, compounding nightly because the ramp re-reads the cap it wrote; one of them was a brand
-- defense campaign whose keywords are the house's own brand terms.
c24 AS (
  SELECT 'C24 a campaign the plan measured nothing in, and a brand-defense campaign, is never cut, and every cap says its move',
         (SELECT COUNT(*) FROM (
            SELECT plan, campaign_id, MAX(campaign_planned_budget) bud,
                   MAX(campaign_current_budget) cur,
                   MAX(campaign_visible_spend_per_day) vis, SUM(COALESCE(w_clk, 0)) clk,
                   LOGICAL_OR(UPPER(COALESCE(campaign_name, '')) LIKE '%BRAND DEFENSE%') def
            FROM p GROUP BY 1, 2)
          WHERE cur IS NOT NULL AND bud < cur - 0.005
            AND ((vis <= 0.0001 AND clk = 0) OR def))
       + (SELECT COUNTIF(campaign_budget_basis IS NULL
                         OR campaign_planned_budget_delta_per_day IS NULL
                         OR sentence NOT LIKE '%CAMPAIGN CAP:%') FROM p)
       + (SELECT COUNTIF(ABS(campaign_planned_budget_delta_per_day
                             - (campaign_planned_budget
                                - COALESCE(campaign_current_budget, campaign_planned_budget)))
                         > 0.005) FROM p)
),
-- C25: the seat sentence must name the DIRECTION on every seat, not only on the repriced ones.
-- v27.137 added the clause to REPRICE and its own account claimed both; the ten HOLD_AT_PRICE
-- rows — the seats whose sentence says nothing is uploaded — carried a raise and did not say so.
c25 AS (
  SELECT 'C25 every SEAT sentence names whether the plan raises or cuts that keyword (P-6 disclosure)',
         COUNTIF(seat_no IS NOT NULL
                 AND sentence NOT LIKE '%A RAISE of about%'
                 AND sentence NOT LIKE '%a cut of about%'
                 AND sentence NOT LIKE '%no change of about%')
  FROM p
),
-- C26 (v27.147): P-14c -- every held row earned the hold with a very good last day and sits on
-- the good side, and no sale-less window is held (a window that sold nothing cannot have a very
-- good last day). Negative controls 2026-09-28 on a temp copy: one HELD row with
-- last_day_strong flipped -> 1; one HELD row with w_ord set to 0 -> 1; live -> 0.
-- RESTATED v27.156 (2026-10-02, P-18): a hold is also kept while the very good day that started
-- it is still inside the window, so the check READS hold_kept_by and never re-derives the guard:
-- every HELD row is kept by LAST_DAY with a very good last day, or by STRONG_DAY_IN_WINDOW with
-- window_from <= hold_strong_day (a HELD row with no hold_kept_by fails: the check reads the
-- latest partition, which SP_BUILD_NEXT_WEEK_PLAN v27.156 writes); a row that is not HELD names
-- no reason. The sale-less term stays: the strong day that keeps a STRONG_DAY_IN_WINDOW hold had an order and
-- is inside the window. Negative controls 2026-10-02 (Los Angeles) on temp copies of the plan
-- table, this file's text with the table name swapped; the 2026-10-02 partition written by
-- SP_BUILD_NEXT_WEEK_PLAN v27.156 holds no HELD row, so each control made the lowest-numbered
-- live row that served with w_ord >= 1 (rn 371 of the partition) HELD on the good side first:
--   LIVE 0 · strong day = window_from - 1, kept by STRONG_DAY_IN_WINDOW, last day not strong 1 ·
--   strong day = window_from 0 · hold_kept_by NULL 1 · LAST_DAY with last day not strong 1 ·
--   a non-HELD row naming LAST_DAY 1 · the strong-day-in row with w_ord 0 1.
--   (C13 read 1 on every copy that changed a verdict, as it must: the copy no longer matches the
--   judgement view.)
c26 AS (
  SELECT 'C26 P-14c/P-18: every HELD row is on the good side and kept by a very good last day or by the very good day that started it still in the window; no sale-less window is held',
         COUNTIF(verdict = 'HELD_UNSETTLED'
                 AND (side != 'GOOD'
                      OR NOT COALESCE((hold_kept_by = 'LAST_DAY' AND last_day_strong)
                                      OR (hold_kept_by = 'STRONG_DAY_IN_WINDOW'
                                          AND window_from <= hold_strong_day), FALSE)))
       + COUNTIF(verdict != 'HELD_UNSETTLED' AND hold_kept_by IS NOT NULL)
       + COUNTIF(verdict = 'HELD_UNSETTLED' AND COALESCE(w_ord, 0) = 0)
  FROM b
),
-- ---- v27.158 (2026-10-02, piece-1 plan Task 4): the builder's money ----
-- M1 (P-21): the ramped allowance never exceeds today's not-good spend, per plan x family.
m1 AS (
  SELECT 'M1 the ramped allowance never exceeds today not-good spend (P-21)',
         (SELECT COUNTIF(allowance_ramped_per_day > notgood_today_per_day + 0.0001)
          FROM (SELECT DISTINCT plan, family, allowance_ramped_per_day, notgood_today_per_day FROM p))
       + (SELECT IF(COUNT(*) = 0, 1, 0) FROM p)
),
-- M2 (audit fix #12): every cap's basis is one of the §4.7 rules, one per campaign, and the number
-- follows the rule it names: RAMPED is ROUND(current + (need - current) / ramp_steps, 2) to the
-- cent; FLOORED_AT_NEED is need to the cent; BAND_SNAPPED_UP is $32.00 and _DOWN $20.00;
-- FLOORED_AT_MINIMUM is $1.00; NO_MOVE_* is today's budget. need is recounted from the rows the way
-- C11 counts it (4-decimal money, so a ramp value can round a cent the other way: tolerance one
-- cent). The row term: the sentence says "the one-third ramp decided it" exactly on RAMPED rows.
cap AS (
  SELECT plan, campaign_id, MAX(campaign_planned_budget) bud, MAX(campaign_current_budget) cur,
         MAX(campaign_budget_basis) basis, COUNT(DISTINCT campaign_budget_basis) n_basis,
         MAX(ramp_steps) steps,
         SUM(planned_spend_per_day)
         + SUM(IF(is_candidate AND seat_no IS NULL AND move != 'PAUSE',
                  COALESCE(SAFE_DIVIDE(w_sp, window_days), 0), 0)) need
  FROM p GROUP BY 1, 2
),
m2 AS (
  SELECT 'M2 every campaign cap names the rule that set it and its number follows that rule (fix #12)',
         (SELECT COUNTIF(n_basis > 1 OR basis IS NULL
                         OR basis NOT IN ('RAMPED', 'FLOORED_AT_NEED', 'BAND_SNAPPED_UP',
                                          'BAND_SNAPPED_DOWN', 'FLOORED_AT_MINIMUM', 'NO_MOVE_HOLDOUT',
                                          'NO_MOVE_BRAND_DEFENSE', 'NO_MOVE_UNMEASURED')
                         OR (basis = 'RAMPED'
                             AND ROUND(ABS(bud - ROUND(COALESCE(cur, need)
                                                       + (need - COALESCE(cur, need)) / steps, 2)), 4) > 0.01)
                         OR (basis = 'FLOORED_AT_NEED' AND ROUND(ABS(bud - need), 4) > 0.01)
                         OR (basis = 'BAND_SNAPPED_UP' AND ABS(bud - 32.00) > 0.005)
                         OR (basis = 'BAND_SNAPPED_DOWN' AND ABS(bud - 20.00) > 0.005)
                         OR (basis = 'FLOORED_AT_MINIMUM' AND ABS(bud - 1.00) > 0.005)
                         OR (STARTS_WITH(basis, 'NO_MOVE_') AND ABS(bud - COALESCE(cur, bud)) > 0.005))
          FROM cap)
       + (SELECT COUNTIF((campaign_budget_basis = 'RAMPED')
                         != (sentence LIKE '%tonight the one-third ramp decided it%')) FROM p)
       + (SELECT IF(COUNT(*) = 0, 1, 0) FROM cap)
),
-- M3 (P-22): expected_after_upload_per_day is one number per plan x family and equals the seats'
-- cost + every queued candidate's window spend per day x (planned bid / current bid), PAUSE at
-- zero; share_closed is (not-good today - expected) / (not-good today - target) when that gap is
-- above $0.005 a day and NULL otherwise; and every row's sentence prints the expected figure and
-- the share (or "no gap to close").
fam_m AS (
  SELECT plan, family,
         MAX(expected_after_upload_per_day) ex, MIN(expected_after_upload_per_day) ex_min,
         COUNTIF(expected_after_upload_per_day IS NULL) ex_null,
         MAX(share_closed) sh, MIN(share_closed) sh_min, COUNTIF(share_closed IS NULL) sh_null,
         COUNT(*) n, MAX(notgood_today_per_day) ng, MAX(allowance_target_per_day) tgt,
         SUM(IF(seat_no IS NOT NULL, seat_cost_per_day, 0))
         + SUM(IF(is_candidate AND seat_no IS NULL AND move != 'PAUSE',
                  COALESCE(SAFE_DIVIDE(w_sp, window_days), 0)
                  * COALESCE(SAFE_DIVIDE(planned_bid, NULLIF(current_bid, 0)), 1), 0)) recount
  FROM p GROUP BY 1, 2
),
m3 AS (
  SELECT 'M3 expected after upload = the seats + the queue at the price the plan leaves it at; share_closed follows (P-22)',
         (SELECT COUNTIF(ex_null > 0 OR ex != ex_min
                         OR ABS(ex - recount) > 0.001
                         OR (ng - tgt > 0.005
                             AND (sh_null > 0 OR sh != sh_min
                                  OR ABS(sh - (ng - ex) / (ng - tgt)) > 0.0005))
                         OR (ng - tgt <= 0.005 AND sh_null != n))
          FROM fam_m)
       + (SELECT COUNTIF(STRPOS(sentence, FORMAT('Expected after the upload: $%.2f a day',
                                                 expected_after_upload_per_day)) = 0
                         OR STRPOS(sentence, IF(share_closed IS NULL, 'so there is no gap to close',
                                                FORMAT('%.0f%% of the gap to the allowance target closes',
                                                       100 * share_closed))) = 0)
          FROM p)
       + (SELECT IF(COUNT(*) = 0, 1, 0) FROM fam_m)
),
-- ---- v27.159 (2026-10-02, piece-1 plan Task 5): the builder's seats ----
-- T1 (P-16): an incumbent keeps its contract — number (C23), price, verdict date, the night it took
-- the seat, the question — or leaves only when the allowance cannot carry every incumbent (since
-- v27.167 latest-seated first until the rest fit; see the RESTATED v27.167 note below; v27.159 ..
-- v27.164 asked every leaver to cost more than the room the kept ones leave). No other row claims tenure; a seat is
-- INCUMBENT or NEW and carries seat_since (as_of on a NEW seat); and each tenure says itself in the
-- sentence. Vacuous on the first v27.159 partition (no contract written before it); the controls
-- exercise it.
-- RESTATED v27.164 (piece-1 follow-up F2): THE COST IS NOT PART OF THE CONTRACT. An incumbent's cost
-- is its kept price (the previous partition's planned_bid) on TONIGHT's window, recounted here from
-- the row as the builder costs it: a probe tonight click_goal_day x kept price (click_goal_day read
-- from the judgement, the one place it is declared), any other row w_sp / window_days x kept price /
-- current bid, and 0 with no spend or no current bid. The eviction test reads the same recount. The
-- v27.159 form compared the cost with the previous partition's, which is the rule F2 retired: on the
-- 2026-10-03 partition built 08:12 UTC by v27.160 it held 30 live incumbents that printed "A RAISE"
-- ($15.24 a day) while their price was held or cut.
-- RESTATED v27.167 (piece-1 follow-up F8): INCUMBENTS LEAVE LATEST-SEATED FIRST UNTIL THE REST FIT.
-- The eviction term reads the builder's walk order (the previous partition's seat_since, then
-- tonight's rank; inc_ord): no incumbent that left (any tenure but INCUMBENT, a re-seat as NEW
-- included) comes before one that kept its seat, and the first one that left costs more than the
-- allowance leaves after the kept ones. The v27.164 form asked that of every incumbent that left —
-- the fit test's invariant, which passes an earlier, costlier incumbent sent out while a later,
-- cheaper one keeps its seat, and fails a later leaver cheap enough to fit on its own. The sentence
-- term now also asks a LEFT_ALLOWANCE_SHRANK row for R2's words ("incumbents leave latest-seated
-- first until the rest fit"): v27.164's sentence named the fit test.
inc_goal AS (SELECT campaign_id, keyword_id, click_goal_day FROM j),
inc_ord AS (
  SELECT x.*,
         MAX(IF(x.seat_tenure = 'INCUMBENT', x.inc_pos, 0)) OVER (PARTITION BY x.plan, x.family) AS last_kept_pos,
         MIN(IF(COALESCE(x.seat_tenure, '') != 'INCUMBENT', x.inc_pos, NULL))
           OVER (PARTITION BY x.plan, x.family) AS first_left_pos
  FROM (SELECT p.plan, p.family, p.campaign_id, p.keyword_id, p.seat_tenure,
               ROW_NUMBER() OVER (PARTITION BY p.plan, p.family
                                  ORDER BY h.seat_since, p.rank_no, p.campaign_id, p.keyword_id) AS inc_pos
        FROM prev h
        JOIN p USING (plan, family, campaign_id, keyword_id)
        WHERE h.seat_no IS NOT NULL AND h.seat_since IS NOT NULL AND h.verdict_date > p.as_of
          AND p.is_candidate AND COALESCE(p.ladder_state, '') != 'DEAD') x
),
-- RESTATED v27.168 (piece-1 follow-up G1): "a probe" is the KEPT QUESTION's basis — the previous
-- partition's request_basis = 'HORIZON_PROBE_GOAL', the basis the builder writes on a probe's seat —
-- not tonight's is_probe (v27.164's form), so an ordinary seat that turned probe the next night keeps
-- its window cost (P-16 keeps the question; plan B Fresh 388620934464557 on 2026-10-03 was costed
-- 4 x $0.25 = $1.00 a day against the $0.1067 its question asked).
inc_cost AS (
  SELECT p.plan, p.campaign_id, p.keyword_id,
         COALESCE(CASE WHEN h.request_basis = 'HORIZON_PROBE_GOAL'
                         THEN g.click_goal_day * h.planned_bid
                       WHEN p.w_sp > 0 AND COALESCE(p.current_bid, 0) > 0
                         THEN (p.w_sp / p.window_days) * SAFE_DIVIDE(h.planned_bid, p.current_bid)
                       ELSE 0 END, 0) AS cost_tonight
  FROM prev h
  JOIN p USING (plan, family, campaign_id, keyword_id)
  LEFT JOIN inc_goal g ON g.campaign_id = p.campaign_id AND g.keyword_id = p.keyword_id
  WHERE h.seat_no IS NOT NULL AND h.seat_since IS NOT NULL AND h.verdict_date > p.as_of
),
t1 AS (
  SELECT 'T1 P-16: an incumbent keeps its contract and costs its kept price tonight, or leaves only when tonight allowance cannot carry every incumbent, latest-seated first until the rest fit; tenure is written and said',
         (SELECT COUNTIF(p.seat_tenure = 'INCUMBENT'
                         AND (p.seat_no IS NULL
                              OR p.seat_since IS DISTINCT FROM h.seat_since
                              OR p.verdict_date IS DISTINCT FROM h.verdict_date
                              OR ABS(COALESCE(p.planned_bid, -1) - COALESCE(h.planned_bid, -1)) > 0.005
                              OR ABS(COALESCE(p.seat_cost_per_day, -1) - ROUND(c.cost_tonight, 4)) > 0.0001
                              OR p.clicks_requested IS DISTINCT FROM h.clicks_requested
                              OR p.clicks_due_date IS DISTINCT FROM h.clicks_due_date
                              OR p.expected_cpc IS DISTINCT FROM h.expected_cpc
                              OR p.request_basis IS DISTINCT FROM h.request_basis))
                + COUNTIF(COALESCE(p.seat_tenure, '') != 'INCUMBENT'
                          AND (o.inc_pos < o.last_kept_pos
                               OR (o.inc_pos = o.first_left_pos
                                   AND NOT (c.cost_tonight > fa.allow - fa.kept + 0.0001))))
          FROM prev h
          JOIN p USING (plan, family, campaign_id, keyword_id)
          JOIN inc_cost c USING (plan, campaign_id, keyword_id)
          JOIN inc_ord o USING (plan, family, campaign_id, keyword_id)
          JOIN (SELECT plan, family, MAX(allowance_ramped_per_day) allow,
                       SUM(IF(seat_tenure = 'INCUMBENT', seat_cost_per_day, 0)) kept
                FROM p GROUP BY 1, 2) fa USING (plan, family)
          WHERE h.seat_no IS NOT NULL AND h.seat_since IS NOT NULL AND h.verdict_date > p.as_of
            AND p.is_candidate AND COALESCE(p.ladder_state, '') != 'DEAD')
       + (SELECT COUNT(*)
          FROM p LEFT JOIN prev h USING (plan, family, campaign_id, keyword_id)
          WHERE p.seat_tenure IN ('INCUMBENT', 'LEFT_ALLOWANCE_SHRANK')
            AND NOT COALESCE(h.seat_no IS NOT NULL AND h.seat_since IS NOT NULL
                             AND h.verdict_date > p.as_of AND p.is_candidate
                             AND COALESCE(p.ladder_state, '') != 'DEAD', FALSE))
       + (SELECT COUNTIF((seat_no IS NOT NULL) != (COALESCE(seat_tenure, '') IN ('INCUMBENT', 'NEW'))
                         OR (seat_no IS NOT NULL) != (seat_since IS NOT NULL)
                         OR (seat_tenure = 'NEW' AND seat_since != as_of)
                         OR (seat_tenure = 'INCUMBENT' AND STRPOS(sentence, 'TENURE: it has held this seat since') = 0)
                         OR (seat_tenure = 'NEW' AND STRPOS(sentence, 'TENURE: seated tonight') = 0)
                         -- v27.167 (F8): and in R2's words, not v27.164's fit-test sentence
                         OR (seat_tenure = 'LEFT_ALLOWANCE_SHRANK'
                             AND (STRPOS(sentence, 'TENURE ENDS EARLY') = 0
                                  OR STRPOS(sentence, 'incumbents leave latest-seated first until the rest fit') = 0)))
          FROM p)
       + (SELECT IF(COUNT(*) = 0, 1, 0) FROM p)
),
-- T2 (P-28): a seat number is sticky ACROSS AN ABSENCE TOO, by the precedence the builder numbers
-- with: a keyword the register holds open (live plan) carries the register's number; any other
-- seated keyword carries the number it held most recently in any earlier partition, unless the
-- register holds that number open for a different keyword (live plan) or another keyword seated on
-- the latest partition held it more recently. Vacuous only when no seated keyword ever held a seat.
t2 AS (
  SELECT 'T2 P-28: a seat number is sticky: the register number it holds (live plan), else the number it held most recently, across an absence too',
         (SELECT COUNT(*)
          FROM (SELECT p.plan, p.family, p.keyword_id, p.is_live_plan,
                       IF(p.is_live_plan, l0.seat_no, NULL) AS own_led, c.claim_no, c.claim_as_of
                FROM p
                LEFT JOIN led l0 ON l0.family = p.family AND l0.campaign_id = p.campaign_id
                                AND l0.keyword_id = p.keyword_id
                LEFT JOIN claims c ON c.plan = p.plan AND c.family = p.family
                                  AND c.campaign_id = p.campaign_id AND c.keyword_id = p.keyword_id
                WHERE p.seat_no IS NOT NULL
                  AND p.seat_no != COALESCE(IF(p.is_live_plan, l0.seat_no, NULL), c.claim_no)) x
          LEFT JOIN led l ON x.own_led IS NULL AND x.is_live_plan AND l.family = x.family
                         AND l.seat_no = x.claim_no AND l.keyword_id != x.keyword_id
          LEFT JOIN (SELECT g.plan, g.family, g.keyword_id, g.seat_no, c2.claim_as_of
                     FROM p g
                     JOIN claims c2 ON c2.plan = g.plan AND c2.family = g.family
                                   AND c2.campaign_id = g.campaign_id AND c2.keyword_id = g.keyword_id
                     WHERE g.seat_no IS NOT NULL AND g.seat_no = c2.claim_no) y
            ON x.own_led IS NULL AND y.plan = x.plan AND y.family = x.family AND y.seat_no = x.claim_no
           AND y.keyword_id != x.keyword_id AND y.claim_as_of > x.claim_as_of
          WHERE l.family IS NULL AND y.family IS NULL)
       + (SELECT IF(COUNTIF(seat_no IS NOT NULL) = 0, 1, 0) FROM p)
),
-- T3 (P-26): THE SEAT'S QUESTION SPANS ITS SETTLE HORIZON. Every seat: a positive click count, a
-- price per click, due on its verdict date; its horizon (due date - the night it took the seat) is
-- the channel's settle horizon (settle_due_on - window_to); clicks x expected CPC / horizon =
-- implied spend = the seat's cost, to the cent; the basis is one of P-26's. A NEW seat asks the
-- window's click rate over the horizon (ROUND(w_clk x horizon / window_days)), a probe a whole number
-- of days at its goal, and the basis says which. An incumbent repeats the question it was given (T1).
-- RESTATED v27.164 (piece-1 follow-up F2): implied spend = seat cost on a seat taken tonight only.
-- An incumbent's question is the one it was given, so its implied spend is the money of the night it
-- was asked, while its cost is its kept price on tonight's window (T1 recounts it); the two differ
-- whenever the window moved.
t3 AS (
  SELECT 'T3 P-26: every seat question spans its settle horizon: clicks x expected CPC / horizon = implied spend, = seat cost on a seat taken tonight',
         (SELECT COUNTIF(clicks_requested IS NULL OR clicks_requested <= 0 OR expected_cpc IS NULL
                         OR clicks_due_date IS DISTINCT FROM verdict_date
                         OR DATE_DIFF(clicks_due_date, seat_since, DAY) != DATE_DIFF(settle_due_on, window_to, DAY)
                         OR ABS(clicks_requested * expected_cpc / DATE_DIFF(clicks_due_date, seat_since, DAY)
                                - implied_daily_spend) > 0.01
                         OR (COALESCE(seat_tenure, '') != 'INCUMBENT'
                             AND ABS(implied_daily_spend - seat_cost_per_day) > 0.01)
                         OR request_basis IS NULL
                         OR request_basis NOT IN ('HORIZON_WINDOW_RATE', 'HORIZON_PROBE_GOAL')
                         OR (seat_tenure = 'NEW' AND (request_basis = 'HORIZON_PROBE_GOAL') != COALESCE(is_probe, FALSE))
                         OR (seat_tenure = 'NEW' AND request_basis = 'HORIZON_WINDOW_RATE'
                             AND clicks_requested != CAST(ROUND(w_clk * DATE_DIFF(clicks_due_date, seat_since, DAY)
                                                                / window_days) AS INT64))
                         OR (request_basis = 'HORIZON_PROBE_GOAL'
                             AND MOD(clicks_requested, DATE_DIFF(clicks_due_date, seat_since, DAY)) != 0))
          FROM p WHERE seat_no IS NOT NULL)
       + (SELECT IF(COUNTIF(seat_no IS NOT NULL) = 0, 1, 0) FROM p)
),
-- T4 (P-25, audit fix #19): a seated probe OPENS at a price and its sentence says "OPEN PROBE at $";
-- an unseated probe carries no price and its sentence says "PROBE NOT OPENED TONIGHT; NOTHING
-- UPLOADED"; and no queued candidate that bought nothing says it "keeps buying clicks" (the v27.158
-- PARK sentence said so on every unserved probe it parked: 9 LolliME, 1 Lollibox and a Fresh
-- HOLD_AT_PARK on the 2026-10-02 v27.158 partition).
t4 AS (
  SELECT 'T4 P-25 / fix #19: a seated probe opens and says so, an unseated probe has no move and no price and says so, and no row that bought nothing keeps buying clicks',
         COUNTIF(move = 'OPEN_PROBE' AND (planned_bid IS NULL OR STRPOS(sentence, 'OPEN PROBE at $') = 0))
       + COUNTIF(is_candidate AND move = 'NONE'
                 AND (planned_bid IS NOT NULL OR STRPOS(sentence, 'PROBE NOT OPENED TONIGHT; NOTHING UPLOADED') = 0))
       -- the row's own move clause ("this keyword keeps buying clicks" on PARK, "it keeps buying clicks"
       -- on HOLD_AT_PARK and a served probe's NONE) — not the CAMPAIGN CAP clause, whose "the queue
       -- that keeps buying clicks" is about the campaign (a first draft matched it: 224 rows)
       + COUNTIF(is_candidate AND NOT served AND move IN ('PARK', 'HOLD_AT_PARK', 'NONE')
                 AND REGEXP_CONTAINS(sentence, r'(this keyword|it) keeps buying clicks'))
       + IF(COUNT(*) = 0, 1, 0)
  FROM p
),
-- T5 (P-20): the builder ranks the candidates as the judgement view orders them — P-7's score for
-- the candidates it scores above zero, then money burned with no return (window spend per day x
-- GREATEST(0, 1 - return / bar)), then clicks, then the keys. Recounted from the row's own columns.
t5 AS (
  SELECT 'T5 P-20: candidates rank by P-7 score, then money burned with no return, then clicks (the judge order)',
         (SELECT COUNTIF(rank_no IS DISTINCT FROM rn)
          FROM (SELECT rank_no,
                       ROW_NUMBER() OVER (
                         PARTITION BY plan, family
                         ORDER BY GREATEST(rank_score, 0) DESC,
                                  (w_sp / window_days)
                                  * GREATEST(0, 1 - COALESCE(ret_corrected, 0) / NULLIF(family_bar, 0)) DESC,
                                  w_clk DESC, campaign_id, keyword_id) AS rn
                FROM p WHERE is_candidate))
       + (SELECT IF(COUNTIF(is_candidate) = 0, 1, 0) FROM p)
),
-- ---- v27.160 (2026-10-02, piece-1 plan Task 6): which clock keys a night (P-24), the shadow's words ----
-- K1 (P-24, R11): as_of is the New York date of the build, on every partition SP_BUILD_NEXT_WEEK_PLAN
-- v27.160 wrote — built_at at or after its deploy (2026-10-03 02:45:20+00, INFORMATION_SCHEMA.ROUTINES
-- last_altered). Partitions written before it are keyed on the Los Angeles date: the eight built
-- after 22:00 Los Angeles (2026-08-23 .. 09-30) carry an as_of one day before the New York date of
-- their build. Emptiness: no partition written since the deploy reads 1.
all_p AS (SELECT * FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK`),
k1 AS (
  SELECT 'K1 P-24: as_of is the New York date of the build on every partition written since v27.160',
         (SELECT COUNT(DISTINCT as_of) FROM all_p
          WHERE built_at >= TIMESTAMP '2026-10-03 02:45:20+00'
            AND as_of != DATE(built_at, 'America/New_York'))
       + (SELECT IF(COUNTIF(built_at >= TIMESTAMP '2026-10-03 02:45:20+00') = 0, 1, 0) FROM all_p)
),
-- K2 (P-24, R11's guard): no partition carries two calendar states (or none), on the whole history;
-- and the latest partition carries the state of its own New York date — the night it is keyed on is
-- the night its calendar was read on. The second term is what catches a partition REWRITTEN whole
-- under another night's state (the 2026-09-30 partition carries BOOST while
-- FN_PLAN_CALENDAR_STATE('2026-09-30') is OFF_PEAK; one state per partition cannot see that). It
-- reads the latest partition only: FN_PLAN_CALENDAR_STATE reads the live DIM_US_HOLIDAYS, and an
-- old partition was right under the calendar of its night. Emptiness: an empty table reads 1.
k2 AS (
  SELECT 'K2 P-24: one calendar state per partition, and the latest partition carries its own New York date state',
         (SELECT COUNTIF(n_state != 1 OR n_null > 0)
          FROM (SELECT as_of, COUNT(DISTINCT calendar_state) n_state, COUNTIF(calendar_state IS NULL) n_null
                FROM all_p GROUP BY 1))
       + (SELECT IF(COUNTIF(calendar_state IS DISTINCT FROM
                            `onyga-482313.OI.FN_PLAN_CALENDAR_STATE`(as_of)) > 0, 1, 0) FROM p)
       + (SELECT IF(COUNT(*) = 0, 1, 0) FROM p)
),
-- K3 (audit fix #25): a SHADOW row names the side its own `side` column holds. A plan-A row whose
-- side differs from the live plan's names plan A's side in words ("so plan A puts it on the good |
-- not-good side"); no plan-A row on the good side carries the not-good side's verdict, seat or queue
-- words, and no plan-A row on the not-good side carries the good side's; and no row that publishes a
-- planned bid says it carries none (P-4's clause). On the 2026-10-02 v27.159 partition: 118 shadow
-- rows sided differently from the live plan, none naming plan A's side, 54 GOOD rows reading
-- "competes for a seat at" beside "No move: the good side is never cut", 8 priced rows reading
-- "carries no planned price". Emptiness: a partition with no shadow row reads 1.
k3 AS (
  SELECT 'K3 fix #25: no shadow row names a side its side column does not hold, and no priced row says it carries no price',
         (SELECT COUNTIF(a.side != lb.side
                         AND STRPOS(a.sentence, FORMAT('so plan A puts it on the %s side',
                                                       IF(a.side = 'GOOD', 'good', 'not-good'))) = 0)
               + COUNTIF(a.side = 'GOOD'
                         AND REGEXP_CONTAINS(a.sentence, r'competes for a seat|queues at the park price|QUEUED at rank|SEAT \d+ of |OPEN PROBE at|LOSING on the window|NO SALE —|NOT SERVING —|WAITING, one order|this keyword is on the not-good side|does not compete for a seat'))
               + COUNTIF(a.side = 'NOT_GOOD'
                         AND REGEXP_CONTAINS(a.sentence, r'GOOD on the window —|HELD — |HELD, |GRACE — |No move: the good side is never cut'))
          FROM p a JOIN b lb USING (campaign_id, keyword_id)
          WHERE NOT a.is_live_plan)
       + (SELECT COUNTIF(planned_bid IS NOT NULL AND STRPOS(sentence, 'carries no planned price') > 0) FROM p)
       + (SELECT IF(COUNTIF(NOT is_live_plan) = 0, 1, 0) FROM p)
),
-- ---- v27.170 (2026-10-03, learning piece 2 Task 3 — Ori's ruling D2 (c)): a night is final once it has begun ----
-- The cutover is the v27.170 deploy of SP_BUILD_NEXT_WEEK_PLAN (INFORMATION_SCHEMA.ROUTINES
-- last_altered): F1 and F2 read only partitions whose built_at is at or after it.
-- f_dml: every write to the plan table since the cutover, from BigQuery's own job record. A build
-- that writes runs one DELETE and one INSERT on the table, as child jobs of the script that called
-- it (the orchestrator's pass or a hand CALL alike). The table keeps only a night's last write, so
-- whether that write found the night already written is read from its own DELETE: a first write
-- deletes 0 rows, a rewrite deletes the rows it replaces.
f_dml AS (
  SELECT parent_job_id, creation_time, statement_type,
         dml_statistics.inserted_row_count AS ins, dml_statistics.deleted_row_count AS del
  FROM `region-us`.INFORMATION_SCHEMA.JOBS_BY_PROJECT
  WHERE creation_time >= TIMESTAMP '2026-10-03 17:41:54+00'
    AND state = 'DONE' AND error_result IS NULL
    AND statement_type IN ('INSERT', 'DELETE')
    AND destination_table.project_id = 'onyga-482313' AND destination_table.dataset_id = 'OI'
    AND destination_table.table_id = 'FACT_PLAN_NEXT_WEEK'
),
f_part AS (  -- every night written since the cutover, within the job record's reach: its write's
             -- built_at and its rows. INFORMATION_SCHEMA.JOBS keeps 180 days of jobs, so F1 reads the
             -- nights written in the last 170 (a night older than that would read "not on record")
  SELECT as_of, MAX(built_at) AS built_at, COUNT(*) AS n
  FROM all_p
  WHERE built_at >= TIMESTAMP '2026-10-03 17:41:54+00'
    AND built_at >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 170 DAY)
  GROUP BY as_of
),
f_ins AS (  -- the INSERT that stored it: the first INSERT into the table after its built_at
  SELECT p.as_of, p.built_at, p.n, w.parent_job_id, w.ins_at, w.ins
  FROM f_part p
  LEFT JOIN (SELECT p2.as_of, i.parent_job_id, i.creation_time AS ins_at, i.ins
             FROM f_part p2 JOIN f_dml i
               ON i.statement_type = 'INSERT' AND i.creation_time >= p2.built_at
              AND i.creation_time < TIMESTAMP_ADD(p2.built_at, INTERVAL 1 HOUR)
             QUALIFY ROW_NUMBER() OVER (PARTITION BY p2.as_of ORDER BY i.creation_time) = 1) w
    ON w.as_of = p.as_of
),
f_del AS (  -- that build's DELETE of the night: the last DELETE of the same script before the INSERT
  SELECT f.*, d.del
  FROM f_ins f
  LEFT JOIN f_dml d ON d.parent_job_id = f.parent_job_id AND d.statement_type = 'DELETE'
                   AND d.creation_time <= f.ins_at
  QUALIFY ROW_NUMBER() OVER (PARTITION BY f.as_of ORDER BY d.creation_time DESC) = 1
),
-- F1 (D2 (c)): no night written since v27.170 was REWRITTEN after Los Angeles midnight of its as_of
-- (TIMESTAMP(as_of, 'America/Los_Angeles')). A write stamped after it is allowed only as the
-- night's first write (its DELETE removed nothing): a late plan is still a plan. A night whose
-- write is not on the job record (no INSERT of its row count within the hour after its built_at,
-- or no DELETE before that INSERT in the same script) cannot be shown to be a first write and
-- counts. It reads the nights written in the last 170 days: the job record keeps 180. Emptiness: no
-- such night reads 1.
f1 AS (
  SELECT 'F1 D2 (c): no night written since v27.170 was rewritten after Los Angeles midnight of its as_of (a late first write is allowed)',
         (SELECT COUNTIF(parent_job_id IS NULL OR ins IS DISTINCT FROM n OR del IS NULL
                         OR (built_at >= TIMESTAMP(as_of, 'America/Los_Angeles') AND del > 0))
          FROM f_del)
       + (SELECT IF(COUNT(*) = 0, 1, 0) FROM f_part)
),
-- F2 (D2 (c)): every row written since v27.170 carries a builder_version (vNN.NNN), and every row
-- written since the DEPLOYED builder was deployed carries the version its description opens with
-- (so a deploy that forgets to bump builder_version_d is caught on its first night). The routine
-- must be found with a version (else 1). Emptiness: no row written since the cutover reads 1.
f_rt AS (
  SELECT REGEXP_EXTRACT(ddl, r'description\s*=\s*"(v\d+\.\d+)') AS v, last_altered
  FROM `onyga-482313.OI.INFORMATION_SCHEMA.ROUTINES`
  WHERE routine_name = 'SP_BUILD_NEXT_WEEK_PLAN'
),
f2 AS (
  SELECT 'F2 D2 (c): every row written since v27.170 carries a builder_version, the deployed builder version on rows written since its deploy',
         (SELECT COUNTIF(builder_version IS NULL OR NOT REGEXP_CONTAINS(builder_version, r'^v\d+\.\d+$'))
          FROM all_p WHERE built_at >= TIMESTAMP '2026-10-03 17:41:54+00')
       + (SELECT COUNTIF(a.builder_version IS DISTINCT FROM r.v)
          FROM all_p a JOIN f_rt r ON a.built_at >= r.last_altered)
       + (SELECT IF(COUNT(*) = 1 AND MAX(v) IS NOT NULL, 0, 1) FROM f_rt)
       + (SELECT IF(COUNTIF(built_at >= TIMESTAMP '2026-10-03 17:41:54+00') = 0, 1, 0) FROM all_p)
)
SELECT check_name, violations, IF(violations = 0, 'PASS', 'FAIL') AS result
FROM (SELECT * FROM c01 UNION ALL SELECT * FROM c02 UNION ALL SELECT * FROM c03
      UNION ALL SELECT * FROM c04 UNION ALL SELECT * FROM c05 UNION ALL SELECT * FROM c06
      UNION ALL SELECT * FROM c07 UNION ALL SELECT * FROM c08 UNION ALL SELECT * FROM c09
      UNION ALL SELECT * FROM c10 UNION ALL SELECT * FROM c11 UNION ALL SELECT * FROM c12
      UNION ALL SELECT * FROM c13 UNION ALL SELECT * FROM c14 UNION ALL SELECT * FROM c15
      UNION ALL SELECT * FROM c16 UNION ALL SELECT * FROM c17 UNION ALL SELECT * FROM c18
      UNION ALL SELECT * FROM c19 UNION ALL SELECT * FROM c20 UNION ALL SELECT * FROM c21
      UNION ALL SELECT * FROM c22 UNION ALL SELECT * FROM c23 UNION ALL SELECT * FROM c24
      UNION ALL SELECT * FROM c25 UNION ALL SELECT * FROM c26 UNION ALL SELECT * FROM m1
      UNION ALL SELECT * FROM m2 UNION ALL SELECT * FROM m3 UNION ALL SELECT * FROM t1
      UNION ALL SELECT * FROM t2 UNION ALL SELECT * FROM t3 UNION ALL SELECT * FROM t4
      UNION ALL SELECT * FROM t5 UNION ALL SELECT * FROM k1 UNION ALL SELECT * FROM k2
      UNION ALL SELECT * FROM k3 UNION ALL SELECT * FROM f1 UNION ALL SELECT * FROM f2)
ORDER BY check_name;
