-- =============================================================================================
-- FACT_PLAN_NEXT_WEEK acceptance — v27.138 (2026-08-24). The spec's §9 guarantees, read on the
-- latest as_of partition. EVERY ROW MUST READ PASS.
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
--       fence: window_to = LEAST(watermark - 1, as_of - 2).
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
-- =============================================================================================
WITH p AS (
  SELECT * FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK`
  WHERE as_of = (SELECT MAX(as_of) FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK`)
),
b AS (SELECT * FROM p WHERE is_live_plan),
j AS (SELECT * FROM `onyga-482313.OI.V_PLAN_WINDOW_JUDGMENT`),
led AS (
  SELECT family, CAST(campaign_id AS STRING) AS campaign_id,
         CAST(keyword_id AS STRING) AS keyword_id, MIN(seat_no) AS seat_no
  FROM `onyga-482313.OI.DE_FAMILY_SEAT_LEDGER`
  WHERE closed_on IS NULL
  GROUP BY 1, 2, 3
),
c01 AS (
  SELECT 'C01 window is complete days only and fenced to age 2 (P-10, P-14a)' AS check_name,
         COUNTIF(window_to != LEAST(DATE_SUB(watermark, INTERVAL 1 DAY),
                                    DATE_SUB(as_of, INTERVAL 2 DAY))
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
c06 AS (
  SELECT 'C06 one move per CANDIDATE, none on the good side, none where there is nothing to repair (P-4, §9)',
         COUNTIF(side = 'GOOD' AND move != 'NONE')
       + COUNTIF(is_candidate AND move NOT IN ('REPRICE','HOLD_AT_PRICE','PARK','HOLD_AT_PARK','PAUSE'))
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
          FROM p WHERE move = 'REPRICE')
       + (SELECT COUNTIF(planned_bid IS NOT NULL OR seat_cost_per_day IS NOT NULL)
          FROM p WHERE side = 'GOOD')
),
c13 AS (
  SELECT 'C13 the live plan reproduces the judgement view row for row: side, verdict, candidacy',
         (SELECT COUNT(*) FROM b FULL OUTER JOIN j
            ON j.campaign_id = b.campaign_id AND j.keyword_id = b.keyword_id
          WHERE b.campaign_id IS NULL OR j.campaign_id IS NULL
             OR b.side != j.side_b OR b.verdict != j.verdict
             OR b.is_candidate != j.is_candidate)
),
c14 AS (
  SELECT 'C14 every candidate has exactly ONE of a seat or a queue position (§9)',
         COUNTIF(is_candidate AND seat_no IS NULL AND move NOT IN ('PARK','HOLD_AT_PARK','PAUSE'))
       + COUNTIF(is_candidate AND seat_no IS NOT NULL AND move NOT IN ('REPRICE','HOLD_AT_PRICE'))
       + COUNTIF(is_candidate AND rank_no IS NULL)
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
c17 AS (
  SELECT 'C17 no seat number the register still holds OPEN for another keyword is reissued (§9)',
         (SELECT COUNT(*)
          FROM p JOIN led l ON l.family = p.family AND l.seat_no = p.seat_no
          WHERE p.seat_no IS NOT NULL AND l.keyword_id != p.keyword_id)
       + (SELECT COUNT(*)
          FROM p JOIN led l ON l.family = p.family
                           AND l.campaign_id = p.campaign_id AND l.keyword_id = p.keyword_id
          WHERE p.seat_no IS NOT NULL AND l.seat_no != p.seat_no)
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
       + (SELECT COUNTIF(is_candidate AND (seat_no IS NOT NULL) = (move IN ('PARK','HOLD_AT_PARK','PAUSE')))
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
-- does not hold an open row for — and the register only admits LADDER occupant states, so the
-- plan's AT_BAR and DEAD seats can never acquire one. Trivially green while only one partition
-- exists; it is the check that goes red the first night a number moves.
c23 AS (
  SELECT 'C23 §9: a continuing occupant keeps its seat number from one night to the next',
         (SELECT COUNT(*)
          FROM p JOIN (
            SELECT plan, family, CAST(campaign_id AS STRING) campaign_id,
                   CAST(keyword_id AS STRING) keyword_id, MIN(seat_no) seat_no
            FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK`
            WHERE seat_no IS NOT NULL
              AND as_of = (SELECT MAX(as_of) FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK`
                           WHERE as_of < (SELECT MAX(as_of)
                                          FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK`))
            GROUP BY 1, 2, 3, 4) h
            USING (plan, family, campaign_id, keyword_id)
          WHERE p.seat_no IS NOT NULL AND h.seat_no != p.seat_no
            AND NOT EXISTS (SELECT 1 FROM led l
                            WHERE l.family = p.family AND l.seat_no = h.seat_no
                              AND l.keyword_id != p.keyword_id))
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
      UNION ALL SELECT * FROM m2 UNION ALL SELECT * FROM m3)
ORDER BY check_name;
