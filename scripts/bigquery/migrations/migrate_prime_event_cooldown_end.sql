-- Migration: fill cooldown_start / cooldown_end on prime_event rows (2026-08-01, Ori-approved).
--
-- WHY: every season test in the platform is `CURRENT_DATE BETWEEN boost_start AND cooldown_end`
-- (V_LAUNCH_POPULATION, V_OOB_BUDGET_PHASE, V_KEYWORD_LIFT, both launch views, the coacher band
-- season split). All 3 prime_event rows shipped with cooldown_end NULL, so `BETWEEN` was never
-- true and Prime could not flip PEAK anywhere — peak budget caps ($30), peak windows (3d/7d) and
-- PEAK band cells silently never activated during Prime.
--
-- VALUES: the dominant gift_season pattern in this table — cooldown_start = holiday_date − 1 day,
-- cooldown_end = holiday_date + 3 days (holiday_date is the event's END for multi-day Prime).
-- Targeted UPDATE only: the live table deliberately differs from the repo seed DDL
-- (see memory/prime-day-blitz history) — never re-run DELETE+INSERT seeds here.
UPDATE `onyga-482313.OI.DIM_US_HOLIDAYS`
SET cooldown_start = DATE_SUB(holiday_date, INTERVAL 1 DAY),
    cooldown_end   = DATE_ADD(holiday_date, INTERVAL 3 DAY)
WHERE category = 'prime_event' AND cooldown_end IS NULL;
