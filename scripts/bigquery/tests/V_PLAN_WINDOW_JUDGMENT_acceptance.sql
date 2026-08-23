-- =============================================================================================
-- V_PLAN_SETTLE_COMPLETION + V_PLAN_WINDOW_JUDGMENT acceptance — v27.133 (2026-08-23).
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
--   C06 P-14b: no keyword that was good sits on the not-good side while its window is unsettled,
--       and every HELD_UNSETTLED row is on the good side with a settle-due date in the future.
--   C07 P-3: a GOOD row has min_orders OBSERVED orders (counts are never inflated) unless the
--       grace or the guard put it there; every row names decided_by.
--   C08 P-6/P-7: every not-good row has a planned price at or above its own floor, a seat cost
--       that is not negative and a rank score that is not NULL.
--   C09 P-14a: the completion curve is monotone in age, above zero and never above 1.
--   C10 P-14a: the correction is exactly ONE published division — corrected x effective factor
--       reconstructs the raw window gross profit, and the effective factor is in (0, 1].
--   C11 every row carries a plain sentence, an arm sentence, and a declared settle_arm.
--   C12 P-5 (§9 "no settled winner is moved to the not-good side after a single quiet window").
--   C13 the holdout is never a candidate (house rule, from its eligible_from).
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
c06 AS (
  SELECT 'C06 P-14b no unsettled demotion of a keyword that was good',
         COUNTIF((side_b = 'NOT_GOOD' AND was_good AND NOT settled)
                 OR (settle_arm = 'HELD_UNSETTLED'
                     AND (settle_due_on IS NULL
                          OR settle_due_on <= CURRENT_DATE('America/Los_Angeles')
                          OR side_b != 'GOOD')))
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
                                       'HELD_UNSETTLED','UNCORRECTED_NO_CURVE'))
  FROM j
),
c12 AS (
  SELECT 'C12 P-5 no settled winner demoted on a single quiet window',
         COUNTIF(ladder_state IN ('WINNER','PACED_WINNER') AND w_ord < min_orders
                 AND side_b = 'NOT_GOOD')
  FROM j
),
c13 AS (
  SELECT 'C13 the holdout is never a candidate',
         COUNTIF(holdout AND is_candidate)
  FROM j
)
SELECT check_name, violations, IF(violations = 0, 'PASS', 'FAIL') AS result
FROM (SELECT * FROM c01 UNION ALL SELECT * FROM c02 UNION ALL SELECT * FROM c03
      UNION ALL SELECT * FROM c04 UNION ALL SELECT * FROM c05 UNION ALL SELECT * FROM c06
      UNION ALL SELECT * FROM c07 UNION ALL SELECT * FROM c08 UNION ALL SELECT * FROM c09
      UNION ALL SELECT * FROM c10 UNION ALL SELECT * FROM c11 UNION ALL SELECT * FROM c12
      UNION ALL SELECT * FROM c13)
ORDER BY check_name;
