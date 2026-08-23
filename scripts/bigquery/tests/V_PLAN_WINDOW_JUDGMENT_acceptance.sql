-- =============================================================================================
-- V_PLAN_SETTLE_COMPLETION + V_PLAN_WINDOW_JUDGMENT acceptance — v27.134 (2026-08-23).
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
--   C06 P-14b: no keyword that was good AND SERVED IN THE WINDOW sits on the not-good side while
--       its window is unsettled, and every HELD_UNSETTLED row is on the good side, with a
--       settle-due date in the future AND a window it actually served in. The service clause is
--       the doctrine, not a loophole: the guard exists because sales are still ARRIVING, and a
--       keyword with no clicks in the window has none in flight (v27.134).
--   C07 P-3: a GOOD row has min_orders OBSERVED orders (counts are never inflated) unless the
--       grace or the guard put it there; every row names decided_by.
--   C08 P-6/P-7: every not-good row has a planned price at or above its own floor, a seat cost
--       that is not negative and a rank score that is not NULL.
--   C09 P-14a: the completion curve is monotone in age, above zero and never above 1.
--   C10 P-14a: the correction is exactly ONE published division — corrected x effective factor
--       reconstructs the raw window gross profit, and the effective factor is in (0, 1].
--   C11 every row carries a plain sentence, an arm sentence, a declared settle_arm and a declared
--       park-price source.
--   C12 P-5 as WRITTEN — "one quiet window, held; two quiet windows in a row and rule B stands".
--       A ladder-settled winner with a quiet window is on the good side UNLESS last night's live
--       plan already granted it a grace, and no grace is granted twice in a row (v27.134: the
--       view used to implement the grant and not the limit, making grace permanent).
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
  SELECT 'C06 P-14b no unsettled demotion of a keyword that was good and served',
         COUNTIF((side_b = 'NOT_GOOD' AND was_good AND NOT settled AND served)
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
  SELECT 'C12 P-5 one quiet window is held, and grace is never granted twice in a row',
         COUNTIF((ladder_state IN ('WINNER','PACED_WINNER') AND w_ord < min_orders
                  AND side_b = 'NOT_GOOD' AND NOT prior_grace)
                 OR (verdict = 'GRACE' AND prior_grace))
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
)
SELECT check_name, violations, IF(violations = 0, 'PASS', 'FAIL') AS result
FROM (SELECT * FROM c01 UNION ALL SELECT * FROM c02 UNION ALL SELECT * FROM c03
      UNION ALL SELECT * FROM c04 UNION ALL SELECT * FROM c05 UNION ALL SELECT * FROM c06
      UNION ALL SELECT * FROM c07 UNION ALL SELECT * FROM c08 UNION ALL SELECT * FROM c09
      UNION ALL SELECT * FROM c10 UNION ALL SELECT * FROM c11 UNION ALL SELECT * FROM c12
      UNION ALL SELECT * FROM c13 UNION ALL SELECT * FROM c14 UNION ALL SELECT * FROM c15
      UNION ALL SELECT * FROM c16 UNION ALL SELECT * FROM c17)
ORDER BY check_name;
