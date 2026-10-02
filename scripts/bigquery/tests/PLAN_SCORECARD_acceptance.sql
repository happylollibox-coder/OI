-- =============================================================================================
-- PLAN_SCORECARD acceptance — v27.154 (2026-10-01). V_PLAN_SCORECARD / FN_PLAN_SCORECARD (plan
-- Task 5's grade) and the nine plan_* checks Task A put on V_ENGINE_HEALTH. EVERY ROW MUST READ PASS.
--   bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "$(grep -v '^--' FILE)"
-- Objects: scripts/bigquery/functions/FN_PLAN_SCORECARD.sql, scripts/bigquery/views/V_PLAN_SCORECARD.sql.
-- SOP: architecture/NEXT_WEEK_MONEY.md §6 "Grading". Spec §5, P-9, P-13, P-14b/c.
--
-- WHY THE SUITE CANNOT PASS ON EMPTINESS. On 2026-10-01 the scorecard is young: one graded week
-- (the August nights), every RECOMMENDATION is WAIT, and no guard decision has settled (the guard
-- columns exist from the 2026-09-28 partition; the first window settles 2026-10-03). The draft
-- suite passed an empty scorecard by construction. Here:
--   * C04 and C08 hold the scorecard to what the plan history makes gradable, re-derived from
--     FACT_PLAN_NEXT_WEEK in this file — "empty because young" passes, "empty because broken" fails;
--   * every check also runs on FN_PLAN_SCORECARD with the clock moved 30 days forward (row CM),
--     where the guard has real decisions to partition and the hint leaves WAIT;
--   * every check has a NEGATIVE CONTROL run as a standing row: the same expression over a doctored
--     temp copy must FIRE (the row reads PASS when it fired). A control with nothing to doctor reads
--     FAIL, never a quiet PASS.
--
-- THE CHECK EXPRESSIONS ARE WRITTEN ONCE, over sc_copies (one tagged copy per scenario), and each
-- copy is judged against the expectation of its own clock (LIVE = today in Los Angeles, MOVED =
-- today + 30). Twins of the function kept in this file, which must change with it: the gradable-
-- decision predicate (exp_g), the one-night-per-Sunday-week rule (exp_fw), the 20-decision hint
-- threshold (C09) and the 3-week recommendation threshold (C03).
--
-- COST, measured 2026-10-01 at deploy (uncached): V_PLAN_SCORECARD 354 slot-s / 70.8 MB / 4.6 s;
-- FN_PLAN_SCORECARD at today + 30 391 slot-s. The nine plan_* rows of V_ENGINE_HEALTH are read by
-- NAME (56 slot-s): a filter on check_name prunes the board's other arms, while the whole board read
-- uncached the same day cost 67,639 slot-s.
--
-- The whole suite, measured 2026-10-01 (uncached script, 16 child jobs): 727 slot-s, 52 s.
--
-- RUN 2026-10-01 (Los Angeles), first deploy: 31 rows, every one PASS. The intermediate
-- violation table (copy x check) was then printed from the same temp tables, so each PASS below is
-- a control that FIRED or a live reading of 0 with something under it — not a vacuous one:
--   LIVE and MOVED read 0 on every check (C01-C10; C05 and C10 on LIVE only).
--   C01: NC_C01 (a GRADE row's calendar_state NULL) 1; NC_C01S (the RULE_HINT sentence NULL) 1.
--   C02: NC_C02 (allocation -1) 1; NC_C02Z (allocation NULL) 1.
--   C03: NC_C03D (a recommendation doubled) 1; NC_C03X (dropped) 1; NC_C03W (KEEP_B on 1 week) 1.
--   C04: NC_C04 (one family-night dropped) 1. Expectation today: 1 graded night (2026-08-28, the
--        week of 2026-08-23), 4 family-nights; at today + 30: 8 family-nights (2 weeks).
--   C05: the nine plan_* checks were on the board, none RED (INFO x3, GREEN x6); NC_C05D (one
--        removed) 1; NC_C05R (one set RED) 1.
--   C06: LIVE 0 with 0 decisions gradable (117 written since 2026-09-28: 9 held, 108 released;
--        first settle date 2026-10-03); MOVED 0 on 117 graded decisions in one week, four class rows;
--        NC_C06C (a class count +1) 1; NC_C06G (the week total +1 on all four rows) 5; NC_C06E
--        (today's empty GUARD against the moved clock's 117 gradable decisions) 1.
--   C07: NC_C07 (a family-night 3 days old) 1; NC_C07G (a guard week settling tomorrow) 1.
--   C08: LIVE 0 — the RULE_HINT row counts 0 and its sentence starts 'WAIT: no guard decision is
--        old enough to grade yet' and names 2026-10-03; NC_C08 (sentence replaced by a count) 1;
--        NC_C08G (the moved grades against today's clock) 2.
--   C09: NC_C09 (LOWER_STRONG_DAY_MULT with 0 graded) 1; NC_C09D (the hint row doubled) 1.
--   C10: 1,444 live P-14c rows (86 with last_day_strong) all agree with rule_value 1.5 and the
--        one-order minimum; NC_C10 (one row's flag flipped) 1.
--   CM: 117 real guard decisions graded at today + 30; every check 0 on that copy.
-- =============================================================================================
DECLARE d0  DATE DEFAULT CURRENT_DATE('America/Los_Angeles');
DECLARE d30 DATE DEFAULT DATE_ADD(CURRENT_DATE('America/Los_Angeles'), INTERVAL 30 DAY);

-- ---- the scorecard, read once at today and once with the clock moved 30 days forward ----
CREATE TEMP TABLE sc_live AS
  SELECT *, ROW_NUMBER() OVER (PARTITION BY row_type
                               ORDER BY family, calendar_state, plan, week_start, graded_night, outcome_class) AS rn
  FROM `onyga-482313.OI.V_PLAN_SCORECARD`;
CREATE TEMP TABLE sc_moved AS
  SELECT *, ROW_NUMBER() OVER (PARTITION BY row_type
                               ORDER BY family, calendar_state, plan, week_start, graded_night, outcome_class) AS rn
  FROM `onyga-482313.OI.FN_PLAN_SCORECARD`(d30);

-- ---- what the plan history makes gradable, per clock (TWINS of the function's rules) ----
CREATE TEMP TABLE clock_dates AS
  SELECT 'LIVE' AS clock, d0 AS d UNION ALL SELECT 'MOVED', d30;
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

-- ---- the copies: LIVE and MOVED, and one doctored copy per negative control ----
CREATE TEMP TABLE sc_copies AS
            SELECT 'LIVE'      AS copy, 'LIVE'  AS clock, * FROM sc_live
  UNION ALL SELECT 'MOVED',              'MOVED', * FROM sc_moved
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
  UNION ALL SELECT 'NC_C09D', 'LIVE', * FROM sc_live WHERE row_type = 'RULE_HINT';
-- the copies, listed explicitly: a copy that came back EMPTY still gets judged (and fails C01)
CREATE TEMP TABLE copies AS
  SELECT copy, clock FROM UNNEST([
    STRUCT('LIVE' AS copy, 'LIVE' AS clock), ('MOVED', 'MOVED'),
    ('NC_C01', 'LIVE'), ('NC_C01S', 'LIVE'), ('NC_C02', 'LIVE'), ('NC_C02Z', 'LIVE'),
    ('NC_C03D', 'LIVE'), ('NC_C03X', 'LIVE'), ('NC_C03W', 'LIVE'), ('NC_C04', 'LIVE'),
    ('NC_C06C', 'MOVED'), ('NC_C06G', 'MOVED'), ('NC_C06E', 'MOVED'),
    ('NC_C07', 'LIVE'), ('NC_C07G', 'MOVED'), ('NC_C08', 'LIVE'), ('NC_C08G', 'LIVE'),
    ('NC_C09', 'LIVE'), ('NC_C09D', 'LIVE')]);

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

-- ---- C10: the plan's own last_day_strong against the threshold the scorecard grades on ----
CREATE TEMP TABLE p14c AS
  SELECT as_of, campaign_id, keyword_id, last_day_strong, last_day_ord, last_day_ret, family_bar,
         ROW_NUMBER() OVER (ORDER BY as_of, campaign_id, keyword_id) AS rn
  FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK`
  WHERE is_live_plan AND last_day_strong IS NOT NULL;
CREATE TEMP TABLE p14c_copies AS
            SELECT 'LIVE' AS copy, * FROM p14c
  UNION ALL SELECT 'NC_C10', * REPLACE (IF(rn = 1, NOT last_day_strong, last_day_strong) AS last_day_strong) FROM p14c;

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
-- C09 one hint row; WAIT iff under 20 graded decisions (twin: 20); its counts are the GUARD weeks' totals
SELECT k.copy, 'C09',
       IF(COUNT(h.copy) != 1, 1, 0)
     + COUNTIF(h.copy IS NOT NULL AND (h.graded_rows < 20) != (h.recommendation = 'WAIT'))
     + COUNTIF(h.copy IS NOT NULL AND h.recommendation NOT IN ('WAIT', 'KEEP_STRONG_DAY_MULT', 'LOWER_STRONG_DAY_MULT',
                                                               'RAISE_STRONG_DAY_MULT', 'NO_CLEAN_SIGNAL'))
     + COUNTIF(h.copy IS NOT NULL
               AND NOT COALESCE(h.held_right + h.held_wrong + h.released_right + h.released_wrong = h.graded_rows
                                AND h.graded_rows    = COALESCE(t.g, 0)
                                AND h.held_right     = COALESCE(t.hr, 0) AND h.held_wrong     = COALESCE(t.hw, 0)
                                AND h.released_right = COALESCE(t.rr, 0) AND h.released_wrong = COALESCE(t.rw, 0), FALSE))
FROM copies k
LEFT JOIN (SELECT * FROM sc_copies WHERE row_type = 'RULE_HINT') h USING (copy)
LEFT JOIN (SELECT copy, SUM(g) AS g, SUM(hr) AS hr, SUM(hw) AS hw, SUM(rr) AS rr, SUM(rw) AS rw
           FROM (SELECT copy, week_start, MAX(graded_rows) AS g, MAX(held_right) AS hr, MAX(held_wrong) AS hw,
                        MAX(released_right) AS rr, MAX(released_wrong) AS rw
                 FROM sc_copies WHERE row_type = 'GUARD' GROUP BY 1, 2)
           GROUP BY 1) t USING (copy)
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
-- C10 the plan's last_day_strong agrees with the scorecard's rule_value on every P-14c row
SELECT k_copy, 'C10',
       COUNTIF(p.last_day_strong != (p.last_day_ord >= 1
                                     AND COALESCE(p.last_day_ret, -1) >= p.family_bar * r.rule_value))
     + IF(COUNT(p.copy) = 0, 1, 0)
     + IF(MAX(r.rule_value) IS NULL, 1, 0)
FROM UNNEST(['LIVE', 'NC_C10']) AS k_copy
CROSS JOIN (SELECT MAX(rule_value) AS rule_value FROM sc_live WHERE row_type = 'RULE_HINT') r
LEFT JOIN p14c_copies p ON p.copy = k_copy
GROUP BY k_copy;

-- a (copy, check) absent from vlist means every grouped term had no input row: zero violations from
-- those terms. Each check also carries a term driven from the explicit copy list, so an EMPTY copy
-- is still judged (C01, C02, C07, C08, C09, C05 and C10 read their copies from a list, not from data).
CREATE TEMP TABLE v AS SELECT copy, chk, SUM(n) AS n FROM vlist GROUP BY 1, 2;
WITH
n_moved AS (SELECT COALESCE(MAX(graded_rows), 0) AS g FROM sc_moved WHERE row_type = 'RULE_HINT'),
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
  -- THE HINT SPEAKS TOO EARLY OR DISAGREES WITH ITS OWN ROWS: a threshold change argued from five
  -- decisions, or a hint whose counts are not the GUARD rows Ori can read.
  UNION ALL SELECT 'C09 one RULE_HINT row; WAIT iff fewer than 20 graded decisions; its counts equal the GUARD weeks\' totals',
         (SELECT COALESCE(SUM(n), 0) FROM v WHERE copy = 'LIVE' AND chk = 'C09')
  -- THE THRESHOLD MOVED AND THE GRADE DID NOT: the hint grades the band below 1.5x while the plan
  -- holds on a different multiple, and its advice is about a rule no longer in force.
  UNION ALL SELECT 'C10 the plan\'s own last_day_strong agrees with the strong_day_mult the scorecard grades on (rule_value), on every P-14c row',
         (SELECT COALESCE(SUM(n), 0) FROM v WHERE copy = 'LIVE' AND chk = 'C10')
  -- THE SUITE IS GREEN ONLY BECAUSE TODAY IS EMPTY: with real guard decisions to grade, a check fails.
  UNION ALL SELECT FORMAT('CM POSITIVE CONTROL C01-C04 and C06-C09 hold on FN_PLAN_SCORECARD with the clock moved 30 days forward, on %d real guard decisions (fires if there are none)',
                          (SELECT g FROM n_moved)),
         (SELECT COALESCE(SUM(n), 0) FROM v WHERE copy = 'MOVED' AND chk = 'C01') + (SELECT COALESCE(SUM(n), 0) FROM v WHERE copy = 'MOVED' AND chk = 'C02') + (SELECT COALESCE(SUM(n), 0) FROM v WHERE copy = 'MOVED' AND chk = 'C03') + (SELECT COALESCE(SUM(n), 0) FROM v WHERE copy = 'MOVED' AND chk = 'C04')
       + (SELECT COALESCE(SUM(n), 0) FROM v WHERE copy = 'MOVED' AND chk = 'C06') + (SELECT COALESCE(SUM(n), 0) FROM v WHERE copy = 'MOVED' AND chk = 'C07') + (SELECT COALESCE(SUM(n), 0) FROM v WHERE copy = 'MOVED' AND chk = 'C08') + (SELECT COALESCE(SUM(n), 0) FROM v WHERE copy = 'MOVED' AND chk = 'C09')
       + IF((SELECT g FROM n_moved) = 0, 1, 0)
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
  UNION ALL SELECT 'C10a NEGATIVE CONTROL C10 FIRES: one P-14c row\'s last_day_strong flipped', IF((SELECT COALESCE(SUM(n), 0) FROM v WHERE copy = 'NC_C10' AND chk = 'C10') >= 1, 0, 1)
)
SELECT check_name, violations, IF(violations = 0, 'PASS', 'FAIL') AS result
FROM checks
ORDER BY check_name;
