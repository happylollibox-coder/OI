-- =============================================================================================
-- FACT_PLAN_NEXT_WEEK acceptance — v27.136 (2026-08-23). The spec's §9 guarantees, read on the
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
-- =============================================================================================
WITH p AS (
  SELECT * FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK`
  WHERE as_of = (SELECT MAX(as_of) FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK`)
),
b AS (SELECT * FROM p WHERE is_live_plan),
j AS (SELECT * FROM `onyga-482313.OI.V_PLAN_WINDOW_JUDGMENT`),
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
       + COUNTIF(is_candidate AND move NOT IN ('REPRICE','HOLD_AT_PRICE','PARK','PAUSE'))
       + COUNTIF(NOT is_candidate AND holdout AND move != 'NONE_HOLDOUT')
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
c09 AS (
  SELECT 'C09 P-14: every row names its arm; no unsettled demotion of a keyword that was good AND served',
         COUNTIF(settle_arm IS NULL OR decided_by IS NULL
                 OR (side = 'NOT_GOOD' AND was_good AND served AND NOT settled))
  FROM b
),
c10 AS (
  SELECT 'C10 P-12: every repriced seat carries a verdict date in the future',
         COUNTIF(move = 'REPRICE' AND (verdict_date IS NULL OR verdict_date <= as_of))
       + COUNTIF(move != 'REPRICE' AND verdict_date IS NOT NULL)
  FROM p
),
c11 AS (
  SELECT 'C11 budgets: never in the forbidden $20.01-$31.99 band, never under $1.00, never under the good side (P-4)',
         (SELECT COUNTIF(campaign_planned_budget > 20.00 AND campaign_planned_budget < 32.00)
                + COUNTIF(campaign_planned_budget < 1.00)
                + COUNTIF(campaign_planned_budget IS NULL) FROM p)
       + (SELECT COUNTIF(bud < good_spend - 0.005)
          FROM (SELECT plan, campaign_id, MAX(campaign_planned_budget) bud,
                       SUM(IF(side = 'GOOD', planned_spend_per_day, 0)) good_spend
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
         COUNTIF(is_candidate AND seat_no IS NULL AND move NOT IN ('PARK','PAUSE'))
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
)
SELECT check_name, violations, IF(violations = 0, 'PASS', 'FAIL') AS result
FROM (SELECT * FROM c01 UNION ALL SELECT * FROM c02 UNION ALL SELECT * FROM c03
      UNION ALL SELECT * FROM c04 UNION ALL SELECT * FROM c05 UNION ALL SELECT * FROM c06
      UNION ALL SELECT * FROM c07 UNION ALL SELECT * FROM c08 UNION ALL SELECT * FROM c09
      UNION ALL SELECT * FROM c10 UNION ALL SELECT * FROM c11 UNION ALL SELECT * FROM c12
      UNION ALL SELECT * FROM c13 UNION ALL SELECT * FROM c14 UNION ALL SELECT * FROM c15
      UNION ALL SELECT * FROM c16)
ORDER BY check_name;
