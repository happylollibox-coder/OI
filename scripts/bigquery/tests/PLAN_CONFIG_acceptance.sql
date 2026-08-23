-- =============================================================================================
-- DE_PLAN_CONFIG + FN_PLAN_CALENDAR_STATE acceptance — v27.132 (2026-08-23).
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
--   C06 every seed row carries the DECLARED SENTINEL updated_at, never a deploy-time clock —
--       so re-running the DDL can never out-rank, by recency, a row Ori entered by hand. This
--       is the check that failed on v27.130, where the seed carried CURRENT_TIMESTAMP().
--   C07 where a state carries a row someone entered by hand, that row is the ACTIVE WINNER: no
--       plan_seed row may win a state Ori has ruled on.
--   C08 the plan's window agrees with the house's OLDER window authority for today's state.
--       V_PEAK_WINDOW_RULE + DE_PEAK_WINDOW_OVERRIDE already answer "3 or 7 in a peak" on Ori's
--       evidence discipline, and their re-measure clocks can grant a 7. P-11 says one engine, so
--       DE_PLAN_CONFIG is the plan's authority — but the two must not disagree silently. When
--       this check goes red, someone rules; it is not a bug to be patched away in the view.
--   C09 every ACTIVE seed row still carries the SETTINGS the DDL declares. This is the alarm for
--       the v27.131 defect: that guard keyed on updated_by, so an UPDATE IN PLACE of a seeded
--       row (`SET allowance_share = 0.33 WHERE calendar_state = 'PEAK' AND is_active`) left
--       updated_by = 'plan_seed' and the next re-deploy silently reverted it. v27.132 keys the
--       DELETE on the VALUES, so the edit now survives — and this check makes it VISIBLE rather
--       than silent: a plan_seed row whose settings no longer match the declaration is a hand
--       change wearing the seed's label, and the fix is to retire it and insert an owned row
--       (the SOP's recipe). The seed values below are DECLARED CONSTANTS copied from the DDL,
--       not measurements (Standing Rule 0 exempt); if the DDL's declared seed changes, change
--       them here in the same commit.
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
c06 AS (
  SELECT 'C06 seed rows carry the declared sentinel updated_at' AS check_name,
         COUNTIF(updated_at != TIMESTAMP '2026-08-23 00:00:00 UTC') AS violations
  FROM `onyga-482313.OI.DE_PLAN_CONFIG`
  WHERE updated_by = 'plan_seed'
),
c07 AS (
  SELECT 'C07 a hand-entered row always wins its state' AS check_name,
         COUNT(*) AS violations
  FROM (
    SELECT calendar_state, updated_by
    FROM `onyga-482313.OI.DE_PLAN_CONFIG`
    WHERE is_active
    QUALIFY ROW_NUMBER() OVER (PARTITION BY calendar_state ORDER BY updated_at DESC) = 1
  ) w
  WHERE w.updated_by = 'plan_seed'
    AND EXISTS (SELECT 1 FROM `onyga-482313.OI.DE_PLAN_CONFIG` o
                WHERE o.calendar_state = w.calendar_state AND o.updated_by != 'plan_seed')
),
c08 AS (
  SELECT 'C08 plan window agrees with V_PEAK_WINDOW_RULE today' AS check_name,
         COUNTIF(p.window_days != r.w_days) AS violations
  FROM (SELECT w_days FROM `onyga-482313.OI.V_PEAK_WINDOW_RULE`) r
  CROSS JOIN (
    SELECT window_days
    FROM `onyga-482313.OI.DE_PLAN_CONFIG`
    WHERE is_active
      AND calendar_state = `onyga-482313.OI.FN_PLAN_CALENDAR_STATE`(CURRENT_DATE('America/New_York'))
    QUALIFY ROW_NUMBER() OVER (PARTITION BY calendar_state ORDER BY updated_at DESC) = 1
  ) p
),
c09 AS (
  SELECT 'C09 active seed rows still carry the declared seed settings' AS check_name,
         COUNTIF(sd.calendar_state IS NULL) AS violations
  FROM `onyga-482313.OI.DE_PLAN_CONFIG` t
  LEFT JOIN UNNEST([
    STRUCT('OFF_PEAK' AS calendar_state, 7 AS window_days, 0.20 AS allowance_share,
           'B' AS live_plan, 3 AS ramp_steps, 2 AS min_orders),
    STRUCT('BOOST', 3, 0.50, 'B', 3, 2),
    STRUCT('PEAK',  3, 0.20, 'B', 3, 2)
  ]) sd
    ON  sd.calendar_state  = t.calendar_state
    AND sd.window_days     = t.window_days
    AND sd.allowance_share = t.allowance_share
    AND sd.live_plan       = t.live_plan
    AND sd.ramp_steps      = t.ramp_steps
    AND sd.min_orders      = t.min_orders
  WHERE t.updated_by = 'plan_seed' AND t.is_active
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
      UNION ALL SELECT * FROM c04 UNION ALL SELECT * FROM c05
      UNION ALL SELECT * FROM c06 UNION ALL SELECT * FROM c07 UNION ALL SELECT * FROM c08
      UNION ALL SELECT * FROM c09)
ORDER BY check_name;
