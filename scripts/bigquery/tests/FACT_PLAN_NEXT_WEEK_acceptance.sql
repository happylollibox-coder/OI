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
c03 AS (
  SELECT 'C03 pot = the GOOD side window spend per day, to the cent (P-2)',
         COUNTIF(ABS(pot_per_day - good_spend) > 0.01)
  FROM (
    SELECT plan, family, MAX(pot_per_day) pot_per_day,
           SAFE_DIVIDE(SUM(IF(side = 'GOOD' AND NOT holdout, w_sp, 0)), MAX(window_days)) good_spend
    FROM p GROUP BY 1, 2)
),
c04 AS (
  SELECT 'C04 allowance = share x pot, ramped one step of the gap (P-2, P-8)',
         COUNTIF(ABS(allowance_target_per_day - allowance_share * pot_per_day) > 0.01
                 OR ABS(allowance_ramped_per_day
                        - GREATEST(allowance_share * pot_per_day,
                                   notgood_today_per_day
                                   - (notgood_today_per_day - allowance_share * pot_per_day) / ramp_steps)) > 0.01)
  FROM (SELECT DISTINCT plan, family, allowance_share, pot_per_day, allowance_target_per_day,
                        allowance_ramped_per_day, notgood_today_per_day, ramp_steps FROM p)
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
c08 AS (
  SELECT 'C08 no holdout campaign is repriced, parked, paused or seated by the plan (house rule)',
         COUNTIF(holdout AND move NOT IN ('NONE', 'NONE_HOLDOUT'))
       + COUNTIF(holdout AND seat_no IS NOT NULL)
       + COUNTIF(holdout AND is_candidate)
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
c11 AS (
  SELECT "C11 budgets: outside the forbidden band, over $1.00, and never under the money the plan can SEE inside them (P-4)",
         (SELECT COUNTIF(campaign_planned_budget > 20.00 AND campaign_planned_budget < 32.00
                         AND campaign_budget_basis NOT IN
                             ('NO_MOVE_UNMEASURED', 'NO_MOVE_BRAND_DEFENSE'))
                + COUNTIF(campaign_planned_budget < 1.00)
                + COUNTIF(campaign_planned_budget IS NULL) FROM p)
       + (SELECT COUNTIF(bud < good_spend - 0.005) + COUNTIF(bud < need - 0.005)
          FROM (SELECT plan, campaign_id, MAX(campaign_planned_budget) bud,
                       SUM(IF(side = 'GOOD', planned_spend_per_day, 0)) good_spend,
                       -- v27.138: the plan's own arithmetic counts a queued keyword at ZERO, and
                       -- the plan's own PARK sentence says parking does not stop a spend. Flooring
                       -- at the arithmetic is satisfied by construction; flooring at the MONEY is
                       -- what stops a cap being ramped towards a figure nobody believes.
                       SUM(planned_spend_per_day)
                       + SUM(IF(is_candidate AND seat_no IS NULL AND move != 'PAUSE',
                                COALESCE(SAFE_DIVIDE(w_sp, window_days), 0), 0)) need
                FROM p GROUP BY 1, 2))
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
c15 AS (
  SELECT 'C15 pot + not-good = the whole non-holdout window spend per day, to the cent (P-2)',
         COUNTIF(ABS(pot + notgood - total) > 0.01)
  FROM (SELECT plan, family, MAX(pot_per_day) pot, MAX(notgood_today_per_day) notgood,
               SAFE_DIVIDE(SUM(IF(NOT holdout, w_sp, 0)), MAX(window_days)) total
        FROM p GROUP BY 1, 2)
),
c16 AS (
  SELECT 'C16 the ramp step is a report inside its own bounds, and the settings are the declared ones',
         COUNTIF(ramp_step < 1 OR ramp_step > ramp_steps OR ramp_steps < 1
                 OR allowance_share <= 0 OR allowance_share > 1
                 OR calendar_state IS NULL OR sentence IS NULL OR family IS NULL)
  FROM p
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
c26 AS (
  SELECT 'C26 P-14c: every HELD row has a very good last day and is on the good side; no sale-less window is held',
         COUNTIF(verdict = 'HELD_UNSETTLED' AND (NOT COALESCE(last_day_strong, FALSE) OR side != 'GOOD'))
       + COUNTIF(verdict = 'HELD_UNSETTLED' AND COALESCE(w_ord, 0) = 0)
  FROM b
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
      UNION ALL SELECT * FROM c25 UNION ALL SELECT * FROM c26)
ORDER BY check_name;
