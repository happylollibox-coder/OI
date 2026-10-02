-- =============================================================================================
-- PLAN_SCORECARD acceptance — v27.154 (2026-10-01; follow-up the same day: C09 restated, C10
-- replaced, C11 and C12 added; second follow-up, 2026-10-01 LA / 10-02 UTC: C13 added, C12 restated, CM widened).
-- V_PLAN_SCORECARD / FN_PLAN_SCORECARD (plan Task 5's grade) and the
-- nine plan_* checks Task A put on V_ENGINE_HEALTH. EVERY ROW MUST READ PASS.
--   bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "$(grep -v '^--' FILE)"
-- Objects: scripts/bigquery/functions/FN_PLAN_SCORECARD.sql, scripts/bigquery/views/V_PLAN_SCORECARD.sql.
-- SOP: architecture/NEXT_WEEK_MONEY.md §6 "Grading". Spec §5, P-9, P-13, P-14b/c.
-- Companion: scripts/bigquery/tests/check_plan_scorecard_hint_branches.py runs the function's OWN
-- body on doctored copies of the plan table, which this file cannot (see "WHAT THIS FILE DOES NOT
-- PROVE" below).
--
-- WHY THE SUITE CANNOT PASS ON EMPTINESS. On 2026-10-01 the scorecard is young: one graded week
-- (the August nights), every RECOMMENDATION is WAIT, and no guard decision has settled (the guard
-- columns exist from the 2026-09-28 partition; the first window settles 2026-10-03). Here:
--   * C04 and C08 hold the scorecard to what the plan history makes gradable, re-derived from
--     FACT_PLAN_NEXT_WEEK in this file — "empty because young" passes, "empty because broken" fails;
--   * every check also runs on FN_PLAN_SCORECARD with the clock moved 30 days forward (row CM),
--     where the guard has 117 real decisions to partition, and at 2026-10-03 (row C12), the clock at
--     which review MUST_FIX 1 measured the old hint saying KEEP from 0 holds and 1 band row (that
--     band row was a release whose hold clock had run out; since the second follow-up the band leaves
--     such releases out and reads 0 there — C13);
--   * every check has a NEGATIVE CONTROL run as a standing row: the same expression over a doctored
--     temp copy must FIRE (the row reads PASS when it fired). A control with nothing to doctor reads
--     FAIL, never a quiet PASS.
--
-- THE CHECK EXPRESSIONS ARE WRITTEN ONCE, over sc_copies (one tagged copy per scenario), and each
-- copy is judged against the expectation of its own clock (LIVE = today in Los Angeles, MOVED =
-- today + 30, CASE = 2026-10-03). Twins of the function kept in this file, which must change with
-- it: the gradable-decision predicate (exp_g), the one-night-per-Sunday-week rule (exp_fw), the
-- 20-decision hint threshold (C09), the 3-week recommendation threshold (C03), the hint's sentence
-- openings (C11), the band (C13: band_cand / band_exp — a LAST_DAY_NOT_STRONG release with a last day
-- from 1.0x the bar up to its own multiplier, at least its own order minimum that day, and a hold
-- clock that had not run out, under the rule the hint names), and legacy_through 2026-10-01 with the
-- legacy rule 1.5 / 1 (C10, C13: history — the last night written before the plan table stored the
-- rule, and the rule those nights were judged under — never a setting). The per-group minimum is NOT
-- twinned: C09 reads min_group_rows from the hint row, so the number stays Ori's to rule on in one
-- place.
--
-- C09 (restated by the follow-up). The hint WAITs iff fewer than 20 graded decisions in all, no rule
-- in force, or EITHER group it compares (held_rows, band_rows) under min_group_rows; C09T holds its
-- totals to the GUARD weeks and its groups inside them. The v27.154 comment on C09 said it prevented
-- "a threshold change argued from five decisions"; no check did that, because the hint gated only on
-- the total.
-- C10 (replaced by the follow-up). The v27.154 C10 recomputed last_day_strong from today's mirrored
-- 1.5x on every P-14c row in history — a second copy of the P-14c test — and would have stayed red for
-- good after a threshold change (review measured 7 / 11 / 18 permanent violations at 1.3 / 1.2 / 2.0).
-- The rule each decision was made under is now STORED on its plan row, and C10 reads only that: every
-- row after legacy_through carries one, a night carries one rule, the hint's rule_value /
-- rule_min_orders are the latest night's, and two days after the columns existed a night has been
-- written since. It never reads last_day_strong's inputs.
-- C13 (added by the second follow-up). The band is meant to hold the keyword-nights a
-- lower strong_day_mult would have held. The judge's guard_released_by CASE tests NOT last_day_strong
-- before hold_expired, so a release whose hold clock had already run out is also labelled
-- LAST_DAY_NOT_STRONG when its last day was weak, and a lower multiplier would still have released it
-- (the judge's HELD arm needs NOT hold_expired). The function as committed in 46ae335 counted those releases in
-- the band. C13 holds band_rows to the band counted here from the published columns
-- (guard_released_by, hold_expired, last_day_ord, last_day_ret, family_bar, the stored rule); it
-- never re-derives the guard. The violation count is how many rows the band is off by.
--
-- RUN 2026-10-01 (Los Angeles; 2026-10-02 UTC), twice after the second follow-up deployed (the second
-- time on the files as committed): 43 rows, every one PASS, the same counts both times. The violation
-- table (copy x check) was printed from each run, so each PASS below is a control that FIRED or a
-- reading of 0 with something under it — not a vacuous one:
--   LIVE, MOVED and CASE read 0 on every check they run (C05 on LIVE only; C10 on LIVE and MOVED).
--   C01: NC_C01 (a GRADE row's calendar_state NULL) 1; NC_C01S (the RULE_HINT sentence NULL) 1.
--   C02: NC_C02 (allocation -1) 1; NC_C02Z (allocation NULL) 1.
--   C03: NC_C03D (a recommendation doubled) 1; NC_C03X (dropped) 1; NC_C03W (KEEP_B on 1 week) 1.
--   C04: NC_C04 (one family-night dropped) 1. Expectation today: 1 graded night (2026-08-28, the
--        week of 2026-08-23), 4 family-nights.
--   C05: the nine plan_* checks were on the board, none RED; NC_C05D (one removed) 1; NC_C05R (one
--        set RED) 1.
--   C06: LIVE 0 with 0 decisions gradable (117 written since 2026-09-28; first settle date
--        2026-10-03); MOVED 0 on 117 graded decisions in one week; NC_C06C (a class count +1) 1;
--        NC_C06G (the week total +1 on all four rows) 5; NC_C06E (today's empty GUARD against the
--        moved clock's 117 gradable decisions) 1.
--   C07: NC_C07 (a family-night 3 days old) 1; NC_C07G (a guard week settling tomorrow) 1.
--   C08: LIVE 0 — the RULE_HINT row counts 0 and its sentence names 2026-10-03; NC_C08 (sentence
--        replaced by a count) 1; NC_C08G (the moved grades against today's clock) 2.
--   C09: NC_C09 (LOWER with 0 graded) 1; NC_C09D (the hint row doubled) 1; NC_C09B (117 graded, 12
--        held, ONE band row, reading KEEP: the doctored control MUST_FIX 1 asked for) 1; NC_C09H (117
--        graded, ONE held, 12 band rows, reading KEEP) 1; C09T: NC_C09G (held_rows one larger than the
--        graded holds) 1.
--   C10: LIVE 0 — today's latest night (2026-10-01) was written before the columns existed and the
--        hint names 1.5x / 1 order; NC_C10N (the latest night's 361 rows moved after the columns
--        existed, with no rule) 361; NC_C10M (that night carrying 2.0 on one row, 1.5 on the rest) 2;
--        NC_C10V (that night storing rule_value + 0.25) 1; NC_C10E (only the nights to 2026-10-01,
--        judged on 2026-10-03) 1.
--   C11: NC_C11W (a group WAIT whose sentence names neither short group) 1; NC_C11K (KEEP opening
--        "over 117 graded guard decisions", the v27.154 form) 1.
--   C12: at 2026-10-03, 20 graded, 0 held, 0 in the band (the expired-clock release is left out),
--        minimum 10 each: WAIT, sentence naming both groups; C13 0 on it.
--   C13: band_exp counted today 0 in the band; at 2026-10-03 0 in the band and 1 release left out for
--        its expired clock; at today + 30 2 in the band and 2 left out; no release left out for a
--        short last day at any clock. LIVE, MOVED and CASE 0. NC_C13 (the 2026-10-03 hint with its
--        expired-clock release counted back into the band) 1.
--   CM: 117 real guard decisions graded at today + 30 (9 held, 2 in the band: WAIT); every check 0.
-- THE SAME FILE RUN AGAINST THE FUNCTION AS DEPLOYED BEFORE THE SECOND FOLLOW-UP (the body committed in 46ae335),
-- the same evening, before the fix was deployed: C13 read 1 on CASE (the function counted 1 band row
-- where 0 belong) and 2 on MOVED (4 where 2 belong), so C12 read FAIL 1 and CM read FAIL 2; the other
-- 41 rows PASS. That is C13 firing on the real defect, not only on a doctored copy.
--
-- WHAT THIS FILE DOES NOT PROVE. On the history to 2026-10-01 no clock reaches 10 graded holds or 10
-- graded band rows (at most 9 and 2), so every real hint reads WAIT and LOWER / RAISE / KEEP /
-- NO_CLEAN_SIGNAL have never come out of the function on real input. C09 and C11 judge the hint's
-- output against its own published counts, which is all a check over the output can do. The
-- function's arithmetic on those branches is exercised by check_plan_scorecard_hint_branches.py: run
-- 2026-10-01 (LA) after the second follow-up, ten doctored copies of the plan table, every one as
-- expected (exit 0) — RAISE from 12 held / 12 wrong, LOWER from 12 band / 12 wrong, KEEP,
-- NO_CLEAN_SIGNAL, WAIT naming the held group (9 of 10), WAIT naming the band (1 of 10, 30 graded),
-- WAIT with every decision under 1.5x while the latest night carries 2.0x (other_rule_rows 24), WAIT
-- with no rule on the latest night, and (new) S_BAND_EXPIRED and S_BAND_SHORT_DAY: 12 held right, 12
-- band releases at 1.2x that settled not good, and 18 releases at 1.2x that settled good but had an
-- expired hold clock (respectively 0 orders on the last day). Each read KEEP with band 12 / 0 wrong.
-- Its negative controls, each the same run on a doctored copy of the function file, each exit 1:
--   the clock term (AND NOT COALESCE(c.hold_expired, FALSE)) removed: S_BAND_EXPIRED read
--     LOWER_STRONG_DAY_MULT with band 30 / 18 wrong; every other scenario as expected;
--   the order term (AND c.last_day_ord >= c.eff_min) removed: S_BAND_SHORT_DAY read
--     LOWER_STRONG_DAY_MULT with band 30 / 18 wrong; every other scenario as expected;
--   min_group_rows doctored to 1: S_HELD_SMALL and S_BAND_SMALL read RAISE_STRONG_DAY_MULT, and
--     S_OTHER_RULE's WAIT names "of the 1 needed".
--
-- COST, measured 2026-10-01 (LA) in the last run above (uncached): V_PLAN_SCORECARD 209.2 slot-s;
-- FN_PLAN_SCORECARD at today + 30 217.1 slot-s and at 2026-10-03 181.5 slot-s (both join
-- FACT_AMAZON_ADS on the clustered keys). C13's three steps read FACT_PLAN_NEXT_WEEK only, not
-- FACT_AMAZON_ADS: 4.4 + 0.9 + 0.8 slot-s. The nine plan_* rows of V_ENGINE_HEALTH are read by NAME
-- (3.8 slot-s): a filter on check_name prunes the board's other arms, while the whole board read
-- uncached on 2026-10-01 cost 67,639 slot-s. The whole suite: 662.7 slot-s, 225.5 MB, 62 s; the
-- first post-fix run 827.4 slot-s, 86 s; the pre-fix run above 1,190.3 slot-s, 225.4 MB, 103 s.
-- check_plan_scorecard_hint_branches.py: 141.8 slot-s on the committed file, 131.9 to 139.0 on each
-- doctored copy.
-- =============================================================================================
DECLARE d0  DATE DEFAULT CURRENT_DATE('America/Los_Angeles');
DECLARE d30 DATE DEFAULT DATE_ADD(CURRENT_DATE('America/Los_Angeles'), INTERVAL 30 DAY);
-- the real case review MUST_FIX 1 measured: at this clock 20 decisions are graded and 0 held; the
-- band read 1 under the 46ae335 function, a release whose hold clock had run out, and reads 0 now
DECLARE d_case DATE DEFAULT DATE '2026-10-03';
-- TWIN, HISTORY not a setting: the last night written before FACT_PLAN_NEXT_WEEK carried the rule
DECLARE legacy_through DATE DEFAULT DATE '2026-10-01';
-- TWIN, HISTORY not a setting: the rule the nights to legacy_through were judged under
DECLARE legacy_mult FLOAT64 DEFAULT 1.5;
DECLARE legacy_min  INT64   DEFAULT 1;

-- ---- the scorecard, read once at today and once with the clock moved 30 days forward ----
CREATE TEMP TABLE sc_live AS
  SELECT *, ROW_NUMBER() OVER (PARTITION BY row_type
                               ORDER BY family, calendar_state, plan, week_start, graded_night, outcome_class) AS rn
  FROM `onyga-482313.OI.V_PLAN_SCORECARD`;
CREATE TEMP TABLE sc_moved AS
  SELECT *, ROW_NUMBER() OVER (PARTITION BY row_type
                               ORDER BY family, calendar_state, plan, week_start, graded_night, outcome_class) AS rn
  FROM `onyga-482313.OI.FN_PLAN_SCORECARD`(d30);
CREATE TEMP TABLE sc_case AS
  SELECT *, ROW_NUMBER() OVER (PARTITION BY row_type
                               ORDER BY family, calendar_state, plan, week_start, graded_night, outcome_class) AS rn
  FROM `onyga-482313.OI.FN_PLAN_SCORECARD`(d_case);

-- ---- what the plan history makes gradable, per clock (TWINS of the function's rules) ----
CREATE TEMP TABLE clock_dates AS
  SELECT 'LIVE' AS clock, d0 AS d UNION ALL SELECT 'MOVED', d30 UNION ALL SELECT 'CASE', d_case;
-- one plan night per Sunday-start week: the latest that is at least 14 days old
CREATE TEMP TABLE exp_fw AS
  WITH night AS (
    SELECT as_of, MAX(calendar_state) AS calendar_state
    FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK` GROUP BY 1
  ),
  pick AS (
    SELECT c.clock, n.as_of, n.calendar_state
    FROM clock_dates c JOIN night n ON DATE_DIFF(c.d, n.as_of, DAY) >= 14
    QUALIFY n.as_of = MAX(n.as_of) OVER (PARTITION BY c.clock, DATE_TRUNC(n.as_of, WEEK(SUNDAY)))
  )
  SELECT p.clock, p.as_of AS graded_night, f.family, p.calendar_state
  FROM pick p
  JOIN (SELECT DISTINCT as_of, family FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK`) f USING (as_of);
-- every guard decision the live plan wrote under P-14c by the clock, and whether it has settled.
-- READS verdict and guard_released_by as published; never re-derives the guard.
CREATE TEMP TABLE exp_g AS
  SELECT c.clock, DATE_TRUNC(p.as_of, WEEK(SUNDAY)) AS week_start, p.as_of, p.settle_due_on,
         (p.settle_due_on <= c.d) AS gradable
  FROM clock_dates c
  JOIN `onyga-482313.OI.FACT_PLAN_NEXT_WEEK` p ON p.as_of <= c.d
  WHERE p.is_live_plan
    AND p.last_day_strong IS NOT NULL
    AND (p.verdict = 'HELD_UNSETTLED' OR p.guard_released_by IS NOT NULL);
CREATE TEMP TABLE exp_gw AS
  SELECT clock, week_start, COUNT(*) AS n FROM exp_g WHERE gradable GROUP BY 1, 2;
CREATE TEMP TABLE clocks AS
  SELECT c.clock, c.d,
         COALESCE(fw.n_fw, 0)       AS n_fw,
         COALESCE(g.n_gradable, 0)  AS n_gradable,
         COALESCE(g.n_written, 0)   AS n_written,
         g.next_due
  FROM clock_dates c
  LEFT JOIN (SELECT clock, COUNT(*) AS n_fw FROM exp_fw GROUP BY 1) fw USING (clock)
  LEFT JOIN (SELECT clock, COUNTIF(gradable) AS n_gradable, COUNT(*) AS n_written,
                    MIN(IF(NOT gradable, settle_due_on, NULL)) AS next_due
             FROM exp_g GROUP BY 1) g USING (clock);
-- ---- C13: the band as the function must count it, per clock (TWIN of the band and of "under the
-- rule in force"). READS guard_released_by, hold_expired, last_day_ord, last_day_ret, family_bar and
-- the stored rule as published; never re-derives the guard. A row's rule is the one stored on it,
-- else the legacy rule for a night to legacy_through, else none (and then it is in no band).
CREATE TEMP TABLE band_cand AS
  SELECT c.clock, p.as_of, p.campaign_id, p.keyword_id,
         SAFE_DIVIDE(p.last_day_ret, NULLIF(p.family_bar, 0))                            AS x_bar,
         p.last_day_ord,
         COALESCE(p.hold_expired, FALSE)                                                 AS expired,
         COALESCE(p.strong_day_mult, IF(p.as_of <= legacy_through, legacy_mult, NULL))  AS eff_mult,
         COALESCE(p.strong_day_min_orders, IF(p.as_of <= legacy_through, legacy_min, NULL)) AS eff_min
  FROM clock_dates c
  JOIN `onyga-482313.OI.FACT_PLAN_NEXT_WEEK` p ON p.as_of <= c.d AND p.settle_due_on <= c.d
  WHERE p.is_live_plan
    AND p.last_day_strong IS NOT NULL
    AND p.guard_released_by = 'LAST_DAY_NOT_STRONG';
-- the rule each clock's hint names (C10 holds it to the latest night's stored rule)
CREATE TEMP TABLE clock_rule AS
            SELECT 'LIVE'  AS clock, rule_value, rule_min_orders FROM sc_live  WHERE row_type = 'RULE_HINT'
  UNION ALL SELECT 'MOVED',          rule_value, rule_min_orders FROM sc_moved WHERE row_type = 'RULE_HINT'
  UNION ALL SELECT 'CASE',           rule_value, rule_min_orders FROM sc_case  WHERE row_type = 'RULE_HINT';
-- one row per clock, zeros included. n_band: the band. n_expired: releases that sit between 1.0x and
-- their multiplier under the rule but whose hold clock had run out (the rows the 46ae335 band
-- wrongly counted). n_short_day: the same, clock running, but fewer orders on the last day than the
-- rule asks.
CREATE TEMP TABLE band_exp AS
  SELECT c.clock,
         COUNTIF(NOT b.expired AND b.last_day_ord >= b.eff_min)   AS n_band,
         COUNTIF(b.expired)                                       AS n_expired,
         COUNTIF(NOT b.expired AND NOT COALESCE(b.last_day_ord >= b.eff_min, FALSE)) AS n_short_day
  FROM clock_dates c
  LEFT JOIN clock_rule r USING (clock)
  LEFT JOIN band_cand b
    ON b.clock = c.clock
   AND b.eff_mult = r.rule_value AND b.eff_min = r.rule_min_orders
   AND b.x_bar >= 1.0 AND b.x_bar < b.eff_mult
  GROUP BY c.clock;

-- ---- the copies: LIVE and MOVED, and one doctored copy per negative control ----
CREATE TEMP TABLE sc_copies AS
            SELECT 'LIVE'      AS copy, 'LIVE'  AS clock, * FROM sc_live
  UNION ALL SELECT 'MOVED',              'MOVED', * FROM sc_moved
  UNION ALL SELECT 'CASE',               'CASE',  * FROM sc_case
  -- C01: a GRADE row loses its calendar state; the hint row loses its sentence
  UNION ALL SELECT 'NC_C01',  'LIVE', * REPLACE (IF(row_type = 'GRADE' AND rn = 1, NULL, calendar_state) AS calendar_state) FROM sc_live
  UNION ALL SELECT 'NC_C01S', 'LIVE', * REPLACE (IF(row_type = 'RULE_HINT', NULL, sentence) AS sentence) FROM sc_live
  -- C02: a GRADE row's allocation negative; NULL
  UNION ALL SELECT 'NC_C02',  'LIVE', * REPLACE (IF(row_type = 'GRADE' AND rn = 1, -1.0, allocated_dollars) AS allocated_dollars) FROM sc_live
  UNION ALL SELECT 'NC_C02Z', 'LIVE', * REPLACE (IF(row_type = 'GRADE' AND rn = 1, CAST(NULL AS FLOAT64), allocated_dollars) AS allocated_dollars) FROM sc_live
  -- C03: a recommendation doubled; dropped; a one-week recommendation that does not WAIT
  UNION ALL SELECT 'NC_C03D', 'LIVE', * FROM sc_live
  UNION ALL SELECT 'NC_C03D', 'LIVE', * FROM sc_live WHERE row_type = 'RECOMMENDATION' AND rn = 1
  UNION ALL SELECT 'NC_C03X', 'LIVE', * FROM sc_live WHERE NOT (row_type = 'RECOMMENDATION' AND rn = 1)
  UNION ALL SELECT 'NC_C03W', 'LIVE', * REPLACE (IF(row_type = 'RECOMMENDATION' AND rn = 1, 'KEEP_B', recommendation) AS recommendation) FROM sc_live
  -- C04: one family-night dropped
  UNION ALL SELECT 'NC_C04',  'LIVE', * FROM sc_live WHERE NOT (row_type = 'FAMILY_WEEK' AND rn = 1)
  -- C06 (on the moved copy, where GUARD has rows): a class count off by one; a week's total off by one;
  -- and today's empty GUARD judged against a clock at which decisions are gradable
  UNION ALL SELECT 'NC_C06C', 'MOVED', * REPLACE (IF(row_type = 'GUARD' AND rn = 1, class_rows + 1, class_rows) AS class_rows) FROM sc_moved
  UNION ALL SELECT 'NC_C06G', 'MOVED', * REPLACE (IF(row_type = 'GUARD', graded_rows + 1, graded_rows) AS graded_rows) FROM sc_moved
  UNION ALL SELECT 'NC_C06E', 'MOVED', * FROM sc_live
  -- C07: a family-night three days old; a guard week graded before its last window settled
  UNION ALL SELECT 'NC_C07',  'LIVE',  * REPLACE (IF(row_type = 'FAMILY_WEEK' AND rn = 1, DATE_SUB(d0, INTERVAL 3 DAY), graded_night) AS graded_night) FROM sc_live
  UNION ALL SELECT 'NC_C07G', 'MOVED', * REPLACE (IF(row_type = 'GUARD' AND rn = 1, DATE_ADD(d30, INTERVAL 1 DAY), last_settle_due_on) AS last_settle_due_on) FROM sc_moved
  -- C08: the youth sentence replaced by a count; the moved grades judged against today's clock
  UNION ALL SELECT 'NC_C08',  'LIVE', * REPLACE (IF(row_type = 'RULE_HINT', 'WAIT: 3 graded guard decision(s) of the 20 this hint needs.', sentence) AS sentence) FROM sc_live
  UNION ALL SELECT 'NC_C08G', 'LIVE', * FROM sc_moved
  -- C09: the hint leaves WAIT below 20; the hint row doubled
  UNION ALL SELECT 'NC_C09',  'LIVE', * REPLACE (IF(row_type = 'RULE_HINT', 'LOWER_STRONG_DAY_MULT', recommendation) AS recommendation) FROM sc_live
  UNION ALL SELECT 'NC_C09D', 'LIVE', * FROM sc_live
  UNION ALL SELECT 'NC_C09D', 'LIVE', * FROM sc_live WHERE row_type = 'RULE_HINT'
  -- C09 (MUST_FIX 1): 117 graded decisions, 12 held (enough) and ONE band row, reading KEEP — it must
  -- WAIT; the same with ONE held row and 12 in the band; and a group count that its totals cannot hold
  UNION ALL SELECT 'NC_C09B', 'MOVED', * REPLACE (
              IF(row_type = 'RULE_HINT', 12, held_rows) AS held_rows,
              IF(row_type = 'RULE_HINT', 0, held_rows_wrong) AS held_rows_wrong,
              IF(row_type = 'RULE_HINT', 1, band_rows) AS band_rows,
              IF(row_type = 'RULE_HINT', 0, band_released_wrong) AS band_released_wrong,
              IF(row_type = 'RULE_HINT', 'KEEP_STRONG_DAY_MULT', recommendation) AS recommendation) FROM sc_moved
  UNION ALL SELECT 'NC_C09H', 'MOVED', * REPLACE (
              IF(row_type = 'RULE_HINT', 1, held_rows) AS held_rows,
              IF(row_type = 'RULE_HINT', 0, held_rows_wrong) AS held_rows_wrong,
              IF(row_type = 'RULE_HINT', 12, band_rows) AS band_rows,
              IF(row_type = 'RULE_HINT', 0, band_released_wrong) AS band_released_wrong,
              IF(row_type = 'RULE_HINT', 'KEEP_STRONG_DAY_MULT', recommendation) AS recommendation) FROM sc_moved
  UNION ALL SELECT 'NC_C09G', 'MOVED', * REPLACE (IF(row_type = 'RULE_HINT', held_rows + 1, held_rows) AS held_rows) FROM sc_moved
  -- C11: a WAIT that names neither short group; a KEEP that leads with the total (the old sentence)
  UNION ALL SELECT 'NC_C11W', 'MOVED', * REPLACE (
              IF(row_type = 'RULE_HINT', 'WAIT: 117 graded guard decisions in 1 week(s). Nothing changes.', sentence) AS sentence) FROM sc_moved
  UNION ALL SELECT 'NC_C11K', 'MOVED', * REPLACE (
              IF(row_type = 'RULE_HINT', 12, held_rows) AS held_rows,
              IF(row_type = 'RULE_HINT', 12, band_rows) AS band_rows,
              IF(row_type = 'RULE_HINT', 'KEEP_STRONG_DAY_MULT', recommendation) AS recommendation,
              IF(row_type = 'RULE_HINT', 'THE LAST-DAY BAR HOLDS over 117 graded guard decisions in 1 week(s): of the 12 keyword-nights let through with a last day between 1.0x and 1.5x the bar, 0 turned out good. Keep strong_day_mult at 1.5.', sentence) AS sentence) FROM sc_moved
  -- C13: the 2026-10-03 hint with the releases whose hold clock had run out counted back into its band,
  -- as the 46ae335 function counted them (nothing to add => the control does not fire => FAIL)
  UNION ALL SELECT 'NC_C13', 'CASE', * REPLACE (
              IF(row_type = 'RULE_HINT', band_rows + (SELECT n_expired FROM band_exp WHERE clock = 'CASE'), band_rows) AS band_rows) FROM sc_case;
-- the copies, listed explicitly: a copy that came back EMPTY still gets judged (and fails C01)
CREATE TEMP TABLE copies AS
  SELECT copy, clock FROM UNNEST([
    STRUCT('LIVE' AS copy, 'LIVE' AS clock), ('MOVED', 'MOVED'),
    ('NC_C01', 'LIVE'), ('NC_C01S', 'LIVE'), ('NC_C02', 'LIVE'), ('NC_C02Z', 'LIVE'),
    ('NC_C03D', 'LIVE'), ('NC_C03X', 'LIVE'), ('NC_C03W', 'LIVE'), ('NC_C04', 'LIVE'),
    ('NC_C06C', 'MOVED'), ('NC_C06G', 'MOVED'), ('NC_C06E', 'MOVED'),
    ('NC_C07', 'LIVE'), ('NC_C07G', 'MOVED'), ('NC_C08', 'LIVE'), ('NC_C08G', 'LIVE'),
    ('NC_C09', 'LIVE'), ('NC_C09D', 'LIVE'), ('NC_C09B', 'MOVED'), ('NC_C09H', 'MOVED'),
    ('NC_C09G', 'MOVED'), ('NC_C11W', 'MOVED'), ('NC_C11K', 'MOVED'), ('CASE', 'CASE'),
    ('NC_C13', 'CASE')]);

-- ---- C05: the nine plan_* checks, read by NAME (prunes the board; see the header) ----
CREATE TEMP TABLE board AS
  SELECT check_name, status FROM `onyga-482313.OI.V_ENGINE_HEALTH`
  WHERE check_name IN ('plan_window_complete_days', 'plan_pot_reconciliation', 'plan_one_move_per_notgood',
                       'plan_ownership_no_foreign_go', 'plan_both_plans_written', 'plan_settle_guard_holds',
                       'plan_settle_curve_coverage', 'plan_proposal_lag_days', 'plan_partition_fresh');
CREATE TEMP TABLE board_copies AS
            SELECT 'LIVE' AS copy, check_name, status FROM board
  UNION ALL SELECT 'NC_C05D', check_name, status FROM board
            WHERE check_name != (SELECT MIN(check_name) FROM board)
  UNION ALL SELECT 'NC_C05R', check_name, IF(check_name = (SELECT MIN(check_name) FROM board), 'RED', status) FROM board;

-- ---- C10: the rule each P-14c decision was made under, as STORED on its row (never re-derived) ----
CREATE TEMP TABLE p14c AS
  SELECT as_of, campaign_id, keyword_id, strong_day_mult, strong_day_min_orders
  FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK`
  WHERE is_live_plan AND last_day_strong IS NOT NULL;
-- the doctored nights are the latest real night's rows moved to the moved clock's date, so they are
-- always the latest night that clock reads; an empty table leaves the controls nothing and they FAIL
CREATE TEMP TABLE p14c_latest AS
  SELECT *, ROW_NUMBER() OVER (ORDER BY campaign_id, keyword_id) AS rn
  FROM p14c WHERE as_of = (SELECT MAX(as_of) FROM p14c);
CREATE TEMP TABLE p14c_copies AS
            SELECT 'LIVE'    AS copy, * FROM p14c
  UNION ALL SELECT 'MOVED',           * FROM p14c
  -- a night after the columns existed whose rows carry no rule
  UNION ALL SELECT 'NC_C10N',         * FROM p14c
  UNION ALL SELECT 'NC_C10N', * EXCEPT (rn) REPLACE (d30 AS as_of, CAST(NULL AS FLOAT64) AS strong_day_mult,
                                                    CAST(NULL AS INT64) AS strong_day_min_orders) FROM p14c_latest
  -- a night carrying two rules
  UNION ALL SELECT 'NC_C10M',         * FROM p14c
  UNION ALL SELECT 'NC_C10M', * EXCEPT (rn) REPLACE (d30 AS as_of, IF(rn = 1, 2.0, 1.5) AS strong_day_mult,
                                                    1 AS strong_day_min_orders) FROM p14c_latest
  -- a latest night whose rule is not the one the hint names (rule_value + 0.25)
  UNION ALL SELECT 'NC_C10V',         * FROM p14c
  UNION ALL SELECT 'NC_C10V', * EXCEPT (rn) REPLACE (d30 AS as_of,
              (SELECT MAX(rule_value) + 0.25 FROM sc_moved WHERE row_type = 'RULE_HINT') AS strong_day_mult,
              (SELECT MAX(rule_min_orders) FROM sc_moved WHERE row_type = 'RULE_HINT') AS strong_day_min_orders) FROM p14c_latest
  -- two days after the columns existed and the plan has written no night since
  UNION ALL SELECT 'NC_C10E',         * FROM p14c WHERE as_of <= legacy_through;
-- (copy, the scorecard copy whose hint it is judged against, that scorecard's clock, the real day)
CREATE TEMP TABLE c10_list AS
  SELECT * FROM UNNEST([
    STRUCT('LIVE' AS copy, 'LIVE' AS sc_copy, d0 AS cd, d0 AS today_d),
    ('MOVED', 'MOVED', d30, d0), ('NC_C10N', 'MOVED', d30, d0), ('NC_C10M', 'MOVED', d30, d0),
    ('NC_C10V', 'MOVED', d30, d0),
    ('NC_C10E', 'LIVE', DATE_ADD(legacy_through, INTERVAL 2 DAY), DATE_ADD(legacy_through, INTERVAL 2 DAY))]);
CREATE TEMP TABLE c10_agg AS
  SELECT x.copy, x.sc_copy, x.cd, x.today_d,
         COUNTIF(p.as_of > legacy_through AND p.as_of <= x.cd
                 AND (p.strong_day_mult IS NULL OR p.strong_day_min_orders IS NULL))      AS n_unrecorded,
         MAX(IF(p.as_of <= x.cd, p.as_of, NULL))                                         AS latest_night,
         COUNTIF(p.as_of > legacy_through AND p.as_of <= x.today_d)                      AS n_since_columns
  FROM c10_list x
  LEFT JOIN p14c_copies p ON p.copy = x.copy
  GROUP BY 1, 2, 3, 4;
CREATE TEMP TABLE c10_two AS
  SELECT copy, COUNT(*) AS n_nights_two_rules
  FROM (SELECT x.copy, p.as_of
        FROM c10_list x JOIN p14c_copies p ON p.copy = x.copy AND p.as_of <= x.cd
        GROUP BY 1, 2
        HAVING COUNT(DISTINCT IF(p.strong_day_mult IS NULL OR p.strong_day_min_orders IS NULL, NULL,
                                 FORMAT('%t|%t', p.strong_day_mult, p.strong_day_min_orders))) > 1)
  GROUP BY copy;
CREATE TEMP TABLE c10_latest AS
  SELECT a.copy, MAX(p.strong_day_mult) AS l_mult, MAX(p.strong_day_min_orders) AS l_min
  FROM c10_agg a JOIN p14c_copies p ON p.copy = a.copy AND p.as_of = a.latest_night
  GROUP BY 1;

-- ---- every check, written once, evaluated on every copy: (copy, chk, n) ----
CREATE TEMP TABLE vlist AS
-- C01 grain, row types, sentences; the hint row is always present
SELECT k.copy, 'C01' AS chk,
       COUNTIF(row_type NOT IN ('GRADE', 'RECOMMENDATION', 'FAMILY_WEEK', 'GUARD', 'RULE_HINT'))
     + COUNTIF(row_type = 'GRADE' AND (plan IS NULL OR plan NOT IN ('A', 'B') OR family IS NULL OR calendar_state IS NULL))
     + COUNTIF(row_type = 'RECOMMENDATION' AND (family IS NULL OR calendar_state IS NULL OR recommendation IS NULL))
     + COUNTIF(row_type = 'FAMILY_WEEK' AND (family IS NULL OR calendar_state IS NULL OR graded_night IS NULL OR week_start IS NULL))
     + COUNTIF(row_type = 'GUARD' AND (week_start IS NULL OR outcome_class IS NULL OR calendar_state IS NULL))
     + COUNTIF(row_type = 'RULE_HINT' AND recommendation IS NULL)
     + COUNTIF(COALESCE(sentence, '') = '')
     + IF(COUNTIF(row_type = 'RULE_HINT') = 0, 1, 0) AS n
FROM copies k LEFT JOIN sc_copies s USING (copy) GROUP BY k.copy
UNION ALL
-- C02 allocations; and no GRADE row at all while the history has a graded night
SELECT k.copy, 'C02',
       COUNTIF(s.row_type = 'GRADE' AND (s.allocated_dollars IS NULL OR s.allocated_dollars < 0))
     + COUNTIF(s.row_type = 'FAMILY_WEEK' AND (s.allocated_a IS NULL OR s.allocated_a < 0
                                              OR s.allocated_b IS NULL OR s.allocated_b < 0))
     + IF(COUNTIF(s.row_type = 'GRADE') = 0 AND MAX(c.n_fw) > 0, 1, 0)
FROM copies k JOIN clocks c USING (clock) LEFT JOIN sc_copies s ON s.copy = k.copy GROUP BY k.copy
UNION ALL
-- C03a one recommendation per family x state, and WAIT below three graded weeks (twin: 3)
SELECT copy, 'C03', COUNTIF(n != 1 OR bad_wait)
FROM (SELECT copy, family, calendar_state, COUNT(*) AS n,
             LOGICAL_OR(graded_windows < 3 AND COALESCE(recommendation, '') != 'WAIT') AS bad_wait
      FROM sc_copies WHERE row_type = 'RECOMMENDATION' GROUP BY 1, 2, 3)
GROUP BY copy
UNION ALL
-- C03b a recommendation for every graded family x state, and none without grades
SELECT COALESCE(g.copy, r.copy), 'C03', COUNTIF(g.copy IS NULL OR r.copy IS NULL)
FROM (SELECT DISTINCT copy, family, calendar_state FROM sc_copies WHERE row_type = 'GRADE') g
FULL OUTER JOIN (SELECT DISTINCT copy, family, calendar_state FROM sc_copies WHERE row_type = 'RECOMMENDATION') r
  ON g.copy = r.copy AND g.family = r.family AND g.calendar_state = r.calendar_state
GROUP BY 1
UNION ALL
-- C04a the family-nights graded are exactly the ones the history makes gradable
SELECT COALESCE(s.copy, e.copy), 'C04', COUNTIF(s.copy IS NULL OR e.copy IS NULL)
FROM (SELECT DISTINCT copy, family, graded_night FROM sc_copies WHERE row_type = 'FAMILY_WEEK') s
FULL OUTER JOIN (SELECT k.copy, e.family, e.graded_night FROM copies k JOIN exp_fw e USING (clock)) e
  ON s.copy = e.copy AND s.family = e.family AND s.graded_night = e.graded_night
GROUP BY 1
UNION ALL
-- C04b each GRADE row counts exactly those nights for its family x state
SELECT COALESCE(s.copy, e.copy), 'C04', COUNTIF(s.copy IS NULL OR e.copy IS NULL OR s.gw != e.n)
FROM (SELECT copy, family, calendar_state, MAX(graded_windows) AS gw
      FROM sc_copies WHERE row_type = 'GRADE' GROUP BY 1, 2, 3) s
FULL OUTER JOIN (SELECT k.copy, e.family, e.calendar_state, COUNT(DISTINCT e.graded_night) AS n
                 FROM copies k JOIN exp_fw e USING (clock) GROUP BY 1, 2, 3) e
  ON s.copy = e.copy AND s.family = e.family AND s.calendar_state = e.calendar_state
GROUP BY 1
UNION ALL
-- C06a/b each GUARD row: four classes sum to the week's graded rows; its own count is its class's
SELECT copy, 'C06',
       COUNTIF(row_type = 'GUARD'
               AND NOT COALESCE(held_right + held_wrong + released_right + released_wrong = graded_rows
                                AND class_rows = CASE outcome_class
                                                   WHEN 'HELD_RIGHT'     THEN held_right
                                                   WHEN 'HELD_WRONG'     THEN held_wrong
                                                   WHEN 'RELEASED_RIGHT' THEN released_right
                                                   WHEN 'RELEASED_WRONG' THEN released_wrong END, FALSE))
FROM sc_copies GROUP BY copy
UNION ALL
-- C06c four distinct classes per week, one shared total
SELECT copy, 'C06', COUNTIF(n != 4 OR nd != 4 OR g_max != g_min)
FROM (SELECT copy, week_start, COUNT(*) AS n, COUNT(DISTINCT outcome_class) AS nd,
             MAX(graded_rows) AS g_max, MIN(graded_rows) AS g_min
      FROM sc_copies WHERE row_type = 'GUARD' GROUP BY 1, 2)
GROUP BY copy
UNION ALL
-- C06d every gradable decision graded, week by week, and nothing graded that is not gradable
SELECT COALESCE(s.copy, e.copy), 'C06', COUNTIF(s.copy IS NULL OR e.copy IS NULL OR s.g != e.n)
FROM (SELECT copy, week_start, MAX(graded_rows) AS g FROM sc_copies WHERE row_type = 'GUARD' GROUP BY 1, 2) s
FULL OUTER JOIN (SELECT k.copy, e.week_start, e.n FROM copies k JOIN exp_gw e USING (clock)) e
  ON s.copy = e.copy AND s.week_start = e.week_start
GROUP BY 1
UNION ALL
-- C07 nothing graded before it is old enough; no FAMILY_WEEK while the history has a graded night
SELECT k.copy, 'C07',
       COUNTIF(s.row_type = 'FAMILY_WEEK' AND (s.graded_night IS NULL OR DATE_DIFF(c.d, s.graded_night, DAY) < 14))
     + COUNTIF(s.row_type = 'GUARD' AND (s.last_settle_due_on IS NULL OR s.last_settle_due_on > c.d))
     + IF(COUNTIF(s.row_type = 'FAMILY_WEEK') = 0 AND MAX(c.n_fw) > 0, 1, 0)
FROM copies k JOIN clocks c USING (clock) LEFT JOIN sc_copies s ON s.copy = k.copy GROUP BY k.copy
UNION ALL
-- C08 the hint counts what is gradable, and while nothing is, says so with the settle date
SELECT k.copy, 'C08',
       COUNTIF(s.row_type = 'RULE_HINT' AND COALESCE(s.graded_rows, -1) != c.n_gradable)
     + COUNTIF(s.row_type = 'RULE_HINT' AND c.n_gradable = 0 AND c.n_written > 0
               AND NOT (STARTS_WITH(COALESCE(s.sentence, ''), 'WAIT: no guard decision is old enough to grade yet')
                        AND STRPOS(COALESCE(s.sentence, ''),
                                   CONCAT('the first one settles on ', CAST(c.next_due AS STRING))) > 0))
     + COUNTIF(s.row_type = 'RULE_HINT' AND c.n_gradable = 0 AND c.n_written = 0
               AND NOT STARTS_WITH(COALESCE(s.sentence, ''), 'WAIT: the live plan has written no guard decision'))
     + IF(COUNTIF(s.row_type = 'RULE_HINT') = 0, 1, 0)
FROM copies k JOIN clocks c USING (clock) LEFT JOIN sc_copies s ON s.copy = k.copy GROUP BY k.copy
UNION ALL
-- C09 one hint row; it WAITs iff fewer than 20 graded decisions in all (twin: 20), no rule in force,
-- or EITHER group it compares (held_rows, band_rows) under the min_group_rows the row publishes;
-- and only the five words the hint has
SELECT k.copy, 'C09',
       IF(COUNT(h.copy) != 1, 1, 0)
     + COUNTIF(h.copy IS NOT NULL
               AND COALESCE(h.graded_rows < 20 OR h.rule_value IS NULL OR h.rule_min_orders IS NULL
                            OR h.min_group_rows IS NULL
                            OR h.held_rows < h.min_group_rows OR h.band_rows < h.min_group_rows, TRUE)
                   != (COALESCE(h.recommendation, '') = 'WAIT'))
     + COUNTIF(h.copy IS NOT NULL AND (h.min_group_rows IS NULL OR h.min_group_rows < 1))
     + COUNTIF(h.copy IS NOT NULL AND h.recommendation NOT IN ('WAIT', 'KEEP_STRONG_DAY_MULT', 'LOWER_STRONG_DAY_MULT',
                                                               'RAISE_STRONG_DAY_MULT', 'NO_CLEAN_SIGNAL'))
FROM copies k
LEFT JOIN (SELECT * FROM sc_copies WHERE row_type = 'RULE_HINT') h USING (copy)
GROUP BY k.copy
UNION ALL
-- C09T its totals are the GUARD weeks' totals, and the two groups fit inside them: the held group is
-- the held decisions under the rule in force, the band is a part of the let-through, and with no
-- decision made under another rule the held group IS every graded hold
SELECT k.copy, 'C09T',
       COUNTIF(h.copy IS NOT NULL
               AND NOT COALESCE(h.held_right + h.held_wrong + h.released_right + h.released_wrong = h.graded_rows
                                AND h.graded_rows    = COALESCE(t.g, 0)
                                AND h.held_right     = COALESCE(t.hr, 0) AND h.held_wrong     = COALESCE(t.hw, 0)
                                AND h.released_right = COALESCE(t.rr, 0) AND h.released_wrong = COALESCE(t.rw, 0), FALSE))
     + COUNTIF(h.copy IS NOT NULL
               AND NOT COALESCE(h.held_rows_wrong <= h.held_rows AND h.band_released_wrong <= h.band_rows
                                AND h.held_rows <= h.held_right + h.held_wrong AND h.held_rows_wrong <= h.held_wrong
                                AND h.band_rows <= h.released_right + h.released_wrong
                                AND h.band_released_wrong <= h.released_wrong
                                AND h.other_rule_rows + h.held_rows + h.band_rows <= h.graded_rows
                                AND (h.other_rule_rows > 0
                                     OR (h.held_rows = h.held_right + h.held_wrong AND h.held_rows_wrong = h.held_wrong)), FALSE))
FROM copies k
LEFT JOIN (SELECT * FROM sc_copies WHERE row_type = 'RULE_HINT') h USING (copy)
LEFT JOIN (SELECT copy, SUM(g) AS g, SUM(hr) AS hr, SUM(hw) AS hw, SUM(rr) AS rr, SUM(rw) AS rw
           FROM (SELECT copy, week_start, MAX(graded_rows) AS g, MAX(held_right) AS hr, MAX(held_wrong) AS hw,
                        MAX(released_right) AS rr, MAX(released_wrong) AS rw
                 FROM sc_copies WHERE row_type = 'GUARD' GROUP BY 1, 2)
           GROUP BY 1) t USING (copy)
GROUP BY k.copy
UNION ALL
-- C11 the hint's words carry the group it argued from (TWINS of the function's sentence openings):
-- a WAIT held by a group minimum names each short group and its count; LOWER / RAISE / KEEP /
-- NO_CLEAN_SIGNAL open with the group size, never the total
SELECT k.copy, 'C11',
       COUNTIF(h.copy IS NOT NULL AND h.recommendation = 'WAIT' AND h.graded_rows >= 20
               AND h.rule_value IS NOT NULL AND h.rule_min_orders IS NOT NULL AND h.min_group_rows IS NOT NULL
               AND (h.held_rows < h.min_group_rows OR h.band_rows < h.min_group_rows)
               AND NOT COALESCE(STARTS_WITH(h.sentence, 'WAIT: ')
                                AND (h.held_rows >= h.min_group_rows
                                     OR STRPOS(h.sentence, FORMAT('%d held of the %d needed', h.held_rows, h.min_group_rows)) > 0)
                                AND (h.band_rows >= h.min_group_rows
                                     OR STRPOS(h.sentence, FORMAT('%d let through in the band of the %d needed', h.band_rows, h.min_group_rows)) > 0), FALSE))
     + COUNTIF(h.recommendation = 'LOWER_STRONG_DAY_MULT'
               AND NOT COALESCE(STARTS_WITH(h.sentence, FORMAT('THE LAST-DAY BAR LOOKS TOO HIGH from %d keyword-nights let through', h.band_rows)), FALSE))
     + COUNTIF(h.recommendation = 'RAISE_STRONG_DAY_MULT'
               AND NOT COALESCE(STARTS_WITH(h.sentence, FORMAT('THE LAST-DAY BAR LOOKS TOO LOW from %d keyword-nights held', h.held_rows)), FALSE))
     + COUNTIF(h.recommendation = 'KEEP_STRONG_DAY_MULT'
               AND NOT COALESCE(STARTS_WITH(h.sentence, FORMAT('THE LAST-DAY BAR HOLDS from %d held and %d let through in the band', h.held_rows, h.band_rows)), FALSE))
     + COUNTIF(h.recommendation = 'NO_CLEAN_SIGNAL'
               AND NOT COALESCE(STARTS_WITH(h.sentence, FORMAT('NO CLEAN SIGNAL from %d held and %d let through in the band', h.held_rows, h.band_rows)), FALSE))
FROM copies k
LEFT JOIN (SELECT * FROM sc_copies WHERE row_type = 'RULE_HINT') h USING (copy)
GROUP BY k.copy
UNION ALL
-- C13 the band is exactly the graded releases a lower multiplier would have held under the rule the
-- hint names (TWIN: band_exp): never one whose hold clock had run out, never a last day short of the
-- order minimum. The count is how many rows the band is off by; a copy with no hint row counts 1.
SELECT k.copy, 'C13',
       IF(COUNT(h.copy) = 0, 1, 0)
     + COALESCE(SUM(IF(h.copy IS NULL, 0, ABS(COALESCE(h.band_rows, -1) - COALESCE(b.n_band, 0)))), 0)
FROM copies k
LEFT JOIN band_exp b USING (clock)
LEFT JOIN (SELECT * FROM sc_copies WHERE row_type = 'RULE_HINT') h ON h.copy = k.copy
GROUP BY k.copy
UNION ALL
-- C05 the nine plan_* checks exist, once each, and none is RED
SELECT k_copy, 'C05',
       (9 - COUNT(DISTINCT b.check_name)) + (COUNT(b.check_name) - COUNT(DISTINCT b.check_name))
     + COUNTIF(b.status = 'RED')
FROM UNNEST(['LIVE', 'NC_C05D', 'NC_C05R']) AS k_copy
LEFT JOIN board_copies b ON b.copy = k_copy
GROUP BY k_copy
UNION ALL
-- C10 the rule is STORED on every P-14c row written after the columns existed, one rule per night,
-- and the hint's rule_value / rule_min_orders are the latest night's (stored; for a night written
-- before the columns existed, present); and the plan has written a night since the columns existed
-- once two days have passed. Reads the stored columns; never re-derives last_day_strong.
SELECT a.copy, 'C10',
       a.n_unrecorded
     + COALESCE(t.n_nights_two_rules, 0)
     + IF(l.l_mult IS NOT NULL
          AND NOT COALESCE(ABS(h.rule_value - l.l_mult) < 1e-9 AND h.rule_min_orders = l.l_min, FALSE), 1, 0)
     + IF(l.l_mult IS NULL AND a.latest_night <= legacy_through
          AND (h.rule_value IS NULL OR h.rule_min_orders IS NULL), 1, 0)
     + IF(a.latest_night IS NULL, 1, 0)
     + IF(h.copy IS NULL, 1, 0)
     + IF(a.today_d >= DATE_ADD(legacy_through, INTERVAL 2 DAY) AND a.n_since_columns = 0, 1, 0)
FROM c10_agg a
LEFT JOIN c10_two t USING (copy)
LEFT JOIN c10_latest l USING (copy)
LEFT JOIN (SELECT * FROM sc_copies WHERE row_type = 'RULE_HINT') h ON h.copy = a.sc_copy;

-- a (copy, check) absent from vlist means every grouped term had no input row: zero violations from
-- those terms. Each check also carries a term driven from the explicit copy list, so an EMPTY copy
-- is still judged (C01, C02, C07, C08, C09, C09T, C11, C13, C05 and C10 read their copies from a list,
-- not from data).
CREATE TEMP TABLE v AS SELECT copy, chk, SUM(n) AS n FROM vlist GROUP BY 1, 2;
WITH
n_moved AS (SELECT COALESCE(MAX(graded_rows), 0) AS g FROM sc_moved WHERE row_type = 'RULE_HINT'),
the_case AS (
  SELECT MAX(graded_rows) AS g, MAX(held_rows) AS held, MAX(band_rows) AS band,
         MAX(min_group_rows) AS mn, MAX(recommendation) AS rec, COUNT(*) AS n
  FROM sc_case WHERE row_type = 'RULE_HINT'),
live_counts AS (
  SELECT (SELECT n_fw FROM clocks WHERE clock = 'LIVE') AS n_fw,
         (SELECT COUNT(DISTINCT graded_night) FROM exp_fw WHERE clock = 'LIVE') AS n_nights,
         (SELECT n_gradable FROM clocks WHERE clock = 'LIVE') AS n_gradable,
         (SELECT n_written FROM clocks WHERE clock = 'LIVE') AS n_written,
         (SELECT CAST(next_due AS STRING) FROM clocks WHERE clock = 'LIVE') AS next_due
),
checks AS (
  -- A SCORECARD ROW WITH NO GRAIN OR NO SENTENCE: Ori reads a grade he cannot place, or a blank where
  -- the reason should be, and the recommendation is read off the wrong family or state.
  SELECT 'C01 every row names its type and the grain that type promises, and carries a sentence' AS check_name,
         (SELECT COALESCE(SUM(n), 0) FROM v WHERE copy = 'LIVE' AND chk = 'C01') AS violations
  -- A NEGATIVE OR MISSING ALLOCATION: net per allocated dollar divides by it, and a sign error flips
  -- which plan wins.
  UNION ALL SELECT 'C02 allocated dollars are never negative and never NULL on a graded row (and graded rows exist when the history has a graded night)',
         (SELECT COALESCE(SUM(n), 0) FROM v WHERE copy = 'LIVE' AND chk = 'C02')
  -- TWO RECOMMENDATIONS FOR ONE FAMILY x STATE, OR NONE, OR A SWITCH ON ONE WEEK: Ori acts on a rule
  -- the scorecard did not apply.
  UNION ALL SELECT 'C03 exactly one recommendation per family x calendar state that has grades, none without, WAIT below three graded weeks',
         (SELECT COALESCE(SUM(n), 0) FROM v WHERE copy = 'LIVE' AND chk = 'C03')
  -- THE SCORECARD IS EMPTY OR SHORT BECAUSE IT IS BROKEN, AND READS AS YOUNG: a week the history can
  -- grade is missing, or a night is graded twice, and every pooled grade is off.
  UNION ALL SELECT FORMAT('C04 FAMILY_WEEK and GRADE carry exactly the graded nights the plan history allows (today: %d graded night(s), %d family-night(s))',
                          (SELECT n_nights FROM live_counts), (SELECT n_fw FROM live_counts)),
         (SELECT COALESCE(SUM(n), 0) FROM v WHERE copy = 'LIVE' AND chk = 'C04')
  -- A PLAN CHECK WAS RENAMED, DROPPED OR IS RED: the alarm Task A built for a night not saved no
  -- longer exists, or the plan the scorecard grades is broken tonight.
  UNION ALL SELECT 'C05 the nine plan_* checks Task A added are on V_ENGINE_HEALTH once each and none is RED',
         (SELECT COALESCE(SUM(n), 0) FROM v WHERE copy = 'LIVE' AND chk = 'C05')
  -- A GUARD DECISION LOST, DOUBLED OR IN TWO CLASSES: the held-wrong / released-wrong counts the hint
  -- reads are not the decisions the plan made, and the 1.5x is graded on a different population.
  UNION ALL SELECT 'C06 GUARD classes partition the graded guard decisions exactly, week by week (held right + held wrong + released right + released wrong = graded rows = the decisions gradable)',
         (SELECT COALESCE(SUM(n), 0) FROM v WHERE copy = 'LIVE' AND chk = 'C06')
  -- A GRADE ON NUMBERS STILL ARRIVING: a week graded before 14 days, or a guard decision before its
  -- window settled, scores the plan on missing orders.
  UNION ALL SELECT 'C07 no graded night younger than 14 days and no guard week graded before its last window settled',
         (SELECT COALESCE(SUM(n), 0) FROM v WHERE copy = 'LIVE' AND chk = 'C07')
  -- THE GUARD'S GRADE IS SILENT: an empty GUARD reads as "nothing to grade" when decisions are gradable,
  -- or the youth sentence names the wrong date and Ori waits for a grade that is not coming.
  UNION ALL SELECT FORMAT('C08 REPORT guard decisions graded today: %d of %d written (first settles %s; 0 expected before then) — the RULE_HINT row counts exactly the gradable ones and, while none is, says so with the settle date',
                          (SELECT n_gradable FROM live_counts), (SELECT n_written FROM live_counts),
                          COALESCE((SELECT next_due FROM live_counts), 'n/a')),
         (SELECT COALESCE(SUM(n), 0) FROM v WHERE copy = 'LIVE' AND chk = 'C08')
  -- THE HINT ARGUES FROM A GROUP TOO SMALL TO SHOW A DIRECTION, OR DISAGREES WITH ITS OWN ROWS: it
  -- says LOWER / RAISE / KEEP / NO_CLEAN_SIGNAL while the held group or the band has fewer graded rows
  -- than the min_group_rows it publishes (or under 20 in all, or with no rule in force), or its counts
  -- are not the GUARD rows Ori can read, or its groups do not fit inside them. It reads the minimum
  -- from the row: what the minimum should be is Ori's ruling, not this check's.
  UNION ALL SELECT 'C09 one RULE_HINT row; WAIT iff under 20 graded decisions in all, no rule in force, or either compared group under min_group_rows; its totals equal the GUARD weeks\' and its groups fit inside them',
         (SELECT COALESCE(SUM(n), 0) FROM v WHERE copy = 'LIVE' AND chk IN ('C09', 'C09T'))
  -- A DECISION WITH NO RULE ON ITS ROW, A NIGHT WITH TWO RULES, OR A HINT ABOUT A RULE NOT IN FORCE:
  -- the guard's grade compares decisions with a multiplier they were not made under, and a threshold
  -- change argued from it is about the wrong rule. Also fires when two days pass after the columns
  -- existed and the plan has written no night since (no rule is being recorded at all).
  UNION ALL SELECT FORMAT('C10 every P-14c row written after %t stores its strong_day_mult and strong_day_min_orders, one rule per night, and the hint names the latest night\'s rule (today %s)',
                          legacy_through,
                          (SELECT FORMAT('%gx / %d order(s)', MAX(rule_value), MAX(rule_min_orders)) FROM sc_live WHERE row_type = 'RULE_HINT')),
         (SELECT COALESCE(SUM(n), 0) FROM v WHERE copy = 'LIVE' AND chk = 'C10')
  -- THE HINT'S WORDS HIDE THE GROUP IT ARGUED FROM: a WAIT that does not name the short group and its
  -- count, or a verdict sentence that opens with the total graded instead of the group size, so Ori
  -- reads "over 20 decisions" where the argument rests on one.
  UNION ALL SELECT 'C11 the RULE_HINT sentence names each short group and its count on a group WAIT, and opens with the group size on LOWER / RAISE / KEEP / NO_CLEAN_SIGNAL',
         (SELECT COALESCE(SUM(n), 0) FROM v WHERE copy = 'LIVE' AND chk = 'C11')
  -- THE REVIEW'S CASE COMES BACK: at the 2026-10-03 clock 20 graded decisions held 0 holds and, as the
  -- 46ae335 band counted it, 1 band row (a release whose hold clock had run out; the band leaves it
  -- out since the second follow-up and reads 0), and the old hint said KEEP from them. The function itself must
  -- WAIT there, name both groups, and count the band right (C13).
  UNION ALL SELECT FORMAT('C12 REAL CASE: FN_PLAN_SCORECARD at %t (%d graded, %d held, %d in the band, minimum %d each) reads %s, and C01-C04, C06-C09, C11, C13 hold on it (fires if the case no longer has 20 graded and a short group)',
                          d_case, (SELECT g FROM the_case), (SELECT held FROM the_case), (SELECT band FROM the_case),
                          (SELECT mn FROM the_case), (SELECT rec FROM the_case)),
         (SELECT COALESCE(SUM(n), 0) FROM v WHERE copy = 'CASE' AND chk IN ('C01', 'C02', 'C03', 'C04', 'C06', 'C07', 'C08', 'C09', 'C09T', 'C11', 'C13'))
       + IF((SELECT n FROM the_case) != 1, 1, 0)
       + IF(COALESCE((SELECT g FROM the_case), 0) < 20, 1, 0)
       + IF(COALESCE((SELECT LEAST(held, band) >= mn FROM the_case), TRUE), 1, 0)
       + IF(COALESCE((SELECT rec FROM the_case), '') != 'WAIT', 1, 0)
  -- THE SUITE IS GREEN ONLY BECAUSE TODAY IS EMPTY: with real guard decisions to grade, a check fails.
  UNION ALL SELECT FORMAT('CM POSITIVE CONTROL C01-C04, C06-C11, C13 hold on FN_PLAN_SCORECARD with the clock moved 30 days forward, on %d real guard decisions (fires if there are none, or if no graded release sits between 1.0x and its multiplier for C13 to count)',
                          (SELECT g FROM n_moved)),
         (SELECT COALESCE(SUM(n), 0) FROM v WHERE copy = 'MOVED' AND chk = 'C01') + (SELECT COALESCE(SUM(n), 0) FROM v WHERE copy = 'MOVED' AND chk = 'C02') + (SELECT COALESCE(SUM(n), 0) FROM v WHERE copy = 'MOVED' AND chk = 'C03') + (SELECT COALESCE(SUM(n), 0) FROM v WHERE copy = 'MOVED' AND chk = 'C04')
       + (SELECT COALESCE(SUM(n), 0) FROM v WHERE copy = 'MOVED' AND chk = 'C06') + (SELECT COALESCE(SUM(n), 0) FROM v WHERE copy = 'MOVED' AND chk = 'C07') + (SELECT COALESCE(SUM(n), 0) FROM v WHERE copy = 'MOVED' AND chk = 'C08') + (SELECT COALESCE(SUM(n), 0) FROM v WHERE copy = 'MOVED' AND chk IN ('C09', 'C09T'))
       + (SELECT COALESCE(SUM(n), 0) FROM v WHERE copy = 'MOVED' AND chk IN ('C10', 'C11', 'C13'))
       + IF((SELECT g FROM n_moved) = 0, 1, 0)
       + IF(COALESCE((SELECT n_band + n_expired + n_short_day FROM band_exp WHERE clock = 'MOVED'), 0) = 0, 1, 0)
  -- THE BAND HOLDS KEYWORDS A LOWER THRESHOLD WOULD NOT HAVE HELD: a release whose hold clock had run
  -- out is counted as evidence about the multiplier, the band reaches its 10-row minimum early, and
  -- LOWER_STRONG_DAY_MULT is argued from rows the threshold cannot affect.
  UNION ALL SELECT FORMAT('C13 the band counts exactly the graded releases a lower multiplier would have held under the rule in force, never one whose hold clock had run out (today + 30: %d in the band, %d left out for the clock; %t: %d and %d)',
                          (SELECT n_band FROM band_exp WHERE clock = 'MOVED'), (SELECT n_expired FROM band_exp WHERE clock = 'MOVED'),
                          d_case, (SELECT n_band FROM band_exp WHERE clock = 'CASE'), (SELECT n_expired FROM band_exp WHERE clock = 'CASE')),
         (SELECT COALESCE(SUM(n), 0) FROM v WHERE copy = 'LIVE' AND chk = 'C13')
  -- the negative controls: each doctored copy must FIRE its check (0 = it fired)
  UNION ALL SELECT 'C01a NEGATIVE CONTROL C01 FIRES: a GRADE row with no calendar state', IF((SELECT COALESCE(SUM(n), 0) FROM v WHERE copy = 'NC_C01' AND chk = 'C01') >= 1, 0, 1)
  UNION ALL SELECT 'C01b NEGATIVE CONTROL C01 FIRES: the RULE_HINT row with no sentence', IF((SELECT COALESCE(SUM(n), 0) FROM v WHERE copy = 'NC_C01S' AND chk = 'C01') >= 1, 0, 1)
  UNION ALL SELECT 'C02a NEGATIVE CONTROL C02 FIRES: a GRADE allocation of -1', IF((SELECT COALESCE(SUM(n), 0) FROM v WHERE copy = 'NC_C02' AND chk = 'C02') >= 1, 0, 1)
  UNION ALL SELECT 'C02b NEGATIVE CONTROL C02 FIRES: a GRADE allocation of NULL', IF((SELECT COALESCE(SUM(n), 0) FROM v WHERE copy = 'NC_C02Z' AND chk = 'C02') >= 1, 0, 1)
  UNION ALL SELECT 'C03a NEGATIVE CONTROL C03 FIRES: a recommendation doubled', IF((SELECT COALESCE(SUM(n), 0) FROM v WHERE copy = 'NC_C03D' AND chk = 'C03') >= 1, 0, 1)
  UNION ALL SELECT 'C03b NEGATIVE CONTROL C03 FIRES: a recommendation dropped', IF((SELECT COALESCE(SUM(n), 0) FROM v WHERE copy = 'NC_C03X' AND chk = 'C03') >= 1, 0, 1)
  UNION ALL SELECT 'C03c NEGATIVE CONTROL C03 FIRES: KEEP_B on one graded week', IF((SELECT COALESCE(SUM(n), 0) FROM v WHERE copy = 'NC_C03W' AND chk = 'C03') >= 1, 0, 1)
  UNION ALL SELECT 'C04a NEGATIVE CONTROL C04 FIRES: one family-night dropped', IF((SELECT COALESCE(SUM(n), 0) FROM v WHERE copy = 'NC_C04' AND chk = 'C04') >= 1, 0, 1)
  UNION ALL SELECT 'C05a NEGATIVE CONTROL C05 FIRES: one plan_* check missing from the board', IF((SELECT COALESCE(SUM(n), 0) FROM v WHERE copy = 'NC_C05D' AND chk = 'C05') >= 1, 0, 1)
  UNION ALL SELECT 'C05b NEGATIVE CONTROL C05 FIRES: one plan_* check RED', IF((SELECT COALESCE(SUM(n), 0) FROM v WHERE copy = 'NC_C05R' AND chk = 'C05') >= 1, 0, 1)
  UNION ALL SELECT 'C06a NEGATIVE CONTROL C06 FIRES: a GUARD class count off by one (moved clock)', IF((SELECT COALESCE(SUM(n), 0) FROM v WHERE copy = 'NC_C06C' AND chk = 'C06') >= 1, 0, 1)
  UNION ALL SELECT 'C06b NEGATIVE CONTROL C06 FIRES: a GUARD week total off by one (moved clock)', IF((SELECT COALESCE(SUM(n), 0) FROM v WHERE copy = 'NC_C06G' AND chk = 'C06') >= 1, 0, 1)
  UNION ALL SELECT 'C06c NEGATIVE CONTROL C06 FIRES: an empty GUARD where decisions are gradable', IF((SELECT COALESCE(SUM(n), 0) FROM v WHERE copy = 'NC_C06E' AND chk = 'C06') >= 1, 0, 1)
  UNION ALL SELECT 'C07a NEGATIVE CONTROL C07 FIRES: a family-night graded at 3 days old', IF((SELECT COALESCE(SUM(n), 0) FROM v WHERE copy = 'NC_C07' AND chk = 'C07') >= 1, 0, 1)
  UNION ALL SELECT 'C07b NEGATIVE CONTROL C07 FIRES: a guard week whose last window settles tomorrow (moved clock)', IF((SELECT COALESCE(SUM(n), 0) FROM v WHERE copy = 'NC_C07G' AND chk = 'C07') >= 1, 0, 1)
  UNION ALL SELECT 'C08a NEGATIVE CONTROL C08 FIRES: the youth sentence replaced by a count', IF((SELECT COALESCE(SUM(n), 0) FROM v WHERE copy = 'NC_C08' AND chk = 'C08') >= 1, 0, 1)
  UNION ALL SELECT 'C08b NEGATIVE CONTROL C08 FIRES: grades present that today\'s clock cannot have', IF((SELECT COALESCE(SUM(n), 0) FROM v WHERE copy = 'NC_C08G' AND chk = 'C08') >= 1, 0, 1)
  UNION ALL SELECT 'C09a NEGATIVE CONTROL C09 FIRES: the hint leaves WAIT below 20', IF((SELECT COALESCE(SUM(n), 0) FROM v WHERE copy = 'NC_C09' AND chk = 'C09') >= 1, 0, 1)
  UNION ALL SELECT 'C09b NEGATIVE CONTROL C09 FIRES: the hint row doubled', IF((SELECT COALESCE(SUM(n), 0) FROM v WHERE copy = 'NC_C09D' AND chk = 'C09') >= 1, 0, 1)
  UNION ALL SELECT 'C09c NEGATIVE CONTROL C09 FIRES: 117 graded, 12 held, ONE band row, reading KEEP (moved clock)', IF((SELECT COALESCE(SUM(n), 0) FROM v WHERE copy = 'NC_C09B' AND chk = 'C09') >= 1, 0, 1)
  UNION ALL SELECT 'C09d NEGATIVE CONTROL C09 FIRES: 117 graded, ONE held, 12 band rows, reading KEEP (moved clock)', IF((SELECT COALESCE(SUM(n), 0) FROM v WHERE copy = 'NC_C09H' AND chk = 'C09') >= 1, 0, 1)
  UNION ALL SELECT 'C09e NEGATIVE CONTROL C09 FIRES: a held group one larger than the graded holds (moved clock)', IF((SELECT COALESCE(SUM(n), 0) FROM v WHERE copy = 'NC_C09G' AND chk = 'C09T') >= 1, 0, 1)
  UNION ALL SELECT 'C10a NEGATIVE CONTROL C10 FIRES: a night after the columns existed with no rule on its rows', IF((SELECT COALESCE(SUM(n), 0) FROM v WHERE copy = 'NC_C10N' AND chk = 'C10') >= 1, 0, 1)
  UNION ALL SELECT 'C10b NEGATIVE CONTROL C10 FIRES: a night carrying two rules', IF((SELECT COALESCE(SUM(n), 0) FROM v WHERE copy = 'NC_C10M' AND chk = 'C10') >= 1, 0, 1)
  UNION ALL SELECT 'C10c NEGATIVE CONTROL C10 FIRES: a latest night whose stored rule is not the hint\'s rule_value', IF((SELECT COALESCE(SUM(n), 0) FROM v WHERE copy = 'NC_C10V' AND chk = 'C10') >= 1, 0, 1)
  UNION ALL SELECT 'C10d NEGATIVE CONTROL C10 FIRES: two days after the columns existed, no night written since', IF((SELECT COALESCE(SUM(n), 0) FROM v WHERE copy = 'NC_C10E' AND chk = 'C10') >= 1, 0, 1)
  UNION ALL SELECT 'C11a NEGATIVE CONTROL C11 FIRES: a group WAIT that names neither short group (moved clock)', IF((SELECT COALESCE(SUM(n), 0) FROM v WHERE copy = 'NC_C11W' AND chk = 'C11') >= 1, 0, 1)
  UNION ALL SELECT 'C11b NEGATIVE CONTROL C11 FIRES: a KEEP that opens with the total graded, the old sentence (moved clock)', IF((SELECT COALESCE(SUM(n), 0) FROM v WHERE copy = 'NC_C11K' AND chk = 'C11') >= 1, 0, 1)
  UNION ALL SELECT 'C13a NEGATIVE CONTROL C13 FIRES: the 2026-10-03 band with its expired-clock release counted back in, as 46ae335 counted it', IF((SELECT COALESCE(SUM(n), 0) FROM v WHERE copy = 'NC_C13' AND chk = 'C13') >= 1, 0, 1)
)
SELECT check_name, violations, IF(violations = 0, 'PASS', 'FAIL') AS result
FROM checks
ORDER BY check_name;
