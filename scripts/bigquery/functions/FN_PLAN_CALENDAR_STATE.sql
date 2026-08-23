-- =============================================================================================
-- FN_PLAN_CALENDAR_STATE(d) — v27.130 (2026-08-23): which calendar state a date is in, read
-- from the LIVE DIM_US_HOLIDAYS (the authority; the repo seed is stale — config.yaml says so,
-- and the Prime Day BLITZ fix is the scar that proves it).
--   PEAK     d BETWEEN peak_start AND COALESCE(cooldown_end, holiday_date + 3)   (wins)
--   BOOST    d >= boost_start AND d < COALESCE(peak_start, holiday_date)
--   OFF_PEAK otherwise
--
-- PEAK WINS BY CONSTRUCTION, and the win is not theoretical: the seasons overlap on the live
-- calendar, so a single date is routinely inside one season's peak and another season's run-up
-- at the same time. The plan needs ONE state per date to pick ONE window and ONE share, and the
-- tighter window is the safer read while real money is moving — so a peak anywhere beats a
-- run-up everywhere. PLAN_CONFIG_acceptance C03 asserts the precedence on a live overlap date
-- rather than trusting this paragraph.
--
-- Categories = the four the house gate V_SEASON_PEAK_GATE uses. The season end follows the
-- gate's COALESCE(cooldown_end, holiday_date + 3) (Back to School and Halloween carry NULL
-- cooldowns). Rows with no boost_start cannot describe a run-up and are skipped.
-- Callers pass CURRENT_DATE('America/New_York') (the calendar is US Eastern) or a historical
-- date (the backtest). A scalar subquery over a small table — cheap, and it constant-folds.
-- Never returns NULL: the COALESCE lands on OFF_PEAK, and the aggregate always yields a row.
-- Spec: docs/superpowers/specs/2026-08-23-next-week-money-plan-design.md P-13, §3.
-- SOP: architecture/NEXT_WEEK_MONEY.md
-- =============================================================================================
CREATE OR REPLACE FUNCTION `onyga-482313.OI.FN_PLAN_CALENDAR_STATE`(d DATE)
RETURNS STRING
OPTIONS (description = "v27.130 (2026-08-23): calendar state of a date for the next-week money plan — PEAK (peak_start .. COALESCE(cooldown_end, holiday_date+3)) wins over BOOST (boost_start .. the day before COALESCE(peak_start, holiday_date)) over OFF_PEAK; categories gift_season/prime_event/back_to_school/seasonal, read from the LIVE DIM_US_HOLIDAYS, never a date literal. PEAK wins because the live seasons overlap and the plan needs one window and one share per date; the tighter window is the safer read. Never returns NULL. Pair with DE_PLAN_CONFIG for the window, the share, the ramp and the order floor. Acceptance: scripts/bigquery/tests/PLAN_CONFIG_acceptance.sql. Spec P-13, §3.")
AS ((
  SELECT COALESCE(
    IF(COUNTIF(d BETWEEN peak_start
                     AND COALESCE(cooldown_end, DATE_ADD(holiday_date, INTERVAL 3 DAY))) > 0,
       'PEAK', NULL),
    IF(COUNTIF(d >= boost_start AND d < COALESCE(peak_start, holiday_date)) > 0,
       'BOOST', NULL),
    'OFF_PEAK')
  FROM `onyga-482313.OI.DIM_US_HOLIDAYS`
  WHERE category IN ('gift_season', 'prime_event', 'back_to_school', 'seasonal')
    AND boost_start IS NOT NULL
));
