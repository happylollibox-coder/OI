-- =============================================================================================
-- DE_PLAN_CONFIG + FN_PLAN_CALENDAR_STATE acceptance — v27.130 (2026-08-23).
-- EVERY ROW MUST READ PASS.
--   bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "$(grep -v '^--' FILE)"
-- Spec: docs/superpowers/specs/2026-08-23-next-week-money-plan-design.md P-13, §3.
-- SOP: architecture/NEXT_WEEK_MONEY.md
--
-- Checks:
--   C01 exactly one ACTIVE row per calendar state, and all three states are present
--   C02 settings in range: window_days 1..28, allowance_share in (0,1], live_plan A|B,
--       ramp_steps >= 1, min_orders >= 1, and a description a person can actually read
--   C03 the function reads the LIVE calendar on declared dates, and PEAK WINS over a BOOST that
--       overlaps it (2026-10-15 sits inside Halloween's peak AND inside Christmas's run-up)
--   C04 the function never returns NULL or an unknown state over a two-year sweep
--   C05 the three states the config declares are exactly the states the function can return
--       (a state the function emits with no config row would leave the plan with no window)
--
-- C03 dates are DECLARED CALENDAR DATES read off DIM_US_HOLIDAYS, not measurements (Standing
-- Rule 0 exempt). If Ori edits the live calendar these dates move with it and this check is the
-- first thing that says so — which is the point of asserting against the live table.
-- =============================================================================================
WITH cfg AS (
  SELECT calendar_state, COUNT(*) AS n
  FROM `onyga-482313.OI.DE_PLAN_CONFIG`
  WHERE is_active
  GROUP BY 1
),
c01 AS (
  SELECT 'C01 one active row per state, three states' AS check_name,
         (SELECT COUNT(*) FROM cfg WHERE n != 1)
       + (SELECT 3 - COUNT(DISTINCT calendar_state) FROM cfg
          WHERE calendar_state IN ('OFF_PEAK', 'BOOST', 'PEAK')) AS violations
),
c02 AS (
  SELECT 'C02 settings in range and a readable description' AS check_name,
         COUNTIF(window_days NOT BETWEEN 1 AND 28
                 OR allowance_share <= 0 OR allowance_share > 1
                 OR live_plan NOT IN ('A', 'B')
                 OR ramp_steps < 1
                 OR min_orders < 1
                 OR description IS NULL OR LENGTH(TRIM(description)) < 20) AS violations
  FROM `onyga-482313.OI.DE_PLAN_CONFIG`
  WHERE is_active
),
c03 AS (
  SELECT 'C03 calendar reads PEAK / BOOST / OFF_PEAK on declared dates' AS check_name,
         COUNTIF(NOT ok) AS violations
  FROM UNNEST([
    -- Christmas peak (peak_start 2026-11-03 .. cooldown_end 2026-12-28)
    STRUCT(`onyga-482313.OI.FN_PLAN_CALENDAR_STATE`(DATE '2026-12-20') = 'PEAK'     AS ok),
    -- Back to School run-up (boost_start 2026-08-01 .. peak_start 2026-08-10)
    STRUCT(`onyga-482313.OI.FN_PLAN_CALENDAR_STATE`(DATE '2026-08-05') = 'BOOST'    AS ok),
    -- Back to School peak (peak_start 2026-08-10 .. holiday_date 2026-09-14 + 3, cooldown NULL)
    STRUCT(`onyga-482313.OI.FN_PLAN_CALENDAR_STATE`(DATE '2026-08-23') = 'PEAK'     AS ok),
    -- between seasons: after Prime Day's cooldown, before Back to School's boost
    STRUCT(`onyga-482313.OI.FN_PLAN_CALENDAR_STATE`(DATE '2026-07-15') = 'OFF_PEAK' AS ok),
    -- Christmas run-up (boost_start 2026-10-01), still ahead of Halloween's peak_start 2026-10-10
    STRUCT(`onyga-482313.OI.FN_PLAN_CALENDAR_STATE`(DATE '2026-10-05') = 'BOOST'    AS ok),
    -- PEAK WINS: 2026-10-15 is inside Halloween's peak AND inside Christmas's run-up
    STRUCT(`onyga-482313.OI.FN_PLAN_CALENDAR_STATE`(DATE '2026-10-15') = 'PEAK'     AS ok)
  ])
),
c04 AS (
  SELECT 'C04 never NULL, never an unknown state (2025-01-01 .. 2026-12-31)' AS check_name,
         COUNTIF(`onyga-482313.OI.FN_PLAN_CALENDAR_STATE`(d) IS NULL
                 OR `onyga-482313.OI.FN_PLAN_CALENDAR_STATE`(d)
                    NOT IN ('OFF_PEAK', 'BOOST', 'PEAK')) AS violations
  FROM UNNEST(GENERATE_DATE_ARRAY(DATE '2025-01-01', DATE '2026-12-31')) d
),
c05 AS (
  SELECT 'C05 every state the function emits has an active config row' AS check_name,
         (SELECT COUNT(*) FROM (
            SELECT `onyga-482313.OI.FN_PLAN_CALENDAR_STATE`(d) AS s
            FROM UNNEST(GENERATE_DATE_ARRAY(DATE '2025-01-01', DATE '2026-12-31')) d
            GROUP BY 1
          ) emitted
          LEFT JOIN cfg ON cfg.calendar_state = emitted.s
          WHERE cfg.calendar_state IS NULL) AS violations
)
SELECT check_name, violations, IF(violations = 0, 'PASS', 'FAIL') AS result
FROM (SELECT * FROM c01 UNION ALL SELECT * FROM c02 UNION ALL SELECT * FROM c03
      UNION ALL SELECT * FROM c04 UNION ALL SELECT * FROM c05)
ORDER BY check_name;
